// Exey Panteleev
import Foundation

// MARK: - Author Stats (global, repo-wide)

struct AuthorStats {
    var displayName: String = ""
    var filesModified: Int = 0
    var totalCommits: Int = 0
    var totalLOCAdded: Int = 0
    var firstCommitDate: TimeInterval = 0
    var lastCommitDate: TimeInterval = 0
}

// MARK: - Branch Stats

struct StaleBranchInfo {
    let name: String
    let daysInactive: Int
}

// MARK: - Branching Model Detection

enum BranchingModelKind: String, CaseIterable {
    case gitflow      = "Gitflow"
    case trunkBased   = "Trunk-Based Development"
    case githubFlow   = "GitHub Flow"
    case gitlabFlow   = "GitLab Flow"
    case oneFlow      = "OneFlow"
    case unknown      = "Unknown"

    var icon: String {
        switch self {
        case .gitflow:    return "🌿"
        case .trunkBased: return "🪵"
        case .githubFlow: return "🐙"
        case .gitlabFlow: return "🦊"
        case .oneFlow:    return "1️⃣"
        case .unknown:    return "❓"
        }
    }

    var detail: String {
        switch self {
        case .gitflow:    return "Long-lived integration branch · release & hotfix tracks"
        case .trunkBased: return "Single trunk · micro-commits · continuous integration"
        case .githubFlow: return "Short-lived feature branches merged directly to main"
        case .gitlabFlow: return "GitHub Flow + cascading environment branches"
        case .oneFlow:    return "One permanent branch · releases tagged on main"
        case .unknown:    return "Insufficient history to determine strategy"
        }
    }
}

struct BranchingModelStats {
    var model: BranchingModelKind = .unknown
    var confidence: Double = 0              // fraction of total score held by winner
    var integrationBranch: String = ""      // e.g. "develop"
    var environmentBranches: [String] = []  // staging, production, …
    var releasePrefixCount: Int = 0         // release/* branches
    var hotfixPrefixCount: Int = 0          // hotfix/* branches
    var mergeCommitRatio: Double = 0        // merge commits / total commits on main
    var mergesPerDay: Double = 0
    var hasDualMerges: Bool = false         // same commit merged into main AND integration branch
    var hasCascadingMerges: Bool = false    // env branches receive merges from main
    var signals: [String] = []             // human-readable evidence bullets
    var modelScores: [(model: BranchingModelKind, score: Double)] = []
}

struct BranchStats {
    var total: Int = 0
    var local: Int = 0
    var remote: Int = 0
    var stale: Int = 0
    var merged: Int = 0
    var maxDepth: Int = 0
    var peakCommitDay: String = ""
    var rollbackCount: Int = 0
    var totalMainCommits: Int = 0
    var avgLifetimeDays: Double = 0   // first commit → last commit on feature branch
    var avgTTMDays: Double = 0        // first commit on feature branch → merge
    var avgIntegDelayHours: Double = 0 // last commit on feature branch → merge
    var staleBranches: [StaleBranchInfo] = []
    var branchingModel: BranchingModelStats = BranchingModelStats()
}

// MARK: - File Churn Stat

struct FileChurnStat {
    let path: String
    let changeCount: Int
}

// MARK: - Semantic Stats

struct SemanticStats {
    var totalCommits: Int = 0
    var conventionalCommits: Int = 0
    var semverTags: Int = 0
    var totalTags: Int = 0
    var latestSemver: String = ""
    var topPrefixes: [(prefix: String, count: Int)] = []
    var samples: [String] = []
}

// MARK: - Git Analyzer

/// Analyzes git history using the native `git` command line tool.
/// Uses a batch approach for large repos: one `git log --name-only` call
/// to gather per-file stats instead of N individual calls.
struct GitAnalyzer {

    let repoPath: String
    let commitLimit: Int

    init(repoPath: String, commitLimit: Int = 500) {
        self.repoPath = repoPath
        self.commitLimit = commitLimit
    }

