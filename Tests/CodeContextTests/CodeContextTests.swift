// Exey Panteleev
import Testing
import Foundation
@testable import CodeContext

// MARK: - Helpers

private func writeTmp(_ name: String, _ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)_\(UUID().uuidString).swift")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// Stub ParsedFile — sufficient for SecurityAnalyzer (reads file from disk itself).
private func makeParsedFile(_ url: URL) -> ParsedFile {
    ParsedFile(filePath: url.path, moduleName: "", imports: [], description: "",
               lineCount: 0, declarations: [], packageName: "", buildSystem: .unknown,
               todoCount: 0, fixmeCount: 0, longestFunction: nil)
}

/// Fully-parsed ParsedFile — needed for analyzers that consume `.declarations`.
private func parseFile(_ url: URL) throws -> ParsedFile {
    try SwiftParser().parse(file: url)
}

// MARK: - Config

@Test func defaultConfigHasSaneDefaults() {
    let config = CodeContextConfig()
    #expect(config.maxFilesAnalyze == 20000)
    #expect(config.enableCache)
    #expect(config.fileExtensions.contains("swift"))
    #expect(!config.ai.enabled)
}

// MARK: - Dependency Graph

@Suite struct DependencyGraphTests {

    @Test func sinkNodeGetsHigherPageRank() {
        let graph = DependencyGraph()
        graph.addVertex("A"); graph.addVertex("B"); graph.addVertex("C")
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "A", to: "C")
        graph.addEdge(from: "B", to: "C")
        graph.computePageRank()
        #expect((graph.pageRankScores["C"] ?? 0) > (graph.pageRankScores["A"] ?? 0))
    }

    @Test func topologicalSortSourceComesFirst() {
        let graph = DependencyGraph()
        graph.addVertex("A"); graph.addVertex("B")
        graph.addEdge(from: "A", to: "B")
        #expect(graph.topologicalSort()?.first == "A")
    }

    @Test func selfEdgesAreDropped() {
        let graph = DependencyGraph()
        graph.addVertex("A")
        graph.addEdge(from: "A", to: "A")
        #expect(graph.edges.isEmpty)
    }

    @Test func topHotspotsRespectLimit() {
        let graph = DependencyGraph()
        for v in ["A", "B", "C", "D", "E"] { graph.addVertex(v) }
        graph.addEdge(from: "A", to: "E")
        graph.addEdge(from: "B", to: "E")
        graph.addEdge(from: "C", to: "E")
        graph.computePageRank()
        #expect(graph.getTopHotspots(limit: 2).count == 2)
    }
}

// MARK: - Swift Parser

@Suite struct SwiftParserTests {
    let parser = SwiftParser()

