// Exey Panteleev
import Foundation

// MARK: - Dependency Graph

/// Directed dependency graph with PageRank scoring.
final class DependencyGraph: @unchecked Sendable {

    private(set) var vertices: Set<String> = []
    private(set) var edges: [(source: String, target: String)] = []
    private var adjacency: [String: Set<String>] = [:]
    private var reverseAdj: [String: Set<String>] = [:]
    private(set) var pageRankScores: [String: Double] = [:]
    private(set) var hasCycles: Bool = false

    // MARK: - Build

    func build(from parsedFiles: [ParsedFile], bridgingHeaderPath: String = "") {
        let startTime = CFAbsoluteTimeGetCurrent()
        var nameToPath: [String: String] = [:]

        print("\(ts())  Registering \(parsedFiles.count) vertices...")
        for file in parsedFiles {
            addVertex(file.filePath)
            nameToPath[file.fileNameWithoutExtension] = file.filePath
            if !file.moduleName.isEmpty {
                nameToPath[file.moduleName] = file.filePath
            }
        }

        // Import-based edges (cross-module)
        print("\(ts())  Building import-based edges...")
        for source in parsedFiles {
            for importName in source.imports {
                let baseName = importName.components(separatedBy: ".").last ?? importName
                if let targetPath = nameToPath[importName] ?? nameToPath[baseName] {
                    addEdge(from: source.filePath, to: targetPath)
                }
            }
        }
        let importEdges = edges.count
        let t1 = CFAbsoluteTimeGetCurrent() - startTime
        print("\(ts())  Import edges: \(importEdges) (\(String(format: "%.1f", t1))s)")

        // Type-reference edges (intra-module) — capped for performance
        print("\(ts())  Building type-reference edges...")
        buildTypeReferenceEdges(from: parsedFiles)
        let typeRefEdges = edges.count - importEdges
        let t2 = CFAbsoluteTimeGetCurrent() - startTime
        print("\(ts())  Type-reference edges: \(typeRefEdges) (\(String(format: "%.1f", t2))s)")

        // ObjC/Swift interop edges via bridging header
        if !bridgingHeaderPath.isEmpty {
            let preInterop = edges.count
            buildInteropEdges(from: parsedFiles, bridgingHeaderPath: bridgingHeaderPath)
            let interopEdges = edges.count - preInterop
            if interopEdges > 0 {
                print("\(ts())  Interop edges: \(interopEdges) (bridging header hub)")
            }
        }

        print("\(ts())  Detecting cycles...")
        detectCycles()

        let t3 = CFAbsoluteTimeGetCurrent() - startTime
        print("\(ts())  Graph complete: \(vertices.count) nodes, \(edges.count) edges (\(String(format: "%.1f", t3))s)")
    }