    // MARK: - Public

    func currentBranch() -> String {
        let output = git(["rev-parse", "--abbrev-ref", "HEAD"])
        return output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    /// Global author stats. Commit/date info from one git log call; LOC from a second --numstat pass.
    func authorStats() -> [String: AuthorStats] {
        guard let output = git(["log", "--pretty=format:%ae\t%an\t%at", "-\(commitLimit)"]) else { return [:] }
        var stats: [String: AuthorStats] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            let email = String(parts[0])
            let name = String(parts[1])
            let ts = TimeInterval(parts[2]) ?? 0
            guard ts > 0 else { continue }
            var s = stats[email, default: AuthorStats()]
            s.totalCommits += 1
            if s.firstCommitDate == 0 || ts < s.firstCommitDate { s.firstCommitDate = ts }
            if ts > s.lastCommitDate { s.lastCommitDate = ts; s.displayName = name }
            if s.displayName.isEmpty { s.displayName = name }
            stats[email] = s
        }

        // LOC added per author via numstat (second pass — separate git call)
        if let numstat = git(["log", "-\(commitLimit)", "--pretty=format:__AUTHOR__%n%ae", "--numstat"]) {
            var currentEmail = ""
            for line in numstat.components(separatedBy: "\n") {
                if line == "__AUTHOR__" { currentEmail = ""; continue }
                if currentEmail.isEmpty { currentEmail = line.trimmingCharacters(in: .whitespaces); continue }
                let cols = line.split(separator: "\t")
                guard cols.count >= 2, let added = Int(cols[0]) else { continue }
                stats[currentEmail]?.totalLOCAdded += added
            }
        }
        return stats
    }

    func branchStats() -> BranchStats {
        var stats = BranchStats()
        let now = Date().timeIntervalSince1970
        let staleThreshold: TimeInterval = 90 * 24 * 3600
        let protected: Set<String> = ["main", "master", "develop", "development", "HEAD"]
        var staleList: [StaleBranchInfo] = []

        // Local branches: inventory, depth, stale detection
        if let output = git(["for-each-ref", "--format=%(refname:short)\t%(committerdate:unix)", "refs/heads/"]) {
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard !parts.isEmpty else { continue }
                let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let ts = parts.count >= 2 ? (TimeInterval(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) : 0
                stats.local += 1
                let depth = name.components(separatedBy: "/").count
                if depth > stats.maxDepth { stats.maxDepth = depth }
                if ts > 0 && (now - ts) > staleThreshold {
                    stats.stale += 1
                    staleList.append(StaleBranchInfo(name: name, daysInactive: Int((now - ts) / 86400)))
                }
            }
        }
        stats.staleBranches = staleList.sorted { $0.daysInactive > $1.daysInactive }.prefix(10).map { $0 }

        if let output = git(["branch", "--merged", "--format=%(refname:short)"]) {
            stats.merged = output.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !protected.contains($0) }
                .count
        }

        if let output = git(["for-each-ref", "--format=%(refname:short)", "refs/remotes/"]) {
            stats.remote = output.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
                .count
        }

        // Peak commit day from recent history
        if let dayOut = git(["log", "--all", "-2000", "--pretty=format:%at"]) {
            var dayCounts: [Int: Int] = [:]
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            for line in dayOut.split(separator: "\n") {
                if let ts = TimeInterval(line.trimmingCharacters(in: .whitespacesAndNewlines)), ts > 0 {
                    let weekday = cal.component(.weekday, from: Date(timeIntervalSince1970: ts)) - 1
                    dayCounts[weekday, default: 0] += 1
                }
            }
            if let peak = dayCounts.max(by: { $0.value < $1.value }) {
                let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                if peak.key >= 0 && peak.key < days.count { stats.peakCommitDay = days[peak.key] }
            }
        }

        // Detect main branch
        let mainBranch = ["main", "master"].first {
            git(["rev-parse", "--verify", "--quiet", $0]) != nil
        } ?? "HEAD"

