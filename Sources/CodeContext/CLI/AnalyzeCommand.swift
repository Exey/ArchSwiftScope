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

    @Flag(name: .long, help: "Render the Packages & Modules breakdown. Off by default for a faster scan.")
    var renderModules: Bool = false

    @Option(name: .long, help: "GitHub repository URL to enable link toggling (e.g. https://github.com/owner/repo)")
    var githubLinks: String = ""

    func run() async throws {
        print("\(ts()) 🚀 Starting ArchSwiftScope analysis for: \(path)")

        let config = ConfigLoader.load()
        DebugFlags.debugSubproject = debugSubproject || config.debugSubproject

        if clearCache {
            await CacheManager().clear()
            print("\(ts()) 🗑️  Cache cleared")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // ── Scan pipeline ────────────────────────────────────────────────────
        print("\(ts()) 📂 Scanning repository...")
        let scanT0 = CFAbsoluteTimeGetCurrent()
        let result = try await AnalysisPipeline.run(
            path: path,
            config: config,
            useCache: !noCache,
            verbose: verbose
        )
        print("\(ts())  Branch: \(result.branchName) · \(stageTime(CFAbsoluteTimeGetCurrent() - scanT0))")

        let graph = result.graph
        let enrichedFiles = result.enrichedFiles

        // ── Security risk checks (streaming, parallel per-check) ────────────
        let mpPaths = result.monkeyPatchedLibs.map(\.path)
        let projectFiles = enrichedFiles.filter { f in
            !mpPaths.contains { f.filePath.contains("/\($0)/") }
        }
        let swiftFileCount = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count
        let repoPath = URL(fileURLWithPath: path).standardizedFileURL.path

        let secT0 = CFAbsoluteTimeGetCurrent()
        let checkCount = SecurityAnalyzer.checkCount
        print("\n\(ts()) 🚨 Security risk checks · \(checkCount) checks · \(swiftFileCount) Swift files")

        let priLabel: (APPriority) -> String = {
            switch $0 { case .high: return "HIGH"; case .medium: return "MED "; case .low: return "LOW " }
        }
        let (apResults, securityScore) = SecurityAnalyzer.runWithScore(
            files: projectFiles,
            repoPath: repoPath,
            commitLimit: config.gitCommitLimit
        ) { r in
            let icon = r.passed ? "✓" : "✗"
            let name = r.check.name
            let truncated = name.count > 44 ? String(name.prefix(43)) + "…" : name
            let padded = truncated.padding(toLength: 44, withPad: " ", startingAt: 0)
            let countStr: String
            if r.passed {
                countStr = "—"
            } else if r.totalCount > r.violations.count {
                countStr = "\(r.totalCount) (showing \(r.violations.count))"
            } else {
                countStr = "\(r.violations.count)"
            }
            print("\(ts())  \(icon) \(priLabel(r.check.priority))  \(padded)  \(countStr)")
        }
        let failed = apResults.filter { !$0.passed }.count
        let passed = apResults.filter { $0.passed }.count
        print("\(ts())  \(failed) failed · \(passed) passed · \(stageTime(CFAbsoluteTimeGetCurrent() - secT0))")
        print("\(ts())  🛡️  Security Index: \(securityScore.total) / 1000 · \(securityScore.band.label)")

        // ── OOP vs POP analysis ──────────────────────────────────────────────
        let oopT0 = CFAbsoluteTimeGetCurrent()
        print("\n\(ts()) 🧬 OOP vs POP · \(swiftFileCount) Swift files")
        let oopStats = OOPvsPOPAnalyzer.analyze(files: projectFiles)
        let oopBar: String = {
            let filled = oopStats.popScore / 5
            let empty  = 20 - filled
            return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        }()
        print("\(ts())  [\(oopBar)] \(oopStats.popScore)% POP · \(stageTime(CFAbsoluteTimeGetCurrent() - oopT0))")
        print("\(ts())  \(oopStats.totalClasses) classes · \(oopStats.finalClasses) final · \(oopStats.totalStructs) structs · \(oopStats.totalProtocols) protocols")

        // ── Generate report ──────────────────────────────────────────────────
        let reportT0 = CFAbsoluteTimeGetCurrent()
        print("\n\(ts()) 📊 Generating report...")
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
            securityScore: securityScore,
            renderModules: renderModules,
            githubURL: githubLinks,
            headCommit: result.headCommit
        )
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        print("\(ts()) ✅ Report: \(reportURL.path) · \(stageTime(CFAbsoluteTimeGetCurrent() - reportT0))")

        // ── AI Analysis ──────────────────────────────────────────────────────
        if config.ai.enabled, !config.ai.apiKey.isEmpty {
            print("\n\(ts()) 🤖 Generating AI Insights...")
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
                print("\(ts()) ✨ AI Insights saved to: \(aiReportPath)")
            } else {
                print("\(ts())  ⚠️  AI enabled but not properly configured. Check API key.")
            }
        }

        // ── Final summary ────────────────────────────────────────────────────
        let total = CFAbsoluteTimeGetCurrent() - startTime
        let sysInfo = systemInfoLine()
        print("\n\(ts()) ✨ Complete in \(stageTime(total)) · \(sysInfo)")

        if open {
            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [reportURL.path]
            try? process.run()
            #endif
        }
    }

    // MARK: - Helpers

    private func stageTime(_ t: Double) -> String {
        let s = Int(t)
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m \(s % 60)s" }
        if s >= 60   { return "\(s / 60)m \(s % 60)s" }
        if t >= 1    { return String(format: "%.1fs", t) }
        return String(format: "%.0fms", t * 1000)
    }

    private func systemInfoLine() -> String {
        let cores = ProcessInfo.processInfo.processorCount
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(osVer.majorVersion).\(osVer.minorVersion)"
        let cpu = cpuBrandShort()
        let cpuStr = cpu.isEmpty ? "\(cores)-core CPU" : "\(cores)-core \(cpu)"
        return "\(cpuStr) · \(ramGB) GB RAM · \(os)"
    }

    private func cpuBrandShort() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 1 else { return "" }
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let full = String(cString: brand)
        // Apple Silicon: "Apple M3 Pro" → "M3 Pro"
        if full.hasPrefix("Apple ") { return String(full.dropFirst(6)) }
        // Intel: "Intel(R) Core(TM) i9-9900K CPU @ 3.60GHz" → "i9-9900K"
        let tokens = full.components(separatedBy: " ")
        if let idx = tokens.firstIndex(where: { $0.hasPrefix("i") && $0.contains("-") }) {
            return tokens[idx]
        }
        return full
    }
}
