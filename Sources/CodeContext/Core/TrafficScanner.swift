// Exey Panteleev
// Detects inbound and outbound connection signals in Swift/ObjC source files.
//
// Outbound:
//   - HTTP/HTTPS/WS/WSS URL string literals
//   - NWConnection (Network.framework TCP client)
//   - NWPathMonitor (TCP reachability monitoring)
//   - SCNetworkReachabilityCreateWithName/Address (SystemConfiguration)
//   - BSD POSIX socket() with SOCK_STREAM (TCP)
//   - CFStreamCreatePairWithSocketToHost (Core Foundation TCP stream)
//
// Inbound:
//   - Vapor-style route definitions (app.get, routes.post, …)
//   - NWListener (Network.framework TCP server)
//
// Detection is a single-pass line scanner.
// Entries are deduplicated by (uri, proto, module) before being returned.

import Foundation

// MARK: - Traffic Entry

struct TrafficEntry {
    let uri: String
    let port: String
    let proto: String    // REST, WebSocket, gRPC, GraphQL, TCP, …
    let dataFmt: String  // JSON, Protobuf, XML, or ""
    let filePath: String
    let line: Int
    let module: String
}

// MARK: - Traffic Result

struct TrafficResult {
    var inbound: [TrafficEntry] = []
    var outbound: [TrafficEntry] = []
    var hasData: Bool { !inbound.isEmpty || !outbound.isEmpty }
}

// MARK: - Traffic Scanner

struct TrafficScanner {

    // Extensions that are pure declarations / documentation — never contain runtime URL calls.
    private static let skipExtensions: Set<String> = ["h", "hpp", "hh", "hxx"]

    // File names that hold package metadata rather than app source.
    private static let skipFileNames: Set<String> = [
        "Package.swift", "Package.resolved", "Project.swift", "Podfile",
    ]

    // File name suffixes that indicate test, spec, or project-generation code.
    // URLs in these files are fixture data, not runtime connections.
    private static let skipSuffixes: [String] = [
        "Tests.swift", "Test.swift", "Spec.swift", "Specs.swift",
        "TestCase.swift", "UITests.swift",
    ]

    // Path components that identify test / spec / tooling directories.
    private static let skipPathComponents: [String] = [
        "/Tests/", "/Test/", "/Specs/", "/Spec/", "/UITests/",
        "/UnitTests/", "/IntegrationTests/", "/TestHelpers/",
        "/Fixtures/", "/Mocks/", "/Stubs/", "/ProjectSpec/",
    ]

    func scan(files: [ParsedFile]) -> TrafficResult {
        var result = TrafficResult()
        var seenIn  = Set<String>()
        var seenOut = Set<String>()

        for file in files {
            let url      = URL(fileURLWithPath: file.filePath)
            let fileName = url.lastPathComponent
            let ext      = url.pathExtension.lowercased()

            if Self.skipFileNames.contains(fileName) { continue }
            if Self.skipExtensions.contains(ext)     { continue }
            if Self.skipSuffixes.contains(where: { fileName.hasSuffix($0) }) { continue }
            if Self.skipPathComponents.contains(where: { file.filePath.contains($0) }) { continue }

            guard let content = try? String(contentsOfFile: file.filePath, encoding: .utf8) else { continue }
            let mod = file.moduleName.isEmpty
                ? (file.packageName.isEmpty ? "root" : file.packageName)
                : file.moduleName

            var inBlockComment = false

            for (idx, rawLine) in content.components(separatedBy: "\n").enumerated() {
                let lineNum = idx + 1
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

                // Track /* … */ block comment state
                if inBlockComment {
                    if trimmed.contains("*/") { inBlockComment = false }
                    continue
                }
                if trimmed.hasPrefix("/*") {
                    if !trimmed.contains("*/") { inBlockComment = true }
                    continue
                }
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                // Inbound: Vapor / server-side Swift route definitions
                if let entry = detectVaporRoute(line: trimmed, filePath: file.filePath, lineNum: lineNum, module: mod) {
                    let key = "\(entry.uri)|\(entry.proto)|\(mod)"
                    if seenIn.insert(key).inserted { result.inbound.append(entry) }
                    continue
                }

                // Inbound: TCP listeners
                if let entry = detectTCPInbound(line: trimmed, filePath: file.filePath, lineNum: lineNum, module: mod) {
                    let key = "\(entry.uri)|\(entry.proto)|\(mod)"
                    if seenIn.insert(key).inserted { result.inbound.append(entry) }
                }

                // Outbound: HTTP/WS URL string literals
                for entry in detectOutboundURLs(line: trimmed, filePath: file.filePath, lineNum: lineNum, module: mod) {
                    let key = "\(entry.uri)|\(entry.proto)|\(mod)"
                    if seenOut.insert(key).inserted { result.outbound.append(entry) }
                }

                // Outbound: TCP connections (NWConnection, SCNetworkReachability, BSD socket, CFStream)
                if let entry = detectTCPOutbound(line: trimmed, filePath: file.filePath, lineNum: lineNum, module: mod) {
                    let key = "\(entry.uri)|\(entry.proto)|\(mod)"
                    if seenOut.insert(key).inserted { result.outbound.append(entry) }
                }
            }
        }

        // Protocol sort order: TCP first (transport-layer primitives), then alphabetical
        func protoRank(_ p: String) -> Int { p == "TCP" ? 0 : 1 }
        result.inbound.sort  { $0.uri < $1.uri }
        result.outbound.sort {
            let ra = protoRank($0.proto), rb = protoRank($1.proto)
            if ra != rb { return ra < rb }
            if $0.proto != $1.proto { return $0.proto < $1.proto }
            return $0.uri < $1.uri
        }
        return result
    }