        // Rollback / revert commit count and total main commits
        if let revertOut = git(["log", "--pretty=format:%s", mainBranch]) {
            let subjects = revertOut.split(separator: "\n")
            stats.totalMainCommits = subjects.count
            stats.rollbackCount = subjects
                .filter { $0.lowercased().contains("revert") || $0.lowercased().contains("rollback") }
                .count
        }

        // Merge analysis: lifetime, TTM, integration delay
        // Each merge commit line: "<merge-ts> <main-parent> <feature-tip>"
        var lifetimes: [Double] = []
        var ttms: [Double] = []
        var integDelays: [Double] = []

        if let mergeOut = git(["log", mainBranch, "--merges", "-50", "--pretty=format:%at %P"]) {
            for line in mergeOut.split(separator: "\n") {
                let fields = line.split(separator: " ")
                guard fields.count >= 3,
                      let mergeTs = TimeInterval(fields[0]),
                      mergeTs > 0 else { continue }

                let mainParent = String(fields[1])
                let featureTip = String(fields[2])

                // Timestamps of commits on the feature branch not reachable from main
                guard let featureLog = git([
                    "log", "\(mainParent)..\(featureTip)", "--pretty=format:%at"
                ]) else { continue }

                let timestamps = featureLog.split(separator: "\n").compactMap {
                    TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines))
                }.filter { $0 > 0 }

                guard !timestamps.isEmpty else { continue }
                let minTs = timestamps.min()!
                let maxTs = timestamps.max()!

                let lifetimeDays = (maxTs - minTs) / 86400
                let ttmDays = (mergeTs - minTs) / 86400
                let delayHours = (mergeTs - maxTs) / 3600

