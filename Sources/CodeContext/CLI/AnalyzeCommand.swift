// Exey Panteleev
import ArgumentParser
import Foundation

// MARK: - Analyze Command

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze a Swift codebase and generate a report"
    )

    @Argument(help: "Path to the repository to analyze")
    var path: String = "."

    @Flag(name: .long, help: "Disable caching")
    var noCache: Bool = false

    @Flag(name: .long, help: "Clear cache before analyzing")
    var clearCache: Bool = false

    @Flag(name: [.short, .long], help: "Enable verbose logging")
    var verbose: Bool = false

    @Flag(name: .long, help: "Open report in browser after generation")
    var open: Bool = false

    @Flag(name: .long, help: "Log subproject/package detection details")
    var debugSubproject: Bool = false

    @Flag(name: .long, help: "Skip Packages & Modules section (faster for large codebases)")
    var skipModules: Bool = false

    func run() async throws {
        print("🚀 Starting ArchSwiftScope analysis for: \(path)")

        let config = ConfigLoader.load()
        DebugFlags.debugSubproject = debugSubproject || config.debugSubproject

        if clearCache {
            await CacheManager().clear()
            print("🗑️  Cache cleared")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Run pipeline
        print("📂 Scanning repository...")
        let result = try await AnalysisPipeline.run(
            path: path,
            config: config,
            useCache: !noCache,
            verbose: verbose
        )

        let graph = result.graph
        let enrichedFiles = result.enrichedFiles

        print("   Branch: \(result.branchName)")

        // Show hotspots
        let hotspots = graph.getTopHotspots(limit: config.hotspotCount)
        print("\n🗺️  Your Codebase Map")
        print("├─ 🔥 Hot Zones (Top \(min(5, hotspots.count))):")

        for (index, item) in hotspots.prefix(5).enumerated() {
            let fileName = URL(fileURLWithPath: item.path).lastPathComponent
            let prefix = (index == 4 || index == hotspots.count - 1) ? "│   └─" : "│   ├─"
            print("\(prefix) \(fileName) (\(String(format: "%.4f", item.score)))")
        }

        // Anti-pattern checks (parallel file I/O)
        let mpPaths = result.monkeyPatchedLibs.map(\.path)
        let projectFiles = enrichedFiles.filter { f in
            !mpPaths.contains { f.filePath.contains("/\($0)/") }
        }
        let swiftFileCount = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count
        let repoPath = URL(fileURLWithPath: path).standardizedFileURL.path
        print("\n⚠️  Anti-pattern checks · \(swiftFileCount) Swift files")
        let apResults = AntipatternAnalyzer.run(files: projectFiles, repoPath: repoPath)

        let priLabel: (APPriority) -> String = {
            switch $0 { case .high: "HIGH"; case .medium: "MED "; case .low: "LOW " }
        }
        for pri in [APPriority.high, .medium, .low] {
            for r in apResults where r.check.priority == pri {
                let icon = r.passed ? "✓" : "✗"
                let name = r.check.name
                let truncated = name.count > 44 ? String(name.prefix(43)) + "…" : name
                let padded = truncated.padding(toLength: 44, withPad: " ", startingAt: 0)
                let count = r.passed ? "—" : "\(r.violations.count)"
                print("   \(icon) \(priLabel(pri))  \(padded)  \(count)")
            }
        }
        let failed = apResults.filter { !$0.passed }.count
        let passed = apResults.filter { $0.passed }.count
        print("   \(failed) failed · \(passed) passed")

        // OOP vs POP analysis
        print("\n🧬 OOP vs POP · \(swiftFileCount) Swift files")
        let oopStats = OOPvsPOPAnalyzer.analyze(files: projectFiles)
        let oopBar: String = {
            let filled = oopStats.popScore / 5
            let empty  = 20 - filled
            return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        }()
        print("   [\(oopBar)] \(oopStats.popScore)% POP")
        print("   \(oopStats.totalClasses) classes · \(oopStats.finalClasses) final · \(oopStats.totalStructs) structs · \(oopStats.totalProtocols) protocols")

        // Generate report
        print("\n📊 Generating report...")
        let outputDir = "output"
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let generator = ReportGenerator()
        let projectName = URL(fileURLWithPath: path).lastPathComponent
        let reportPath = "\(outputDir)/\(projectName).html"
        try generator.generate(
            graph: graph,
            outputPath: reportPath,
            parsedFiles: enrichedFiles,
            branchName: result.branchName,
            authorStats: result.authorStats,
            projectName: projectName,
            metadata: result.metadata,
            monkeyPatchedLibs: result.monkeyPatchedLibs,
            branchStats: result.branchStats,
            semanticStats: result.semanticStats,
            churnFiles: result.churnFiles,
            repoPath: repoPath,
            apResults: apResults,
            oopStats: oopStats,
            skipModules: skipModules
        )

        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        print("✅ Report: \(reportURL.path)")

        // AI Analysis
        if config.ai.enabled, !config.ai.apiKey.isEmpty {
            print("\n🤖 Generating AI Insights...")
            let aiAnalyzer = AICodeAnalyzer(
                apiKey: config.ai.apiKey,
                model: config.ai.model,
                provider: config.ai.provider
            )

            if aiAnalyzer.isConfigured {
                let insights = await aiAnalyzer.batchAnalyze(
                    files: enrichedFiles, graph: graph, limit: 10
                )

                let aiReportPath = "\(outputDir)/ai-insights.md"
                var md = "# AI Code Insights\n\n"
                for (path, insight) in insights {
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    md += "## \(name)\n"
                    md += "**Purpose**: \(insight.purpose)\n\n"
                    md += "**Complexity**: \(insight.complexity)/10\n"
                    md += "**Refactoring Tips**: \(insight.refactoringTips.joined(separator: ", "))\n\n"
                }
                try md.write(toFile: aiReportPath, atomically: true, encoding: .utf8)
                print("✨ AI Insights saved to: \(aiReportPath)")
            } else {
                print("   ⚠️  AI enabled but not properly configured. Check API key.")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let timeStr: String
        if hours > 0 {
            timeStr = "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            timeStr = "\(minutes)m \(seconds)s"
        } else {
            timeStr = String(format: "%.1fs", elapsed)
        }
        print("\n✨ Complete in \(timeStr)")

        if open {
            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [reportURL.path]
            try? process.run()
            #endif
        }
    }
}