    // MARK: - Inbound (Vapor routes)

    private func detectVaporRoute(line: String, filePath: String, lineNum: Int, module: String) -> TrafficEntry? {
        let httpMethods = ["get", "post", "put", "patch", "delete", "on"]
        let prefixes    = ["app.", "routes.", "router.", "grouped."]
        let low = line.lowercased()

        for prefix in prefixes {
            guard low.contains(prefix) else { continue }
            for method in httpMethods {
                let marker = prefix + method + "("
                guard let markerRange = low.range(of: marker) else { continue }
                let after = String(line[markerRange.upperBound...])
                guard let path = firstStringLiteral(in: after), path.hasPrefix("/") else { continue }
                return TrafficEntry(uri: path, port: "", proto: "REST", dataFmt: "JSON",
                                    filePath: filePath, line: lineNum, module: module)
            }
        }
        return nil
    }

    // MARK: - Inbound (TCP listeners)

    private func detectTCPInbound(line: String, filePath: String, lineNum: Int, module: String) -> TrafficEntry? {
        // Network.framework — NWListener TCP server
        if line.contains("NWListener(") {
            let port = extractTCPPort(from: line)
            let uri  = port.isEmpty ? "NWListener" : ":\(port)"
            return TrafficEntry(uri: uri, port: port, proto: "TCP", dataFmt: "",
                                filePath: filePath, line: lineNum, module: module)
        }
        return nil
    }

    // MARK: - Outbound (HTTP/WS URL literals)

    private func detectOutboundURLs(line: String, filePath: String, lineNum: Int, module: String) -> [TrafficEntry] {
        var entries: [TrafficEntry] = []
        var pos = line.startIndex

        while pos < line.endIndex {
            guard let q1 = line[pos...].firstIndex(of: "\"") else { break }
            let contentStart = line.index(after: q1)
            guard contentStart < line.endIndex else { break }
            guard let q2 = line[contentStart...].firstIndex(of: "\"") else { break }

            let literal = String(line[contentStart..<q2])

            let isHTTP = literal.hasPrefix("http://") || literal.hasPrefix("https://")
            let isWS   = literal.hasPrefix("ws://")   || literal.hasPrefix("wss://")

            if (isHTTP || isWS) && literal.count >= 10 {
                let proto  = isWS ? "WebSocket" : detectProtocol(line: line, uri: literal)
                let fmt    = isWS ? "" : detectDataFormat(line: line)
                let port   = extractPort(from: literal)
                entries.append(TrafficEntry(uri: literal, port: port, proto: proto, dataFmt: fmt,
                                            filePath: filePath, line: lineNum, module: module))
            }

            pos = line.index(after: q2)
        }
        return entries
    }

    // MARK: - Outbound (TCP connections)