    /// Build edges based on type references within each package.
    /// Optimized: tokenize files into identifier sets once, then O(1) hash lookups per type check.
    private func buildTypeReferenceEdges(from parsedFiles: [ParsedFile]) {
        var byPackage: [String: [ParsedFile]] = [:]
        for file in parsedFiles {
            let key = file.packageName.isEmpty ? "__app__" : file.packageName
            byPackage[key, default: []].append(file)
        }

        let totalPackages = byPackage.count
        print("\(ts())  Scanning type references across \(totalPackages) modules (parallel)...")

        // Pre-read all file contents in parallel, then tokenize into identifier sets.
        // Each file is tokenized once; type-name checks become O(1) hash lookups.
        let allPaths = parsedFiles.map(\.filePath)
        var rawContents: [String?] = Array(repeating: nil, count: allPaths.count)
        DispatchQueue.concurrentPerform(iterations: allPaths.count) { idx in
            rawContents[idx] = try? String(contentsOfFile: allPaths[idx], encoding: .utf8)
        }
        var tokenSetsArr: [Set<String>?] = Array(repeating: nil, count: allPaths.count)
        DispatchQueue.concurrentPerform(iterations: allPaths.count) { idx in
            guard let content = rawContents[idx] else { return }
            tokenSetsArr[idx] = tokenizeIdentifiers(content)
        }
        rawContents = [] // free raw strings; token sets are all we need

        var tokenCache: [String: Set<String>] = [:]
        tokenCache.reserveCapacity(allPaths.count)
        for (idx, path) in allPaths.enumerated() {
            if let t = tokenSetsArr[idx] { tokenCache[path] = t }
        }
        tokenSetsArr = []

        // Sort packages largest-first so big packages start early and don't become stragglers
        let packagesArray = byPackage
            .map { (name: $0.key, files: $0.value) }
            .sorted { $0.files.reduce(0) { $0 + $1.lineCount } > $1.files.reduce(0) { $0 + $1.lineCount } }
        var localEdgesPerPkg: [[(String, String)]] = Array(repeating: [], count: packagesArray.count)

        var completedCount = 0
        let progressLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: packagesArray.count) { pkgIdx in
            let pkgStart = CFAbsoluteTimeGetCurrent()
            let (pkgName, packageFiles) = (packagesArray[pkgIdx].name, packagesArray[pkgIdx].files)
            let cappedFiles: [ParsedFile] = packageFiles.count > 3000
                ? Array(packageFiles.sorted { $0.lineCount > $1.lineCount }.prefix(3000))
                : packageFiles

            var typeToFile: [(name: String, path: String)] = []
            for file in cappedFiles {
                for decl in file.declarations where decl.kind != .extension && decl.name.count >= 4 && !Declaration.invalidNames.contains(decl.name) {
                    typeToFile.append((name: decl.name, path: file.filePath))
                }
            }
            guard !typeToFile.isEmpty else {
                progressLock.lock(); completedCount += 1; progressLock.unlock()
                return
            }

            if typeToFile.count > 5000 {
                let topPaths = Set(cappedFiles.prefix(1000).map(\.filePath))
                typeToFile = typeToFile.filter { topPaths.contains($0.path) }
            }

            // Inner parallelism: parallelize over files within this package.
            // Each slot is written by exactly one thread — no lock needed.
            var perFileEdges: [[(String, String)]] = Array(repeating: [], count: cappedFiles.count)
            DispatchQueue.concurrentPerform(iterations: cappedFiles.count) { fileIdx in
                let file = cappedFiles[fileIdx]
                guard let tokens = tokenCache[file.filePath] else { return }
                var localEdges: [(String, String)] = []
                // Track which target files already have an edge from this source,
                // so we stop after the first matching type per (source→target) pair.
                var seenTargets = Set<String>()
                for (typeName, declPath) in typeToFile {
                    guard declPath != file.filePath, !seenTargets.contains(declPath) else { continue }
                    if tokens.contains(typeName) {
                        localEdges.append((file.filePath, declPath))
                        seenTargets.insert(declPath)
                    }
                }
                perFileEdges[fileIdx] = localEdges
            }
            localEdgesPerPkg[pkgIdx] = perFileEdges.flatMap { $0 }

            let pkgElapsed = CFAbsoluteTimeGetCurrent() - pkgStart

            progressLock.lock()
            completedCount += 1
            let done = completedCount
            progressLock.unlock()

            let name = pkgName == "__app__" ? "(app)" : pkgName
            let slowTag = pkgElapsed > 10.0 ? " 🐘" : ""
            print("\(ts())  [\(done)/\(totalPackages)] \(name): \(cappedFiles.count) files\(slowTag)")
        }

        // Merge edges into the graph sequentially (addEdge is not thread-safe)
        let totalCollected = localEdgesPerPkg.reduce(0) { $0 + $1.count }
        print("\(ts())  Merging \(totalCollected.formatted()) type-reference edges...")
        for edgeList in localEdgesPerPkg {
            for (src, tgt) in edgeList { addEdge(from: src, to: tgt) }
        }