    @Test func extractsImportsAndAllDeclarationKinds() throws {
        let url = try writeTmp("AllKinds", """
        import Foundation
        import UIKit
        /// A test class
        class MyClass {}
        struct MyStruct: Codable {}
        protocol MyProtocol {}
        enum MyEnum { case a }
        actor MyActor {}
        extension MyClass {}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try parser.parse(file: url)
        #expect(parsed.imports == ["Foundation", "UIKit"])
        #expect(!parsed.description.isEmpty)
        #expect(parsed.declarations.contains { $0.name == "MyClass"    && $0.kind == .class })
        #expect(parsed.declarations.contains { $0.name == "MyStruct"   && $0.kind == .struct })
        #expect(parsed.declarations.contains { $0.name == "MyProtocol" && $0.kind == .protocol })
        #expect(parsed.declarations.contains { $0.name == "MyEnum"     && $0.kind == .enum })
        #expect(parsed.declarations.contains { $0.name == "MyActor"    && $0.kind == .actor })
    }

    @Test func detectsPackageNameFromSPMLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let srcDir = root
            .appendingPathComponent("Packages/MyPkg/Sources/MyPkg")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let file = srcDir.appendingPathComponent("Hello.swift")
        try "struct Hello {}".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try parser.parse(file: file)
        #expect(parsed.packageName == "MyPkg")
        #expect(parsed.moduleName  == "MyPkg")
    }

    @Test func countsTODOsAndFIXMEs() throws {
        let url = try writeTmp("Annotations", """
        struct Foo {
            func bar() {
                // TODO: implement
                // FIXME: broken
                // FIXME: also broken
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try parser.parse(file: url)
        #expect(parsed.todoCount  == 1)
        #expect(parsed.fixmeCount == 2)
    }

    @Test func findsLongestFunction() throws {
        let url = try writeTmp("Functions", """
        struct Foo {
            func short() { }
            func longOne() {
                let a = 1
                let b = 2
                let c = 3
                let d = 4
                let e = 5
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try parser.parse(file: url)
        #expect(parsed.longestFunction?.name == "longOne")
    }

    @Test func skipsNestedTypeDeclarations() throws {
        let url = try writeTmp("Nested", """
        struct Outer {
            enum CodingKeys: String, CodingKey { case id }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try parser.parse(file: url)
        #expect(parsed.declarations.count == 1)
        #expect(parsed.declarations[0].name == "Outer")
    }
}

// MARK: - Security Analyzer
// Tests run the full per-file detection pass on real temp files.
// Detection functions are private; the public runWithScore API is the right seam.

@Suite struct SecurityAnalyzerTests {

    @Test func zeroViolationsGivesZeroScore() {
        let (_, score) = SecurityAnalyzer.runWithScore(files: [])
        #expect(score.total == 0)
    }

    @Test func scoreAlwaysInRange() throws {
        let url = try writeTmp("WorstCase", """
        let apiKey = "sk-prod-abc123def456ghi789jkl"
        let endpoint = "http://api.example.com"
        let wv = UIWebView()
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let (_, score) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        #expect(score.total >= 0)
        #expect(score.total <= 1000)
    }

    @Test func detectsHardcodedSecret() throws {
        let url = try writeTmp("Secrets", """
        struct Config {
            let apiKey = "sk-prod-abc123def456ghi789jkl012"
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let (results, _) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        let check = results.first { $0.check.name.contains("Hardcoded Secret") }
        #expect(check?.violations.isEmpty == false)
    }

    @Test func detectsPlaintextHTTPURL() throws {
        let url = try writeTmp("Network", #"let u = "http://api.example.com/v1""#)
        defer { try? FileManager.default.removeItem(at: url) }
        let (results, _) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        let check = results.first { $0.check.name.contains("Plaintext HTTP") }
        #expect(check?.violations.isEmpty == false)
    }

    @Test func commentedHTTPURLNotFlagged() throws {
        let url = try writeTmp("NetworkClean", """
        // let old = "http://legacy.example.com"
        let u = "https://api.example.com"
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let (results, _) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        let check = results.first { $0.check.name.contains("Plaintext HTTP") }
        #expect(check?.violations.isEmpty == true)
    }

    @Test func detectsUIWebView() throws {
        let url = try writeTmp("LegacyView", "let wv = UIWebView(frame: .zero)")
        defer { try? FileManager.default.removeItem(at: url) }
        let (results, _) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        let check = results.first { $0.check.name.contains("UIWebView") }
        #expect(check?.violations.isEmpty == false)
    }

    @Test func detectsDelegateCertBypass() throws {
        let url = try writeTmp("SessionDelegate", """
        class D: NSObject, URLSessionDelegate {
            func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let (results, _) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        let check = results.first { $0.check.name.contains("Delegate") }
        #expect(check?.violations.isEmpty == false)
    }

    @Test func delegateWithTrustEvalIsClean() throws {
        let url = try writeTmp("SessionDelegateSafe", """
        class D: NSObject, URLSessionDelegate {
            func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                guard let trust = challenge.protectionSpace.serverTrust,
                      SecTrustEvaluateWithError(trust, nil) else {
                    completionHandler(.cancelAuthenticationChallenge, nil); return
                }
                completionHandler(.useCredential, URLCredential(trust: trust))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let (results, _) = SecurityAnalyzer.runWithScore(files: [makeParsedFile(url)])
        let check = results.first { $0.check.name.contains("Delegate") }
        #expect(check?.violations.isEmpty == true)
    }

    @Test func securityBandLabelsExist() {
        #expect(!SecurityScore.Band.healthy.label.isEmpty)
        #expect(!SecurityScore.Band.light.label.isEmpty)
        #expect(!SecurityScore.Band.elevated.label.isEmpty)
        #expect(!SecurityScore.Band.critical.label.isEmpty)
    }

    @Test func priorityWeightsOrdered() {
        #expect(APPriority.high.violationWeight > APPriority.medium.violationWeight)
        #expect(APPriority.medium.violationWeight > APPriority.low.violationWeight)
    }
}

// MARK: - OOP vs POP Analyzer

@Suite struct OOPvsPOPTests {

    @Test func protocolHeavyCodeScoresHigherThanClassHeavy() throws {
        let popUrl = try writeTmp("POPCode", """
        protocol Drawable { func draw() }
        protocol Animatable { func animate() }
        protocol Scalable { var scale: Double { get set } }
        struct Circle: Drawable, Animatable, Scalable { var scale = 1.0; func draw() {}; func animate() {} }
        struct Square: Drawable, Scalable { var scale = 1.0; func draw() {} }
        struct Triangle: Drawable { func draw() {} }
        """)
        let oopUrl = try writeTmp("OOPCode", """
        class Base { func method() {} }
        class Child: Base { override func method() {} }
        class GrandChild: Child { override func method() {} }
        class Another: Base {}
        """)
        defer {
            try? FileManager.default.removeItem(at: popUrl)
            try? FileManager.default.removeItem(at: oopUrl)
        }
        let popScore = OOPvsPOPAnalyzer.analyze(files: [try parseFile(popUrl)]).popScore
        let oopScore = OOPvsPOPAnalyzer.analyze(files: [try parseFile(oopUrl)]).popScore
        #expect(popScore > oopScore)
    }

    @Test func classHeavyCodeScoresLowPOP() throws {
        let url = try writeTmp("OOPCode", """
        class Base { func method() {} }
        class Child: Base { override func method() {} }
        class GrandChild: Child { override func method() {} }
        class Another: Base {}
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let stats = OOPvsPOPAnalyzer.analyze(files: [try parseFile(url)])
        #expect(stats.popScore < 50)
    }
}

// MARK: - Array Extension

@Test func chunkedSplitsCorrectly() {
    let chunks = [1, 2, 3, 4, 5].chunked(into: 2)
    #expect(chunks.count == 3)
    #expect(chunks[0] == [1, 2])
    #expect(chunks[2] == [5])
}

@Test func chunkedWithSizeEqualToArrayLength() {
    let chunks = [1, 2, 3].chunked(into: 3)
    #expect(chunks.count == 1)
    #expect(chunks[0] == [1, 2, 3])
}