    private func detectTCPOutbound(line: String, filePath: String, lineNum: Int, module: String) -> TrafficEntry? {
        // Network.framework — NWConnection TCP client
        if line.contains("NWConnection(") {
            let host = firstStringLiteral(in: line) ?? ""
            let port = extractTCPPort(from: line)
            let uri  = host.isEmpty ? "NWConnection" : (port.isEmpty ? host : "\(host):\(port)")
            return TrafficEntry(uri: uri, port: port, proto: "TCP", dataFmt: "",
                                filePath: filePath, line: lineNum, module: module)
        }

        // Network.framework — NWPathMonitor TCP path/reachability monitoring
        if line.contains("NWPathMonitor(") {
            return TrafficEntry(uri: "NWPathMonitor", port: "", proto: "TCP", dataFmt: "",
                                filePath: filePath, line: lineNum, module: module)
        }

        // SystemConfiguration — SCNetworkReachability TCP probe (deprecated but common)
        if line.contains("SCNetworkReachabilityCreateWithName") || line.contains("SCNetworkReachabilityCreateWithAddress") {
            let host = firstStringLiteral(in: line) ?? ""
            let uri  = host.isEmpty ? "SCNetworkReachability" : host
            return TrafficEntry(uri: uri, port: "", proto: "TCP", dataFmt: "",
                                filePath: filePath, line: lineNum, module: module)
        }

        // BSD POSIX — TCP socket creation via SOCK_STREAM
        let low = line.lowercased()
        if low.contains("sock_stream") && (low.contains("af_inet") || low.contains("af_inet6") || low.contains("pf_inet")) {
            return TrafficEntry(uri: "BSD socket", port: "", proto: "TCP", dataFmt: "",
                                filePath: filePath, line: lineNum, module: module)
        }

        // Core Foundation — CFStreamCreatePairWithSocketToHost TCP stream
        if line.contains("CFStreamCreatePairWithSocketToHost") {
            let host = firstStringLiteral(in: line) ?? ""
            let port = extractTCPPort(from: line)
            let uri  = host.isEmpty ? "CFStream" : (port.isEmpty ? host : "\(host):\(port)")
            return TrafficEntry(uri: uri, port: port, proto: "TCP", dataFmt: "",
                                filePath: filePath, line: lineNum, module: module)
        }

        return nil
    }

    // MARK: - Helpers

    private func firstStringLiteral(in s: String) -> String? {
        guard let open = s.firstIndex(of: "\"") else { return nil }
        let after = s[s.index(after: open)...]
        guard let close = after.firstIndex(of: "\"") else { return nil }
        return String(after[after.startIndex..<close])
    }

    private func detectProtocol(line: String, uri: String) -> String {
        let low = line.lowercased()
        if low.contains("grpc")      { return "gRPC" }
        if low.contains("graphql")   { return "GraphQL" }
        if low.contains("websocket") { return "WebSocket" }
        return "REST"
    }

    private func detectDataFormat(line: String) -> String {
        let low = line.lowercased()
        if low.contains("protobuf") || low.contains(".proto") { return "Protobuf" }
        if low.contains("xml")                                { return "XML" }
        if low.contains("json") || low.contains("codable") || low.contains("decodable") { return "JSON" }
        return ""
    }

    // Extracts port from a URL string literal: scheme://host:PORT/path
    private func extractPort(from uri: String) -> String {
        guard let schemeEnd = uri.range(of: "://")?.upperBound else { return "" }
        let hostPart = String(uri[schemeEnd...])
        let hostEnd  = hostPart.firstIndex(of: "/") ?? hostPart.endIndex
        let host     = String(hostPart[hostPart.startIndex..<hostEnd])
        if let colonIdx = host.lastIndex(of: ":") {
            let portStr = String(host[host.index(after: colonIdx)...])
            if portStr.allSatisfy(\.isNumber) { return portStr }
        }
        return ""
    }

    // Extracts port from TCP API call patterns: rawValue: 443, on: 8080, Port(8080), etc.
    private func extractTCPPort(from line: String) -> String {
        for label in ["rawValue:", "NWEndpoint.Port(", "port:", " on:"] {
            guard let r = line.range(of: label) else { continue }
            let tail   = line[r.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
            let digits = String(tail.prefix(while: { $0.isNumber }))
            if let n = Int(digits), n > 0 && n <= 65535 { return digits }
        }
        return ""
    }
}