                if lifetimeDays >= 0 && lifetimeDays < 365 { lifetimes.append(lifetimeDays) }
                if ttmDays >= 0 && ttmDays < 730 { ttms.append(ttmDays) }
                if delayHours >= 0 && delayHours < 8760 { integDelays.append(delayHours) }
            }
        }

        func avg(_ vals: [Double]) -> Double {
            guard !vals.isEmpty else { return 0 }
            return vals.reduce(0, +) / Double(vals.count)
        }
        stats.avgLifetimeDays = avg(lifetimes)
        stats.avgTTMDays = avg(ttms)
        stats.avgIntegDelayHours = avg(integDelays)

        stats.total = stats.local + stats.remote

        // Detect branching model last (needs totalMainCommits + avgLifetimeDays)
        stats.branchingModel = detectBranchingModel(
            primaryBranch: mainBranch,
            totalMainCommits: stats.totalMainCommits,
            avgLifetimeDays: stats.avgLifetimeDays
        )

        return stats
    }

    // MARK: - Branching Model Detector

    /// Role-based classifier: infers Gitflow / TBD / GitHub Flow / GitLab Flow / OneFlow
    /// from branch names, merge topology, integration tempo, and tag usage.
    private func detectBranchingModel(
        primaryBranch: String,
        totalMainCommits: Int,
        avgLifetimeDays: Double
    ) -> BranchingModelStats {
        var result = BranchingModelStats()
        guard totalMainCommits > 5 else { return result } // need minimal history

        // ── 1. All branch names (local + remote, deduplicated, normalized) ──────────
        guard let rawRefs = git(["for-each-ref",
                                  "--format=%(refname:short)",
                                  "refs/heads/", "refs/remotes/"]) else { return result }

        let allNames: [String] = Array(Set(
            rawRefs.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
                .map { $0.hasPrefix("origin/") ? String($0.dropFirst(7)) : $0 }
        ))

        let protected: Set<String> = [primaryBranch, "main", "master", "HEAD"]

        // ── 2. Integration branch (long-lived, non-primary) ─────────────────────────
        let integCandidates = ["develop", "dev", "devel", "development", "integration", "next"]
        let integBranch = allNames.first { integCandidates.contains($0) }
        result.integrationBranch = integBranch ?? ""

        // ── 3. Branch prefix classification ─────────────────────────────────────────
        result.releasePrefixCount = allNames.filter {
            $0.hasPrefix("release/") || $0.hasPrefix("rel/") || $0.hasPrefix("releases/")
        }.count

        result.hotfixPrefixCount = allNames.filter {
            $0.hasPrefix("hotfix/") || $0.hasPrefix("hotfix-") || $0.hasPrefix("hf/")
        }.count

        // ── 4. Environment branches (GitLab Flow signal) ────────────────────────────
        let envKeywords = ["staging", "stage", "production", "prod", "preprod", "preview", "qa"]
        result.environmentBranches = allNames.filter { name in
            !protected.contains(name) && !integCandidates.contains(name) &&
            envKeywords.contains { name == $0 || name.hasPrefix("\($0)/") || name.hasPrefix("\($0)-") }
        }

        // ── 5. Merge-commit ratio on primary branch ─────────────────────────────────
        if let countStr = git(["rev-list", "--count", "--merges", primaryBranch]),
           let mergeCount = Int(countStr.trimmingCharacters(in: .whitespacesAndNewlines)),
           totalMainCommits > 0 {
            result.mergeCommitRatio = Double(mergeCount) / Double(totalMainCommits)
        }

        // ── 6. Merges per day ───────────────────────────────────────────────────────
        if let firstTsStr = git(["log", primaryBranch, "--pretty=format:%at", "--reverse", "-1"]),
           let firstTs = TimeInterval(firstTsStr.trimmingCharacters(in: .whitespacesAndNewlines)),
           firstTs > 0 {
            let ageInDays = max(1.0, (Date().timeIntervalSince1970 - firstTs) / 86400.0)
            let mergeCount = result.mergeCommitRatio * Double(totalMainCommits)
            result.mergesPerDay = mergeCount / ageInDays
        }

        // ── 7. Dual merges (Gitflow signature) ──────────────────────────────────────
        // Same commit message appears in merges on BOTH primary and integration branch
        if let ib = integBranch {
            if let mainMerges = git(["log", primaryBranch, "--merges", "-50", "--pretty=format:%s"]),
               let integMerges = git(["log", ib, "--merges", "-50", "--pretty=format:%s"]) {
                let mainSet  = Set(mainMerges.split(separator:  "\n").map(String.init).filter { !$0.isEmpty })
                let integSet = Set(integMerges.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
                result.hasDualMerges = mainSet.intersection(integSet).count >= 2
            }
        }

        // ── 8. Cascading merges (GitLab Flow signature) ─────────────────────────────
        for envBranch in result.environmentBranches.prefix(3) {
            if let log = git(["log", envBranch, "--merges", "-3", "--pretty=format:%s"]),
               !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.hasCascadingMerges = true
                break
            }
        }

        // ── 9. Weighted scoring ──────────────────────────────────────────────────────
        var s: [BranchingModelKind: Double] = Dictionary(
            uniqueKeysWithValues: BranchingModelKind.allCases.filter { $0 != .unknown }.map { ($0, 0.0) }
        )

        // Integration branch
        if let ib = integBranch {
            s[.gitflow,    default: 0] += 40
            s[.trunkBased, default: 0] -= 20
            s[.githubFlow, default: 0] -= 10
            result.signals.append("Integration branch '\(ib)' detected")
        }

        // Release branches
        if result.releasePrefixCount > 0 {
            s[.gitflow, default: 0] += 25
            result.signals.append("\(result.releasePrefixCount) release/* branch(es)")
        }

        // Hotfix branches
        if result.hotfixPrefixCount > 0 {
            s[.gitflow,  default: 0] += 18
            s[.oneFlow,  default: 0] += 5
            result.signals.append("\(result.hotfixPrefixCount) hotfix/* branch(es)")
        }

        // Dual merges
        if result.hasDualMerges {
            s[.gitflow, default: 0] += 35
            result.signals.append("Dual-merge pattern: same commits landed in both '\(primaryBranch)' and '\(integBranch ?? "")'")
        }

        // Merge-commit ratio
        if result.mergeCommitRatio > 0.7 {
            s[.gitflow, default: 0] += 15
            result.signals.append("High merge-commit ratio (\(Int(result.mergeCommitRatio * 100))%) on \(primaryBranch)")
        } else if result.mergeCommitRatio > 0 && result.mergeCommitRatio < 0.2 {
            s[.trunkBased, default: 0] += 20
            s[.oneFlow,    default: 0] +=  5
            result.signals.append("Linear history (\(Int(result.mergeCommitRatio * 100))% merge commits — squash/rebase workflow)")
        } else if result.mergeCommitRatio >= 0.3 && result.mergeCommitRatio <= 0.7 {
            s[.gitlabFlow, default: 0] +=  8
            s[.githubFlow, default: 0] +=  5
        }

        // Avg branch lifetime
        if avgLifetimeDays > 0 {
            let d = String(format: "%.1f", avgLifetimeDays)
            if avgLifetimeDays < 1.0 {
                s[.trunkBased, default: 0] += 25
                s[.githubFlow, default: 0] +=  8
                result.signals.append("Very short avg branch lifetime (\(d) days) → micro-commit cadence")
            } else if avgLifetimeDays < 3.0 {
                s[.githubFlow,  default: 0] += 20
                s[.trunkBased,  default: 0] +=  8
                s[.gitlabFlow,  default: 0] +=  8
                result.signals.append("Short avg branch lifetime (\(d) days)")
            } else {
                s[.gitflow, default: 0] += 15
                result.signals.append("Long avg branch lifetime (\(d) days) → batch integration releases")
            }
        }

        // Merge frequency
        if result.mergesPerDay > 0 {
            let f = String(format: "%.1f", result.mergesPerDay)
            if result.mergesPerDay > 3.0 {
                s[.trunkBased, default: 0] += 30
                result.signals.append("High merge frequency (\(f) merges/day into \(primaryBranch))")
            } else if result.mergesPerDay > 1.0 {
                s[.githubFlow,  default: 0] += 20
                s[.trunkBased,  default: 0] +=  8
                s[.gitlabFlow,  default: 0] +=  8
                result.signals.append("Moderate merge frequency (\(f) merges/day into \(primaryBranch))")
            } else if result.mergesPerDay < 0.5 {
                s[.gitflow,  default: 0] += 10
                s[.oneFlow,  default: 0] +=  5
            }
        }

        // GitLab Flow: cascading merges / env branches
        if result.hasCascadingMerges {
            s[.gitlabFlow, default: 0] += 50
            result.signals.append("Cascading merges into environment branches: \(result.environmentBranches.joined(separator: ", "))")
        } else if !result.environmentBranches.isEmpty {
            s[.gitlabFlow, default: 0] += 20
            s[.githubFlow, default: 0] -= 10
            result.signals.append("Environment branches found: \(result.environmentBranches.joined(separator: ", "))")
        }

        // OneFlow baseline: no integration + no release branches
        if integBranch == nil && result.releasePrefixCount == 0 && !result.hasCascadingMerges {
            s[.oneFlow, default: 0] += 8
        }

        // GitHub Flow baseline: simple workflow with no special branches
        if integBranch == nil && result.releasePrefixCount == 0
            && result.hotfixPrefixCount == 0 && !result.hasCascadingMerges {
            s[.githubFlow, default: 0] += 15
            if result.signals.isEmpty {
                result.signals.append("No integration, release, or hotfix branches — simple feature-branch workflow")
            }
        }

        // ── 10. Floor at 0, normalize, pick winner ──────────────────────────────────
        for key in s.keys { s[key] = max(0, s[key]!) }

        let totalScore = s.values.reduce(0, +)
        let sortedScores = s.sorted { $0.value > $1.value }
        result.modelScores = sortedScores.map { (model: $0.key, score: $0.value) }

        if let winner = sortedScores.first, winner.value > 0, totalScore > 0 {
            result.model = winner.key
            result.confidence = winner.value / totalScore
        }

        return result
    }

    func semanticStats() -> SemanticStats {
        var stats = SemanticStats()
        guard let subjects = git(["log", "--pretty=format:%s", "-\(commitLimit)"]) else { return stats }

        let lines = subjects.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        stats.totalCommits = lines.count

        let conventionalTypes = ["feat", "fix", "docs", "chore", "refactor", "test", "style", "ci", "build", "perf", "revert"]
        let pattern = "^(" + conventionalTypes.joined(separator: "|") + ")(\\([^)]+\\))?!?:\\s"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return stats }

        var prefixCounts: [String: Int] = [:]
        for subject in lines {
            let range = NSRange(subject.startIndex..., in: subject)
            if let match = regex.firstMatch(in: subject, range: range),
               let typeRange = Range(match.range(at: 1), in: subject) {
                prefixCounts[String(subject[typeRange]), default: 0] += 1
                stats.conventionalCommits += 1
            } else if stats.samples.count < 5 {
                stats.samples.append(subject)
            }
        }
        stats.topPrefixes = prefixCounts.sorted { $0.value > $1.value }.prefix(6).map { (prefix: $0.key, count: $0.value) }

        // Tags sorted newest-first via --sort=-version:refname
        if let tagOutput = git(["tag", "--sort=-version:refname"]) {
            let tags = tagOutput.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            stats.totalTags = tags.count
            let semverPat = try? NSRegularExpression(pattern: "^v?\\d+\\.\\d+\\.\\d+")
            let semverTags = tags.filter { tag in
                guard let pat = semverPat else { return false }
                return pat.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) != nil
            }
            stats.semverTags = semverTags.count
            stats.latestSemver = semverTags.first ?? ""
        }
        return stats
    }

    /// Batch-enrich files with git metadata using ONE git log call.
    /// Returns enriched files, per-author filesModified counts, and top churn files.
    func analyze(files: [ParsedFile]) -> (files: [ParsedFile], authorFileCounts: [String: Int], churnFiles: [FileChurnStat]) {
        let gitDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            print("⚠️  No .git directory found. Skipping Git analysis.")
            return (files, [:], [])
        }

        let total = files.count
        print("🔍 Analyzing git history (\(total) files, batch mode)...")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build file stats from single batch git log
        let batchStats = batchCollectFileStats()

        let elapsed1 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Batch git log parsed in \(String(format: "%.1f", elapsed1))s (\(batchStats.count) file entries)")

        // Accurate filesModified: count every file each author touched (not capped to top 3)
        let filePaths = Set(files.map { relativePath(for: $0.filePath) })
        var authorFileCounts: [String: Int] = [:]
        for (path, fs) in batchStats where filePaths.contains(path) {
            for author in fs.authorCounts.keys {
                authorFileCounts[author, default: 0] += 1
            }
        }

        // Enrich files
        var results: [ParsedFile] = []
        for file in files {
            let rel = relativePath(for: file.filePath)
            if let fs = batchStats[rel] {
                let topAuthors = fs.authorCounts
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map(\.key)
                var enriched = file
                enriched.gitMetadata = GitMetadata(
                    lastModified: fs.lastModified,
                    changeFrequency: fs.changeCount,
                    topAuthors: Array(topAuthors),
                    recentMessages: Array(fs.messages.prefix(3)),
                    firstCommitDate: fs.firstCommitDate
                )
                results.append(enriched)
            } else {
                results.append(file)
            }
        }

        let elapsed2 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Git analysis complete in \(String(format: "%.1f", elapsed2))s")

        let topChurn = batchStats
            .map { FileChurnStat(path: $0.key, changeCount: $0.value.changeCount) }
            .sorted { $0.changeCount > $1.changeCount }
            .prefix(25)

        return (results, authorFileCounts, Array(topChurn))
    }

    // MARK: - Batch Collection

    /// Single `git log --name-only` call. Streams output via pipe.
    /// For a 5000-file repo with 500 commits, this takes ~2-5s instead of ~50 min.
    private func batchCollectFileStats() -> [String: FileStats] {
        // We use streaming read to handle arbitrarily large output
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "log",
            "--pretty=format:__COMMIT__%n%ae%n%at%n%s",
            "--name-only",
            "-\(commitLimit)"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        // Read ALL data first (before waitUntilExit) to avoid pipe deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        // Parse
        var stats: [String: FileStats] = [:]
        let blocks = output.components(separatedBy: "__COMMIT__\n")

        for block in blocks where !block.isEmpty {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 3 else { continue }

            let author = String(lines[0])
            let timestamp = TimeInterval(lines[1]) ?? 0
            let message = String(lines[2])
            let changedFiles = lines.dropFirst(3)

            for fileLine in changedFiles {
                let trimmed = fileLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                var entry = stats[trimmed, default: FileStats()]
                entry.changeCount += 1
                entry.lastModified = max(entry.lastModified, timestamp)
                if entry.firstCommitDate == 0 || (timestamp > 0 && timestamp < entry.firstCommitDate) {
                    entry.firstCommitDate = timestamp
                }
                entry.authorCounts[author, default: 0] += 1
                if entry.messages.count < 5 {
                    entry.messages.append(message)
                }
                stats[trimmed] = entry
            }
        }
        return stats
    }

    // MARK: - Helpers

    private func relativePath(for absolutePath: String) -> String {
        let base = URL(fileURLWithPath: repoPath).standardizedFileURL.path
        if absolutePath.hasPrefix(base) {
            var result = String(absolutePath.dropFirst(base.count))
            if result.hasPrefix("/") { result = String(result.dropFirst()) }
            return result
        }
        return absolutePath
    }

    /// Returns a line-number → author-name map for a file via `git blame --porcelain`.
    func blameLines(filePath: String) -> [Int: String] {
        guard let output = git(["blame", "--porcelain", filePath]) else { return [:] }
        return parseBlameOutput(output)
    }

    /// Blames only the specified line numbers using `-L ln,ln` ranges — much faster than full-file blame.
    func blameLinesSubset(filePath: String, lineNumbers: Set<Int>) -> [Int: String] {
        guard !lineNumbers.isEmpty else { return [:] }
        var args = ["blame", "--porcelain"]
        for ln in lineNumbers.sorted() { args += ["-L", "\(ln),\(ln)"] }
        args.append(filePath)
        guard let output = git(args) else { return [:] }
        return parseBlameOutput(output)
    }

    private func parseBlameOutput(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var commitAuthors: [String: String] = [:]
        var currentCommit = ""
        var currentLine = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let fields = line.split(separator: " ")
            if fields.count >= 3, fields[0].count == 40, fields[0].allSatisfy({ $0.isHexDigit }) {
                currentCommit = String(fields[0])
                currentLine = Int(fields[2]) ?? 0
                continue
            }
            if line.hasPrefix("author ") {
                let author = String(line.dropFirst("author ".count))
                commitAuthors[currentCommit] = author
                if currentLine > 0 { result[currentLine] = author }
            } else if line.hasPrefix("\t") {
                if currentLine > 0, let author = commitAuthors[currentCommit] {
                    result[currentLine] = author
                }
            }
        }
        return result
    }

    @discardableResult
    func git(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }
}

// MARK: - File Stats

private struct FileStats {
    var changeCount: Int = 0
    var lastModified: TimeInterval = 0
    var firstCommitDate: TimeInterval = 0
    var authorCounts: [String: Int] = [:]
    var messages: [String] = []
}