        tokenCache.removeAll()
    }

    /// Tokenize Swift source content into a set of unique identifiers (length ≥ 4).
    /// Used instead of repeated string scanning: O(file_length) once, then O(1) per type lookup.
    private func tokenizeIdentifiers(_ content: String) -> Set<String> {
        var tokens = Set<String>()
        var i = content.startIndex
        while i < content.endIndex {
            let c = content[i]
            if c.isLetter || c == "_" {
                let start = i
                var len = 1
                i = content.index(after: i)
                while i < content.endIndex {
                    let nc = content[i]
                    guard nc.isLetter || nc.isNumber || nc == "_" else { break }
                    len += 1
                    i = content.index(after: i)
                }
                if len >= 4 { tokens.insert(String(content[start..<i])) }
            } else {
                i = content.index(after: i)
            }
        }
        return tokens
    }

    /// Build edges for Swift↔ObjC interop via bridging header and -Swift.h imports.
    private func buildInteropEdges(from parsedFiles: [ParsedFile], bridgingHeaderPath: String) {
        // Find the bridging header in parsed files
        let bridgingFile = parsedFiles.first { file in
            file.filePath.hasSuffix(bridgingHeaderPath) ||
            file.fileName == (bridgingHeaderPath.components(separatedBy: "/").last ?? bridgingHeaderPath)
        }

        guard let bridgingFile = bridgingFile else {
            print("   ⚠️  Bridging header not found in scanned files: \(bridgingHeaderPath)")
            return
        }

        // Build lookup from file name → path
        let nameToPath: [String: String] = Dictionary(
            parsedFiles.map { ($0.fileName, $0.filePath) },
            uniquingKeysWith: { first, _ in first }
        )
        let nameNoExtToPath: [String: String] = Dictionary(
            parsedFiles.map { ($0.fileNameWithoutExtension, $0.filePath) },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Bridging header → ObjC headers it imports
        for importName in bridgingFile.imports {
            let baseName = importName.components(separatedBy: "/").last ?? importName
            let nameOnly = baseName.replacingOccurrences(of: ".h", with: "")
            if let targetPath = nameToPath[baseName] ?? nameNoExtToPath[nameOnly] {
                addEdge(from: bridgingFile.filePath, to: targetPath)
            }
        }

        // 2. All Swift files → bridging header (implicit dependency)
        for file in parsedFiles where file.filePath.hasSuffix(".swift") {
            addEdge(from: file.filePath, to: bridgingFile.filePath)
        }

        // 3. ObjC .m/.mm files importing *-Swift.h → bridging header as proxy hub
        for file in parsedFiles {
            let ext = URL(fileURLWithPath: file.filePath).pathExtension.lowercased()
            guard ext == "m" || ext == "mm" else { continue }
            if file.imports.contains(where: { $0.hasSuffix("-Swift.h") }) {
                addEdge(from: file.filePath, to: bridgingFile.filePath)
            }
        }
    }

    // MARK: - Graph Operations

    func addVertex(_ v: String) {
        vertices.insert(v)
        if adjacency[v] == nil { adjacency[v] = [] }
        if reverseAdj[v] == nil { reverseAdj[v] = [] }
    }

    func addEdge(from source: String, to target: String) {
        guard source != target, vertices.contains(source), vertices.contains(target),
              !(adjacency[source]?.contains(target) ?? false) else { return }
        edges.append((source: source, target: target))
        adjacency[source]?.insert(target)
        reverseAdj[target]?.insert(source)
    }

    func outDegree(of vertex: String) -> Int { adjacency[vertex]?.count ?? 0 }
    func inDegree(of vertex: String) -> Int { reverseAdj[vertex]?.count ?? 0 }

    // MARK: - Analysis

    func analyze() { computePageRank() }

    func computePageRank(damping: Double = 0.85, iterations: Int = 20) {
        let n = Double(vertices.count)
        guard n > 0 else { return }
        var scores = Dictionary(uniqueKeysWithValues: vertices.map { ($0, 1.0 / n) })

        for _ in 0..<iterations {
            var newScores = Dictionary(uniqueKeysWithValues: vertices.map { ($0, (1.0 - damping) / n) })
            for v in vertices {
                let outNeighbors = adjacency[v] ?? []
                if outNeighbors.isEmpty { continue }
                let share = (scores[v] ?? 0) / Double(outNeighbors.count)
                for neighbor in outNeighbors {
                    newScores[neighbor, default: 0] += damping * share
                }
            }
            scores = newScores
        }
        pageRankScores = scores
    }

    // MARK: - Hotspots

    struct HotspotEntry {
        let path: String
        let score: Double
    }

    func getTopHotspots(limit: Int = 15) -> [HotspotEntry] {
        pageRankScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { HotspotEntry(path: $0.key, score: $0.value) }
    }

    // MARK: - Cycle Detection

    private func detectCycles() {
        var visited: Set<String> = []
        var onStack: Set<String> = []
        func dfs(_ v: String) -> Bool {
            visited.insert(v)
            onStack.insert(v)
            for neighbor in adjacency[v] ?? [] {
                if onStack.contains(neighbor) { return true }
                if !visited.contains(neighbor) && dfs(neighbor) { return true }
            }
            onStack.remove(v)
            return false
        }
        hasCycles = vertices.contains { !visited.contains($0) && dfs($0) }
        if hasCycles { print("\(ts()) ⚠️  Circular dependencies detected in the codebase.") }
    }

    // MARK: - Topological Sort

    func topologicalSort() -> [String]? {
        guard !hasCycles else { return nil }
        var inDegrees = Dictionary(uniqueKeysWithValues: vertices.map { ($0, 0) })
        for (_, neighbors) in adjacency {
            for n in neighbors { inDegrees[n, default: 0] += 1 }
        }
        var queue: [String] = vertices.filter { inDegrees[$0] == 0 }.sorted()
        var result: [String] = []
        while !queue.isEmpty {
            let v = queue.removeFirst()
            result.append(v)
            for neighbor in adjacency[v] ?? [] {
                inDegrees[neighbor]! -= 1
                if inDegrees[neighbor] == 0 { queue.append(neighbor) }
            }
        }
        return result.count == vertices.count ? result : nil
    }
}

