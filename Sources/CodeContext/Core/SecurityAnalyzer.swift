// Exey Panteleev
import Foundation

// MARK: - Models

struct APViolation {
    let file: String
    let fullPath: String
    let line: Int
    let snippet: String
    var author: String? = nil
}

enum APPriority: String {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"

    /// Multiplier applied to violation counts when computing weighted density.
    /// HIGH×2 reflects that a single critical finding carries more risk than two low-severity ones.
    var violationWeight: Double {
        switch self { case .high: return 2.0; case .medium: return 1.0; case .low: return 0.5 }
    }
}

// MARK: - Security Categories

/// The 14 security risk categories used by the security index.
/// `weight` values are points out of the 1000-point security index and sum to 1000.
/// `id` (rawValue) is the 1-based number shown in the report (1...14).
enum SecurityCategory: Int, CaseIterable {
    case insecureDataStorage = 1
    case crashFactors
    case unsafeDeprecated
    case supplyChain
    case memoryCorruption
    case cryptography
    case networkSecurity
    case authentication
    case ioValidation
    case binaryProtections
    case privacy
    case iosConfiguration
    case logicState
    case lowLevelBinary

    /// Display title shown in the report.
    var title: String {
        switch self {
        case .insecureDataStorage: return "Insecure Data Storage"
        case .crashFactors:        return "Crash Factors"
        case .unsafeDeprecated:    return "Unsafe & Deprecated Constructs"
        case .supplyChain:         return "Third-Party & Supply Chain Risks"
        case .memoryCorruption:    return "Memory Corruption & Exploit Factors"
        case .cryptography:        return "Cryptography Issues"
        case .networkSecurity:     return "Network Security"
        case .authentication:      return "Authentication & Authorization"
        case .ioValidation:        return "Input/Output Validation"
        case .binaryProtections:   return "Binary Protections"
        case .privacy:             return "Privacy Violations"
        case .iosConfiguration:    return "iOS Configuration Weaknesses"
        case .logicState:          return "Logic & State-based Exploit Factors"
        case .lowLevelBinary:      return "Low-level Binary Vulnerabilities"
        }
    }

    /// Short emoji marker per category.
    var icon: String {
        switch self {
        case .insecureDataStorage: return "\u{1F5C4}\u{FE0F}"
        case .crashFactors:        return "\u{1F4A5}"
        case .unsafeDeprecated:    return "\u{1F9E8}"
        case .supplyChain:         return "\u{1F4E6}"
        case .memoryCorruption:    return "\u{1F9E0}"
        case .cryptography:        return "\u{1F510}"
        case .networkSecurity:     return "\u{1F310}"
        case .authentication:      return "\u{1FAAA}"
        case .ioValidation:        return "\u{2328}\u{FE0F}"
        case .binaryProtections:   return "\u{1F6E1}\u{FE0F}"
        case .privacy:             return "\u{1F50D}"
        case .iosConfiguration:    return "\u{2699}\u{FE0F}"
        case .logicState:          return "\u{1F500}"
        case .lowLevelBinary:      return "\u{1F529}"
        }
    }

    /// Points this category contributes to the 1000-point index. Weights sum to 1000.
    var weight: Int {
        switch self {
        case .insecureDataStorage: return 130
        case .crashFactors:        return 120
        case .cryptography:        return 110
        case .authentication:      return 100
        case .networkSecurity:     return  90
        case .memoryCorruption:    return  80
        case .ioValidation:        return  80
        case .unsafeDeprecated:    return  60
        case .supplyChain:         return  50
        case .privacy:             return  50
        case .binaryProtections:   return  40
        case .iosConfiguration:    return  40
        case .logicState:          return  30
        case .lowLevelBinary:      return  20
        }
    }

    /// One-line description of what the category covers.
    var blurb: String {
        switch self {
        case .insecureDataStorage: return "Hardcoded secrets, unprotected local storage, sensitive logging."
        case .crashFactors:        return "Force unwraps, try!, as!, IUOs, deadlocks, runtime selector failures."
        case .unsafeDeprecated:    return "Legacy ObjC APIs, deprecated calls, compile-time literals."
        case .supplyChain:         return "Vulnerable or unaudited dependencies, dependency confusion."
        case .memoryCorruption:    return "Unsafe pointers, use-after-free, buffer/integer overflows."
        case .cryptography:        return "Weak algorithms, insecure randomness, broken modes, key handling."
        case .networkSecurity:     return "ATS disabled, missing pinning, plaintext communication."
        case .authentication:      return "Credential misuse, broken cert validation, session handling."
        case .ioValidation:        return "Injection, path traversal, command injection."
        case .binaryProtections:   return "Obfuscation, debugger/jailbreak detection, integrity checks."
        case .privacy:             return "Excessive permissions, consent gaps, identifier misuse."
        case .iosConfiguration:    return "Info.plist misconfigurations (backup, ATS, sharing)."
        case .logicState:          return "Race conditions, jailbreak bypasses, insecure IPC, state bugs."
        case .lowLevelBinary:      return "C/ObjC/C++ memory-corruption primitives and ObjC runtime hazards."
        }
    }
}

struct APCheck {
    let name: String
    let description: String
    let priority: APPriority
    let category: SecurityCategory
    let detect: (_ filePath: String, _ lines: [String]) -> [APViolation]
    /// One-shot project-level scan (plist files, whole-repo absence checks).
    /// Called once with `repoPath` after the per-file pass; ignored when repoPath is empty.
    var projectDetect: ((_ repoPath: String) -> [APViolation])? = nil
    /// True when `detect` is a no-op stub and all findings come from `projectDetect`.
    /// Used by the streaming output to defer printing until after the project-level pass.
    var isProjectOnly: Bool = false
}

struct APResult {
    let check: APCheck
    let violations: [APViolation]
    /// Total number of violations found before the `maxViolations` cap was applied.
    /// Equal to `violations.count` when the cap was not reached.
    let totalCount: Int
    var passed: Bool { violations.isEmpty }

    init(check: APCheck, violations: [APViolation], totalCount: Int? = nil) {
        self.check = check
        self.violations = violations
        self.totalCount = totalCount ?? violations.count
    }
}

// MARK: - Security Score

/// Per-category risk contribution within the 1000-point security index.
struct CategoryScore {
    let category: SecurityCategory
    /// Number of checks defined for this category.
    let checkCount: Int
    /// Total violations found across this category's checks.
    let violations: Int
    /// 0...1 risk fraction for this category (0 = clean, 1 = saturated risk).
    let riskFraction: Double
    /// Points contributed to the 1000-point index = riskFraction * weight.
    let points: Int

    var weight: Int { category.weight }
    /// True when no checks back this category yet (informational only).
    var notAssessed: Bool { checkCount == 0 }
    /// 0...100 risk percentage, for the per-category bars.
    var riskPercent: Int { Int((riskFraction * 100).rounded()) }
}

/// The whole-project security index (0...1000, higher = more risk).
struct SecurityScore {
    let total: Int                  // 0...1000
    let categories: [CategoryScore] // ordered by SecurityCategory.rawValue (1...13)

    /// Risk band for the gauge, mirroring the toxic-chat gauge bands.
    enum Band {
        case healthy, light, elevated, critical
        var label: String {
            switch self {
            case .healthy:  return "Hardened"
            case .light:    return "Minor exposure"
            case .elevated: return "Elevated risk"
            case .critical: return "Critical exposure"
            }
        }
        var color: String {
            switch self {
            case .healthy:  return "#5a8a7a"
            case .light:    return "#a0a030"
            case .elevated: return "#c0a030"
            case .critical: return "#c05040"
            }
        }
        var range: (lo: Int, hi: Int) {
            switch self {
            case .healthy:  return (0, 199)
            case .light:    return (200, 499)
            case .elevated: return (500, 799)
            case .critical: return (800, 1000)
            }
        }
    }

    var band: Band {
        switch total {
        case ..<200:    return .healthy
        case 200..<500: return .light
        case 500..<800: return .elevated
        default:        return .critical
        }
    }
}

// MARK: - Analyzer

struct SecurityAnalyzer {
    static let maxViolations = 100

    /// Runs all checks and streams each result via `onCheckComplete` as it finishes.
    /// Per-file checks stream immediately; project-only checks stream after the project-level pass.
    static func run(files: [ParsedFile], repoPath: String = "", commitLimit: Int = 500,
                    onCheckComplete: ((APResult) -> Void)? = nil) -> [APResult] {
        let checks = allChecks()
        let swiftFiles = files.filter { $0.filePath.hasSuffix(".swift") }
        let nativeFiles = files.filter {
            let p = $0.filePath
            return p.hasSuffix(".m") || p.hasSuffix(".mm") || p.hasSuffix(".c") || p.hasSuffix(".cpp")
        }

        // ── Phase 1: load all file contents in parallel (one read per file) ──
        var swiftContents: [(String, [String])] = Array(repeating: ("", []), count: swiftFiles.count)
        DispatchQueue.concurrentPerform(iterations: swiftFiles.count) { idx in
            let fp = swiftFiles[idx].filePath
            guard let c = try? String(contentsOfFile: fp, encoding: .utf8) else { return }
            swiftContents[idx] = (fp, c.components(separatedBy: "\n"))
        }
        let loadedSwift = swiftContents.filter { !$0.0.isEmpty }

        var nativeContents: [(String, [String])] = Array(repeating: ("", []), count: nativeFiles.count)
        if !nativeFiles.isEmpty {
            DispatchQueue.concurrentPerform(iterations: nativeFiles.count) { idx in
                let fp = nativeFiles[idx].filePath
                guard let c = try? String(contentsOfFile: fp, encoding: .utf8) else { return }
                nativeContents[idx] = (fp, c.components(separatedBy: "\n"))
            }
        }
        let loadedNative = nativeContents.filter { !$0.0.isEmpty }
        let nativeCheckIndices = Set(checks.indices.filter { checks[$0].category == .lowLevelBinary })

        // ── Phase 2: per-check parallel scan ─────────────────────────────────
        // Each check iterates all in-memory files serially; checks run concurrently.
        // This lets onCheckComplete stream each check result as soon as it finishes.
        var results: [APResult] = checks.map { APResult(check: $0, violations: [], totalCount: 0) }
        let resultsLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: checks.count) { checkIdx in
            let check = checks[checkIdx]
            if check.isProjectOnly { return }   // deferred to Phase 3 stream

            var violations: [APViolation] = []
            var totalCount = 0

            for (fp, lines) in loadedSwift {
                let vs = check.detect(fp, lines)
                totalCount += vs.count
                if violations.count < maxViolations {
                    violations.append(contentsOf: vs.prefix(maxViolations - violations.count))
                }
            }
            if nativeCheckIndices.contains(checkIdx) {
                for (fp, lines) in loadedNative {
                    let vs = check.detect(fp, lines)
                    totalCount += vs.count
                    if violations.count < maxViolations {
                        violations.append(contentsOf: vs.prefix(maxViolations - violations.count))
                    }
                }
            }

            let result = APResult(check: check, violations: violations, totalCount: totalCount)
            onCheckComplete?(result)    // stream immediately when this check finishes

            resultsLock.lock()
            results[checkIdx] = result
            resultsLock.unlock()
        }

        // ── Phase 3: project-level checks (sequential, plist / whole-repo) ───
        if !repoPath.isEmpty {
            for i in checks.indices {
                guard let pd = checks[i].projectDetect else { continue }
                let vs = pd(repoPath)
                let cur = results[i]
                let have = cur.violations.count
                let extra = have < maxViolations ? Array(vs.prefix(maxViolations - have)) : []
                results[i] = APResult(
                    check: cur.check,
                    violations: cur.violations + extra,
                    totalCount: cur.totalCount + vs.count
                )
            }
        }
        // Stream project-only checks after project-level pass (their results weren't ready earlier)
        for i in checks.indices where checks[i].isProjectOnly {
            onCheckComplete?(results[i])
        }

        // ── Phase 4: blame enrichment (parallel, range-limited) ───────────────
        if !repoPath.isEmpty {
            let git = GitAnalyzer(repoPath: repoPath, commitLimit: commitLimit)
            var fileToLines: [String: Set<Int>] = [:]
            for result in results {
                for v in result.violations where v.line > 0 {
                    fileToLines[v.fullPath, default: []].insert(v.line)
                }
            }
            let filePaths = Array(fileToLines.keys)
            var blameCache: [String: [Int: String]] = [:]
            let blameLock = NSLock()
            DispatchQueue.concurrentPerform(iterations: filePaths.count) { idx in
                let path = filePaths[idx]
                let lines = fileToLines[path] ?? []
                let blame = git.blameLinesSubset(filePath: path, lineNumbers: lines)
                blameLock.lock()
                blameCache[path] = blame
                blameLock.unlock()
            }
            results = results.map { result in
                let enriched = result.violations.map { v -> APViolation in
                    var updated = v
                    updated.author = blameCache[v.fullPath]?[v.line]
                    return updated
                }
                return APResult(check: result.check, violations: enriched, totalCount: result.totalCount)
            }
        }

        return results
    }

    /// Runs all checks and also computes the 0...1000 security index.
    static func runWithScore(files: [ParsedFile], repoPath: String = "", commitLimit: Int = 500,
                             onCheckComplete: ((APResult) -> Void)? = nil) -> (results: [APResult], score: SecurityScore) {
        let results = run(files: files, repoPath: repoPath, commitLimit: commitLimit, onCheckComplete: onCheckComplete)
        let swiftFileCount = files.filter { $0.filePath.hasSuffix(".swift") }.count
        let score = computeScore(results, fileCount: swiftFileCount)
        return (results, score)
    }

    /// Aggregates check results into per-category scores and the overall 0...1000 index.
    ///
    /// Higher index = more risk. Each category contributes up to `weight` points; its
    /// contribution scales with a saturating function of violation *density* (violations
    /// per scanned file), so a handful of issues in a huge codebase doesn't peg the gauge,
    /// while pervasive issues approach the full weight. Categories with no checks defined
    /// are reported as "not assessed" and contribute 0 points.
    static func computeScore(_ results: [APResult], fileCount: Int) -> SecurityScore {
        // Group results by category.
        var byCategory: [SecurityCategory: [APResult]] = [:]
        for r in results { byCategory[r.check.category, default: []].append(r) }

        let denom = Double(max(fileCount, 1))

        var categoryScores: [CategoryScore] = []
        var total = 0

        for category in SecurityCategory.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let catResults = byCategory[category] ?? []
            let checkCount = catResults.count
            // Use totalCount (uncapped) so 7823 force-unwraps score more than 100.
            let violations = catResults.reduce(0) { $0 + $1.totalCount }

            let risk: Double
            if checkCount == 0 || violations == 0 {
                risk = 0
            } else {
                // Weighted violation count: HIGH×2, MEDIUM×1, LOW×0.5.
                // Logistic curve risk = density / (density + C), C=2.
                // For 1 file + 1 HIGH finding → risk = 0.50 (vs 0.98 with the old exponential).
                let weighted = catResults.reduce(0.0) { acc, r in
                    acc + Double(r.totalCount) * r.check.priority.violationWeight
                }
                let density = weighted / denom
                risk = density / (density + 2.0)
            }

            let points = Int((risk * Double(category.weight)).rounded())
            total += points

            categoryScores.append(CategoryScore(
                category: category,
                checkCount: checkCount,
                violations: violations,
                riskFraction: risk,
                points: points
            ))
        }

        total = max(0, min(1000, total))
        return SecurityScore(total: total, categories: categoryScores)
    }

    // MARK: - Path / Snippet Helpers

    static func displayPath(_ filePath: String) -> String {
        let parts = filePath.components(separatedBy: "/")
        return parts.count > 3 ? parts.suffix(3).joined(separator: "/") : parts.joined(separator: "/")
    }

    static func snippet(_ line: String) -> String {
        let s = line.trimmingCharacters(in: .whitespaces)
        return s.count > 100 ? String(s.prefix(100)) + "\u{2026}" : s
    }

    static func viol(_ filePath: String, _ lineIdx: Int, _ lines: [String]) -> APViolation {
        APViolation(file: displayPath(filePath), fullPath: filePath, line: lineIdx + 1, snippet: snippet(lines[lineIdx]))
    }

    /// Returns the line with all string literal content replaced by spaces,
    /// so checks don't trigger on keywords that appear only inside strings or docs.
    static func stripStrings(_ line: String) -> String {
        var result = ""
        var inString = false
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if c == "\\" && inString {
                result.append("  ")
                let next = line.index(after: idx)
                idx = next < line.endIndex ? line.index(after: next) : next
                continue
            }
            if c == "\"" {
                inString.toggle()
                result.append(c)
            } else {
                result.append(inString ? " " : c)
            }
            idx = line.index(after: idx)
        }
        return result
    }

    /// True if the line is a comment or documentation line.
    static func isComment(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("//") || t.hasPrefix("*") || t.hasPrefix("/*")
    }

    /// Strips trailing `// comment` from a line while preserving string literal content.
    /// Use this for checks that need to inspect literal values (e.g. "http://") without
    /// firing on code that has been commented out inline: `someCall() // "http://old"`
    static func stripLineComment(_ line: String) -> String {
        var result = ""
        var inString = false
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if c == "\\" && inString {
                result.append(c)
                let next = line.index(after: idx)
                if next < line.endIndex { result.append(line[next]); idx = line.index(after: next) }
                else { idx = next }
                continue
            }
            if c == "\"" { inString.toggle() }
            if !inString && c == "/" {
                let next = line.index(after: idx)
                if next < line.endIndex && line[next] == "/" { break }
            }
            result.append(c)
            idx = line.index(after: idx)
        }
        return result
    }

    /// Word-boundary-aware function-call check: returns true only when `funcCall`
    /// (e.g. `"free("`) is NOT preceded by an identifier character, preventing
    /// `myFree(` or `getFreeSpace(` from matching `free(`.
    static func containsCall(_ code: String, _ funcCall: String) -> Bool {
        var pos = code.startIndex
        while let range = code.range(of: funcCall, range: pos..<code.endIndex) {
            if range.lowerBound == code.startIndex {
                return true
            }
            let before = code[code.index(before: range.lowerBound)]
            if !before.isLetter && !before.isNumber && before != "_" {
                return true
            }
            pos = range.upperBound
        }
        return false
    }
}


// MARK: - Check Registry

private extension SecurityAnalyzer {
    static func allChecks() -> [APCheck] {
        [
            // --- HIGH ---
            APCheck(
                name: "Hardcoded Secrets",
                description: "Hardcoding API keys, passwords, or tokens embeds credentials into version history permanently. Load secrets from environment variables, the Keychain, or a secure configuration system at runtime. Any credential found here must be rotated immediately - consider it compromised.",
                priority: .high,
                category: .insecureDataStorage,
                detect: checkHardcodedSecret
            ),
            APCheck(
                name: "UserDefaults Only for Non-Sensitive Data",
                description: "UserDefaults is stored as a plain-text plist, unprotected and readable by any process with sandbox access. Never store passwords, tokens, or personal data there. Use the Keychain for secrets - it is encrypted and access-controlled by the OS.",
                priority: .high,
                category: .insecureDataStorage,
                detect: checkUserDefaultsSensitive
            ),
            APCheck(
                name: "Insecure Randomness in Security Context (arc4random)",
                description: "`arc4random()` / `arc4random_uniform()` are cryptographically weak — found in files that perform encryption, signing, padding, or secure-ID generation. These values must be unpredictable: replace with `SecRandomCopyBytes` or `CryptoKit.SystemRandomNumberGenerator`.",
                priority: .high,
                category: .cryptography,
                detect: checkInsecureRandomCrypto
            ),
            APCheck(
                name: "Deprecated arc4random in Non-Security Code",
                description: "`arc4random()` and `arc4random_uniform()` are deprecated since Swift 4.2. For UI animations, particle effects, and other non-security randomness, prefer `Int.random(in:)` / `Float.random(in:)` from Swift's standard library — they are faster, type-safe, and not deprecated.",
                priority: .low,
                category: .unsafeDeprecated,
                detect: checkInsecureRandomUI
            ),
            APCheck(
                name: "Never Force Unwrap or Force Try (! / try!)",
                description: "Force-unwrapping a nil optional (`x!`) and force-try (`try!`) both crash the app with a fatal error on failure, producing a poor user experience and no recovery path. Use `if let`, `guard let`, `??`, or `try?`/`do-catch` to handle the absent or error case safely. `try!` violations are listed first.",
                priority: .high,
                category: .crashFactors,
                detect: checkForceUnwrap
            ),
            APCheck(
                name: "Avoid Force Casts (as!)",
                description: "A forced downcast that fails crashes the app. Use the conditional form `as?` combined with `if let` or `guard let` to safely attempt the cast and handle the failure case instead of aborting.",
                priority: .high,
                category: .crashFactors,
                detect: checkForceCast
            ),
            APCheck(
                name: "Avoid DispatchQueue.main.sync",
                description: "Calling `DispatchQueue.main.sync` from the main thread causes a guaranteed deadlock that freezes the app - an availability failure and a denial-of-service surface. Use `DispatchQueue.main.async` instead, or restructure to avoid dispatching to main from main.",
                priority: .high,
                category: .crashFactors,
                detect: checkDispatchMainSync
            ),

            // --- MEDIUM ---
            APCheck(
                name: "Avoid Implicitly Unwrapped Optionals (IUOs)",
                description: "Implicitly unwrapped optionals (`Type!`) bypass optional safety: if nil when accessed, the app crashes. Use them only for IBOutlets and properties guaranteed to be set before first access (e.g., in `viewDidLoad`). For everything else, use a regular optional `?` and unwrap explicitly.",
                priority: .medium,
                category: .crashFactors,
                detect: checkImplicitlyUnwrappedOptionals
            ),
            APCheck(
                name: "Replace Deprecated openURL",
                description: "`UIApplication.shared.openURL(_:)` was deprecated in iOS 10. Use `open(_:options:completionHandler:)` instead - it lets the system handle the transition and provides a completion callback. Deprecated APIs receive no security maintenance.",
                priority: .medium,
                category: .unsafeDeprecated,
                detect: checkDeprecatedOpenURL
            ),

            // ── Insecure Data Storage (continued) ──────────────────────────
            APCheck(
                name: "Sensitive Data in Print / Debug Logs",
                description: "Logging passwords, tokens, or secrets via `print` or `debugPrint` writes sensitive data to device logs readable by other processes or extractable from crash reports. Redact sensitive fields or use `os_log` / `Logger` with the `.private` privacy flag.",
                priority: .low,
                category: .insecureDataStorage,
                detect: checkSensitivePrint
            ),

            APCheck(
                name: "Unencrypted Database (Realm / CoreData / SQLite)",
                description: "A Realm database opened without `encryptionKey`, a Core Data store added without `NSPersistentStoreFileProtectionKey`, or a SQLite database opened without SQLCipher's `sqlite3_key` stores all records in plaintext on disk. On a jailbroken device or via direct iTunes backup extraction the entire database is readable. Always supply an encryption key derived from the Keychain — never hardcode it. The Realm check is project-wide: if `encryptionKey` appears anywhere in the codebase, all Realm call sites are considered safe.",
                priority: .high,
                category: .insecureDataStorage,
                detect: checkUnencryptedDatabaseLocal,
                projectDetect: checkUnencryptedRealmProject
            ),
            APCheck(
                name: "Hardcoded Secrets in Info.plist / xcconfig",
                description: "API keys, tokens, and secrets embedded in `Info.plist` or `.xcconfig` files are included verbatim in the app bundle and are trivially extracted with `strings` or `plutil`. Store secrets in the Keychain, retrieve them at launch from a secure backend, or reference them via CI/CD environment variables that are never committed to source control.",
                priority: .high,
                category: .insecureDataStorage,
                detect: { _, _ in [] },
                projectDetect: checkSecretsInConfigFiles,
                isProjectOnly: true
            ),
            APCheck(
                name: "Sensitive Responses Persisted by URLCache / WKWebView",
                description: "`URLCache` configured with non-zero disk capacity persists authenticated responses — including Bearer tokens in response bodies — to the device's file system. `WKWebsiteDataStore.default()` similarly caches cookies and web storage. Use `URLCache(memoryCapacity:diskCapacity: 0)` for sessions carrying auth data, and `WKWebViewConfiguration` with a `.nonPersistent()` data store for sensitive web views.",
                priority: .medium,
                category: .insecureDataStorage,
                detect: checkSensitiveURLCaching
            ),

            // ── Crash Factors (continued) ───────────────────────────────────
            APCheck(
                name: "fatalError / preconditionFailure in Production Code",
                description: "`fatalError` and `preconditionFailure` terminate the process immediately with no recovery path. They are also common placeholders left over from Xcode-generated stubs. Replace with a recoverable error, a graceful fallback, or ensure the path is truly unreachable before keeping them in production.",
                priority: .medium,
                category: .crashFactors,
                detect: checkFatalError
            ),

            // ── Unsafe & Deprecated (continued) ────────────────────────────
            APCheck(
                name: "Dangerous C String Functions",
                description: "`gets`, `sprintf`, `strcpy`, `strcat`, `scanf`, and related functions perform no bounds checking — a too-short buffer causes memory corruption exploitable for code execution. Use length-limited variants (`snprintf`, `strlcpy`, `strlcat`) or Swift-native string handling instead.",
                priority: .high,
                category: .unsafeDeprecated,
                detect: checkDangerousCFunctions
            ),
            APCheck(
                name: "Weak Cryptographic Algorithm Constants (DES / 3DES / RC2 / RC4)",
                description: "DES, 3DES, RC2, and RC4 are broken or insufficiently secure. DES and RC4 are fully compromised; 3DES is deprecated by NIST and vulnerable to Sweet32. Use AES-256-GCM or ChaCha20-Poly1305 via CryptoKit or CommonCrypto's AES interface.",
                priority: .high,
                category: .unsafeDeprecated,
                detect: checkWeakCryptoConstants
            ),
            APCheck(
                name: "UIWebView Usage (Deprecated, No Security Patches Since iOS 12)",
                description: "`UIWebView` has been deprecated since iOS 12 and removed from the App Store review guidelines. It no longer receives security patches, carries known XSS and memory-safety vulnerabilities, and was rejected by App Store review since April 2020. Replace all `UIWebView` instances with `WKWebView`.",
                priority: .high,
                category: .unsafeDeprecated,
                detect: checkUIWebView
            ),

            // ── Third-Party & Supply Chain ──────────────────────────────────
            APCheck(
                name: "HTTP (Non-TLS) Package Source URLs",
                description: "Using `http://` for Swift Package dependencies allows a MITM attacker to inject malicious code into any package fetch. Always use `https://` or SSH URLs, and pin to exact version tags rather than open ranges.",
                priority: .high,
                category: .supplyChain,
                detect: checkHTTPPackageSource
            ),
            APCheck(
                name: "Floating / Branch Dependency Pins",
                description: "Pinning a dependency to a branch (`.branch(\"main\")`) means any push to that branch — including a supply-chain compromise — silently updates your build without review. Always pin to a version tag or commit hash in production.",
                priority: .medium,
                category: .supplyChain,
                detect: checkFloatingDependency
            ),

            // ── Memory Corruption & Exploit Factors ────────────────────────
            APCheck(
                name: "Unsafe Pointer Usage",
                description: "Direct use of `UnsafePointer`, `UnsafeMutablePointer`, `UnsafeRawPointer`, `withUnsafeBytes`, etc. bypasses Swift's memory-safety guarantees. Incorrect pointer arithmetic, aliasing, or lifetime management causes undefined behaviour exploitable for memory corruption. Prefer higher-level Swift APIs; review every unsafe block thoroughly.",
                priority: .high,
                category: .memoryCorruption,
                detect: checkUnsafePointers
            ),
            APCheck(
                name: "Manual Reference Counting (Unmanaged<T>)",
                description: "`Unmanaged<T>` with `passRetained`, `takeRetainedValue`, etc. requires manually balanced retains/releases. A mismatch causes either a use-after-free (exploitable) or a leak. Use `Unmanaged` only for required C-API bridging; validate lifetimes carefully.",
                priority: .medium,
                category: .memoryCorruption,
                detect: checkManualMemory
            ),

            // ── Cryptography Issues (continued) ────────────────────────────
            APCheck(
                name: "Weak Hash Algorithm (MD5 / SHA-1)",
                description: "MD5 and SHA-1 are cryptographically broken: practical collision attacks exist and preimage resistance is weakened. Never use them for integrity, signatures, or password hashing. Use SHA-256+ for general hashing, and Argon2/bcrypt/scrypt for passwords.",
                priority: .high,
                category: .cryptography,
                detect: checkWeakHash
            ),
            APCheck(
                name: "ECB Cipher Mode",
                description: "ECB encrypts each block independently, so identical plaintext blocks produce identical ciphertext blocks — leaking patterns and making ciphertexts malleable. Always use an authenticated mode such as AES-GCM.",
                priority: .high,
                category: .cryptography,
                detect: checkECBMode
            ),
            APCheck(
                name: "Hardcoded IV / Nonce",
                description: "A static, hardcoded initialization vector defeats the randomness requirement of symmetric encryption — two identical plaintexts produce identical ciphertexts, enabling pattern analysis and known-plaintext attacks. Generate a fresh, cryptographically random IV/nonce per encryption operation.",
                priority: .medium,
                category: .cryptography,
                detect: checkHardcodedIV
            ),

            APCheck(
                name: "Hardcoded Encryption Key",
                description: "A symmetric key or AES key assigned from a string literal (`let key = \"abc123...\"`) or a hardcoded `[UInt8]` array is embedded in the binary and extractable with `strings`. Key material must be generated at runtime and stored in the Keychain — never written in source code.",
                priority: .high,
                category: .cryptography,
                detect: checkHardcodedEncryptionKey
            ),
            APCheck(
                name: "CBC Mode Without Authentication (MAC)",
                description: "CBC mode alone provides confidentiality but no integrity: an attacker who can submit chosen ciphertexts can exploit padding-oracle vulnerabilities to decrypt or forge messages without knowing the key. Always pair CBC with a separate HMAC (Encrypt-then-MAC), or replace with an authenticated mode such as AES-GCM or ChaChaPoly1305 which provides both in one pass. Note: this check is file-local — an HMAC defined in a separate CryptoHelper file will not suppress this warning.",
                priority: .high,
                category: .cryptography,
                detect: checkCBCWithoutMAC
            ),
            APCheck(
                name: "Insufficient PBKDF2 Iterations",
                description: "A PBKDF2 round count below 10,000 can be brute-forced on commodity hardware in seconds. NIST SP 800-132 recommends ≥ 600,000 iterations with SHA-256 for 2023+. Raise the iteration count and store it alongside the salt so future migrations remain possible.",
                priority: .medium,
                category: .cryptography,
                detect: checkPBKDF2Iterations
            ),

            // ── Network Security ────────────────────────────────────────────
            APCheck(
                name: "Plaintext HTTP URLs",
                description: "Hardcoded `http://` URLs transmit all data — tokens, session cookies, API responses — in cleartext. Any network observer can read or modify traffic (MITM). Upgrade all communications to HTTPS and ensure ATS is not disabled.",
                priority: .high,
                category: .networkSecurity,
                detect: checkHTTPURL
            ),
            APCheck(
                name: "Certificate Validation Bypass",
                description: "Disabling certificate chain or domain validation (`allowsAnyHTTPSCertificate`, `validatesDomainName = false`, blindly calling `completionHandler(.useCredential, ...)`) makes the app vulnerable to any MITM with a self-signed certificate. Implement proper pinning or rely on the system CA store without bypass.",
                priority: .high,
                category: .networkSecurity,
                detect: checkCertValidationBypass
            ),
            APCheck(
                name: "URLSessionDelegate Challenge Bypass (unconditional useCredential)",
                description: "`completionHandler(.useCredential, ...)` in `urlSession(_:didReceive:completionHandler:)` without a prior `SecTrustEvaluateWithError` call unconditionally accepts any certificate the server presents — including self-signed ones planted by a MITM proxy. Always evaluate trust before granting a credential; cancel with `.cancelAuthenticationChallenge` on failure.",
                priority: .high,
                category: .networkSecurity,
                detect: checkURLSessionDelegateBypass
            ),
            APCheck(
                name: "ATS Disabled in Info.plist (NSAllowsArbitraryLoads)",
                description: "`NSAllowsArbitraryLoads = true` disables App Transport Security, allowing connections to any HTTP server and bypassing TLS requirements enforced since iOS 9. Remove this key or scope it to specific domains that genuinely require exceptions.",
                priority: .high,
                category: .networkSecurity,
                detect: { _, _ in [] },
                projectDetect: checkATSDisabled,
                isProjectOnly: true
            ),
            APCheck(
                name: "WebView JavaScript Injection / Unsafe Configuration",
                description: "Passing interpolated strings into `evaluateJavaScript` lets attacker-controlled content execute arbitrary JS inside the web view's origin — equivalent to stored XSS. `allowFileAccessFromFileURLs` / `allowUniversalAccessFromFileURLs` lets JS escape the sandbox and read the local filesystem. `allowContentJavaScript = true` (iOS 14+) re-enables JS if it was disabled. Setting `isFraudulentWebsiteWarningEnabled = false` disables Safe Browsing, letting phishing pages load silently. Always sanitize data crossing into the JS bridge; disable file-URL access and keep Safe Browsing enabled.",
                priority: .high,
                category: .networkSecurity,
                detect: checkWebViewJSInjection
            ),

            APCheck(
                name: "Hardcoded Auth Token in HTTP Header",
                description: "A literal `\"Bearer ...\"` or `\"Basic ...\"` value passed to `setValue(_:forHTTPHeaderField:)` embeds a live credential in the binary. Any user with `strings` or a debugger can extract it. Store tokens in the Keychain and inject them at request-build time from a secure credential store.",
                priority: .high,
                category: .networkSecurity,
                detect: checkHardcodedAuthHeader
            ),
            APCheck(
                name: "URLSessionConfiguration Allows Arbitrary Loads (in Code)",
                description: "Setting `.allowsArbitraryLoads = true` on a `URLSessionConfiguration` in code disables TLS enforcement for that session, bypassing ATS for all requests it makes — even if the plist does not set `NSAllowsArbitraryLoads`. Remove this flag or scope exceptions to specific domains that genuinely require them.",
                priority: .high,
                category: .networkSecurity,
                detect: checkURLSessionArbitraryLoads
            ),

            // ── Authentication & Authorization ──────────────────────────────
            APCheck(
                name: "Over-Accessible Keychain Items (kSecAttrAccessibleAlways)",
                description: "`kSecAttrAccessibleAlways` and `kSecAttrAccessibleAlwaysThisDeviceOnly` make keychain items readable even when the device is locked, bypassing Secure Enclave protection. Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` or `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` instead.",
                priority: .high,
                category: .authentication,
                detect: checkKeychainAccessible
            ),
            APCheck(
                name: "Deprecated SecTrustEvaluate (use SecTrustEvaluateWithError)",
                description: "`SecTrustEvaluate` is deprecated since iOS 13 / macOS 10.15 and does not return an error object, making silent failure easy. Use `SecTrustEvaluateWithError(_:_:)` which forces callers to handle the failure case explicitly.",
                priority: .medium,
                category: .authentication,
                detect: checkDeprecatedSecTrust
            ),
            APCheck(
                name: "Biometric Auth Not Bound to Keychain Item",
                description: "Calling `evaluatePolicy` without binding the result to a keychain item protected by `SecAccessControlCreateWithFlags` / `.biometryCurrentSet` means the biometric gate returns a bare boolean that a runtime hook or debugger can trivially bypass. Bind sensitive operations to a keychain item with `.userPresence` or `.biometryCurrentSet` access control so the Secure Enclave enforces the check, not your app code.",
                priority: .high,
                category: .authentication,
                detect: checkBiometricWithoutKeychain
            ),

            // ── Input/Output Validation ─────────────────────────────────────
            APCheck(
                name: "SQL Injection (String Interpolation in Queries)",
                description: "Building SQL queries with string interpolation (`\"SELECT … WHERE name = '\\(userInput)'\"`) lets a single-quote break the query structure and execute attacker-controlled SQL. Use parameterized queries: prepare the statement with `?` / `:name` placeholders and bind values via `sqlite3_bind_*` so values are never treated as executable SQL.",
                priority: .high,
                category: .ioValidation,
                detect: checkSQLInjection
            ),
            APCheck(
                name: "Insecure Deserialization (NSKeyedUnarchiver)",
                description: "`NSKeyedUnarchiver.unarchiveObject(with:)` and `unarchiveTopLevelObjectWithData` allow a malicious archive to instantiate arbitrary `NSObject` subclasses — a code-execution surface. Use the secure-coding initializer `NSKeyedUnarchiver(forReadingFrom:)` with `requiresSecureCoding = true` and an explicit `allowedClasses` set. Also flag `NSKeyedArchiver` used with `requiringSecureCoding: false`.",
                priority: .high,
                category: .ioValidation,
                detect: checkInsecureDeserialization
            ),
            APCheck(
                name: "Path Traversal Risk (\"..\" in File Paths)",
                description: "Path segments containing `..` can escape intended directory boundaries when constructed from user-controlled input. Validate and canonicalize all paths; reject inputs containing `..` or use Foundation's `standardized`/`resolvingSymlinksInPath` and compare against an expected root prefix.",
                priority: .medium,
                category: .ioValidation,
                detect: checkPathTraversal
            ),
            APCheck(
                name: "Shell Command Injection Risk (Process / NSTask)",
                description: "Constructing shell commands with `Process`/`NSTask` and user-supplied arguments is dangerous: an attacker controlling any part of the command string can inject arbitrary shell commands. Pass arguments as individual array elements — never as a shell-expanded string — and validate all inputs against a strict allowlist.",
                priority: .high,
                category: .ioValidation,
                detect: checkShellInjection
            ),

            // ── Binary Protections ──────────────────────────────────────────
            APCheck(
                name: "Debug / Diagnostic Framework in Production",
                description: "Frameworks like FLEX, Reveal, Chisel, Dotzu, or DBDebugToolkit expose runtime internals (view hierarchy, network traffic, keychain) to anyone with device access. Gate them behind `#if DEBUG` or remove them entirely before release.",
                priority: .high,
                category: .binaryProtections,
                detect: checkDebugToolsInProduction
            ),
            APCheck(
                name: "No Jailbreak Detection in Codebase",
                description: "No jailbreak/root-detection patterns were found. On a jailbroken device, code-signing is bypassed, sandbox boundaries are removed, and runtime hooks can intercept API calls. For sensitive applications implement active jailbreak detection and respond accordingly.",
                priority: .medium,
                category: .binaryProtections,
                detect: { _, _ in [] },
                projectDetect: checkJailbreakDetectionAbsent,
                isProjectOnly: true
            ),
            APCheck(
                name: "No Anti-Tampering Protections Found",
                description: "No runtime anti-tampering signals were detected — no anti-debug checks (PT_DENY_ATTACH, sysctl-based), no simulator-environment guards, and no tweak-injection awareness (DYLD_INSERT_LIBRARIES, Substrate). For security-sensitive apps, implement layered runtime integrity checks to raise the cost of reverse-engineering and dynamic analysis.",
                priority: .medium,
                category: .binaryProtections,
                detect: { _, _ in [] },
                projectDetect: checkAntiTamperingAbsent,
                isProjectOnly: true
            ),

            // ── Privacy Violations ──────────────────────────────────────────
            APCheck(
                name: "Clipboard Data Access",
                description: "Reading from `UIPasteboard.general` without a clear user action can silently harvest sensitive data copied from another app — passwords, credit-card numbers, OTPs. iOS 14+ notifies users of clipboard access. Restrict reads to explicit user interactions; never poll the pasteboard in background tasks.",
                priority: .medium,
                category: .privacy,
                detect: checkClipboardAccess
            ),
            APCheck(
                name: "Device Fingerprinting / Advertising ID",
                description: "Using `advertisingIdentifier`, `ASIdentifierManager`, or carrier identifiers without consent violates App Store Guidelines 5.1.2 and GDPR/CCPA. Request ATT permission before accessing the IDFA; prefer `identifierForVendor` for analytics and anonymise persistent identifiers.",
                priority: .low,
                category: .privacy,
                detect: checkDeviceFingerprint
            ),
            APCheck(
                name: "Declared Permission Without API Usage (Info.plist Mismatch)",
                description: "An `NSXxxUsageDescription` key in `Info.plist` without any corresponding API usage in the codebase signals a copy-paste leftover or a permission requested beyond actual needs — both a privacy risk and an App Store rejection trigger. Remove unused permission descriptions or verify the corresponding API (e.g. `AVCaptureDevice` for camera, `CLLocationManager` for location) is actually called.",
                priority: .medium,
                category: .privacy,
                detect: { _, _ in [] },
                projectDetect: checkPermissionMismatch,
                isProjectOnly: true
            ),
            APCheck(
                name: "Crash Reporter Initialized Without Data Scrubbing",
                description: "PLCrashReporter, Crashlytics, Sentry, and Bugsnag capture full stack frames, thread state, and by default any in-scope variables — which may include passwords, tokens, or PII. If no scrubbing callback (`beforeSend`, `eventProcessor`, `redactedKeys`) is configured in the same setup file, sensitive values may be transmitted to a third-party server. Configure a scrubbing hook before shipping.",
                priority: .low,
                category: .privacy,
                detect: checkCrashReporterDataLeak
            ),

            // ── iOS Configuration Weaknesses ────────────────────────────────
            APCheck(
                name: "File Sharing / NSFileProtectionNone in Plist",
                description: "`UIFileSharingEnabled = true` exposes the Documents directory via iTunes File Sharing. `NSFileProtectionNone` removes OS-level file encryption, making files readable on jailbroken devices or via forensic tools. Disable file sharing unless strictly required and use `NSFileProtectionComplete` for sensitive files.",
                priority: .high,
                category: .iosConfiguration,
                detect: { _, _ in [] },
                projectDetect: checkFileSharingEnabled,
                isProjectOnly: true
            ),
            APCheck(
                name: "NSFileProtectionNone in Swift Code",
                description: "Setting file protection to `.noProtection` / `FileProtectionType.none` disables the iOS Data Protection API, leaving files readable at rest even on a locked device. Use `.complete` or `.completeUnlessOpen` for all sensitive files.",
                priority: .high,
                category: .iosConfiguration,
                detect: checkFileProtectionNone
            ),

            // ── Logic & State-based Exploit Factors ────────────────────────
            APCheck(
                name: "Main Thread Blocking (Thread.sleep)",
                description: "Calling `Thread.sleep(forTimeInterval:)` on the main thread blocks all UI updates and user interaction — a reliable denial-of-service for the UI and a signal of incorrect async design. Use `Task.sleep`, `asyncAfter`, or actor-based scheduling instead.",
                priority: .medium,
                category: .logicState,
                detect: checkMainThreadBlocking
            ),
            APCheck(
                name: "Notification Observer Not Removed",
                description: "A file that registers `NotificationCenter` observers without a corresponding `removeObserver` call retains stale observers indefinitely. With the selector-based API this causes crashes after deallocation; block-based observers create ghost listeners. Always remove observers in `deinit` or use block-based observation with a stored token.",
                priority: .low,
                category: .logicState,
                detect: checkNotificationLeak
            ),

            // ── Low-level Binary Vulnerabilities ───────────────────────────
            APCheck(
                name: "Raw C Memory Operations (malloc / free / memcpy)",
                description: "Direct use of `malloc`, `calloc`, `realloc`, `free`, `memcpy`, `memmove`, or `memset` bypasses Swift's memory safety. Incorrect sizes, double-frees, or use-after-free are exploitable for heap corruption. Prefer Swift collections and `Data`; encapsulate all raw memory behind a reviewed abstraction boundary.",
                priority: .high,
                category: .lowLevelBinary,
                detect: checkRawCMemory
            ),
            APCheck(
                name: "Unsafe Buffer Pointer / baseAddress! Access",
                description: "`UnsafeBufferPointer`, `UnsafeMutableBufferPointer`, `UnsafeRawBufferPointer`, and `.baseAddress!` give direct pointer access to contiguous memory. Out-of-bounds indexing causes memory corruption; force-unwrapping `.baseAddress!` crashes on an empty buffer. Validate bounds before any pointer arithmetic.",
                priority: .medium,
                category: .lowLevelBinary,
                detect: checkUnsafeBuffer
            ),
            APCheck(
                name: "Objective-C Runtime Hazards (objc_msgSend / NSInvocation / performSelector)",
                description: "Direct `objc_msgSend` calls require a manually correct function-pointer cast — a mismatched return type or calling convention silently corrupts registers or the stack. `performSelector:` via `NSSelectorFromString` dispatches by runtime string with no compile-time signature verification. `NSInvocation` invoked with a mismatched method signature overwrites adjacent stack memory. Only applies to `.m` / `.mm` files.",
                priority: .high,
                category: .lowLevelBinary,
                detect: checkObjCRuntimeHazards
            ),
        ]
    }
}


// MARK: - Detection Checks

private extension SecurityAnalyzer {

    static func checkHardcodedSecret(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let skipWords = ["example", "test", "dummy", "fake", "sample", "placeholder", "your_", "xxx", "todo", "changeme", "insert", "enter"]
        guard let pattern = try? NSRegularExpression(
            pattern: #"(?i)(password|passwd|secret|apiKey|api_key|authKey|token)\s*=\s*"([^"]{8,})""#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let valRange = Range(match.range(at: 2), in: line) else { continue }
            let val = String(line[valRange]).lowercased()
            if !skipWords.contains(where: { val.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkUserDefaultsSensitive(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"UserDefaults\.standard\.set\([^,]+,\s*forKey:\s*"[^"]*(?i)(password|token|secret|key|auth|credential)[^"]*""#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    private static let securityPathTerms = [
        "SecureId", "Encrypt", "Decrypt", "Crypto", "Signing",
        "SecretChat", "Authentication", "SecretKey", "CryptoUtils",
    ]

    /// File name terms that indicate UI / rendering / animation code — skip deprecation noise.
    private static let uiFileNameTerms = [
        "View", "Node", "Animation", "Component", "Button", "Panel",
    ]
    /// Variable/property names that indicate an arc4random value feeds a visual/animation property.
    private static let animLineTerms = [
        "degrees", "velocity", "lifetime", "startAngle", "randAngle",
        ".seed =", "beginTime",
    ]

    static func checkInsecureRandomCrypto(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard securityPathTerms.contains(where: { filePath.contains($0) }) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains("arc4random()") || code.contains("arc4random_uniform(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkInsecureRandomUI(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if securityPathTerms.contains(where: { filePath.contains($0) }) { return [] }
        // Skip files that are clearly UI/rendering/animation by their filename
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        if uiFileNameTerms.contains(where: { fileName.contains($0) }) { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            guard code.contains("arc4random()") || code.contains("arc4random_uniform(") else { continue }
            // Skip lines where the random value feeds a visual/animation property
            if animLineTerms.contains(where: { line.contains($0) }) { continue }
            out.append(viol(filePath, i, lines))
            if out.count >= maxViolations { break }
        }
        return out
    }

    static func checkForceUnwrap(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        guard let unwrapPattern = try? NSRegularExpression(
            pattern: #"[a-zA-Z0-9_\])]!(?!=)(?![a-zA-Z_(])"#
        ),
        let tryBangPattern = try? NSRegularExpression(
            pattern: #"\btry!\s"#
        ) else { return [] }
        var tryBangs: [APViolation] = []
        var others: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isComment(line) { continue }
            if trimmed.contains("@IBOutlet") || trimmed.contains("@IBAction") { continue }
            let code = stripStrings(line)
            let range = NSRange(code.startIndex..., in: code)
            if tryBangPattern.firstMatch(in: code, range: range) != nil {
                tryBangs.append(viol(filePath, i, lines))
            } else if unwrapPattern.firstMatch(in: code, range: range) != nil {
                others.append(viol(filePath, i, lines))
            }
            if tryBangs.count + others.count >= maxViolations { break }
        }
        return Array((tryBangs + others).prefix(maxViolations))
    }

    static func checkForceCast(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains(" as!") || code.contains("\tas!") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkDispatchMainSync(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            guard code.contains("DispatchQueue.main.sync") || code.contains(".main.sync") else { continue }
            let context = i > 0 ? stripStrings(lines[i - 1]) + code : code
            if context.contains("!Thread.isMainThread") { continue }
            out.append(viol(filePath, i, lines))
            if out.count >= maxViolations { break }
        }
        return out
    }

    static func checkImplicitlyUnwrappedOptionals(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:var|let)\s+\w+\s*:\s*[\w<>\[\]]+!"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if line.contains("@IBOutlet") || line.contains("@IBAction") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkDeprecatedOpenURL(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if stripStrings(line).contains("openURL(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

}

// MARK: - New Security Detection Checks (Phase 2)

private extension SecurityAnalyzer {

    // MARK: Network Security — WebView JS Injection

    static func checkWebViewJSInjection(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let dangerousConfig = ["allowFileAccessFromFileURLs", "allowUniversalAccessFromFileURLs",
                               "javaScriptEnabled = true",
                               "allowContentJavaScript = true",
                               "isFraudulentWebsiteWarningEnabled = false"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            // evaluateJavaScript with string interpolation — check raw line for the \( escape sequence
            if line.contains("evaluateJavaScript(") && line.contains("\\(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
                continue
            }
            // Dangerous WKWebView / UIWebView configuration flags
            let code = stripStrings(line)
            if dangerousConfig.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Authentication — Biometric Without Keychain Binding

    static func checkBiometricWithoutKeychain(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let hasEval = lines.contains { !isComment($0) && stripStrings($0).contains("evaluatePolicy(") }
        guard hasEval else { return [] }
        // If the file also binds the result to a keychain item the check is considered safe
        let hasSEBinding = lines.contains {
            let c = stripStrings($0)
            return c.contains("SecAccessControlCreateWithFlags") ||
                   c.contains(".biometryCurrentSet") ||
                   c.contains(".userPresence") ||
                   c.contains("kSecAttrAccessControl")
        }
        guard !hasSEBinding else { return [] }
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if stripStrings(line).contains("evaluatePolicy(") {
                return [viol(filePath, i, lines)]
            }
        }
        return []
    }

    // MARK: I/O Validation — SQL Injection

    static func checkSQLInjection(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let sqlKeywords = ["SELECT ", "INSERT INTO", "UPDATE ", "DELETE FROM",
                           "DROP TABLE", "CREATE TABLE", "WHERE ", "FROM "]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            // String interpolation inside a SQL-looking string literal
            guard line.contains("\\(") else { continue }
            let upper = line.uppercased()
            if sqlKeywords.contains(where: { upper.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: I/O Validation — Insecure Deserialization

    static func checkInsecureDeserialization(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let insecureForms = [
            "NSKeyedUnarchiver.unarchiveObject(with:",
            "NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(",
            "requiringSecureCoding: false",
        ]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if insecureForms.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }
}

// MARK: - New Category Detection Checks

private extension SecurityAnalyzer {

    // MARK: Insecure Data Storage

    static func checkSensitivePrint(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let keywords = ["password", "passwd", "token", "secret", "apikey", "api_key",
                        "credential", "auth", "private_key", "privatekey"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let lower = line.lowercased()
            guard lower.contains("print(") || lower.contains("debugprint(") || lower.contains("nslog(") else { continue }
            if keywords.contains(where: { lower.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Crash Factors

    static func checkFatalError(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains("fatalError(") || code.contains("preconditionFailure(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Unsafe & Deprecated

    static func checkDangerousCFunctions(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let funcs = ["gets(", "sprintf(", "vsprintf(", "strcpy(", "strncpy(",
                     "strcat(", "strncat(", "scanf(", "sscanf(", "getwd("]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if funcs.contains(where: { containsCall(code, $0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkWeakCryptoConstants(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let weak = ["kCCAlgorithmDES", "kCCAlgorithm3DES", "kCCAlgorithmRC2",
                    "kCCAlgorithmRC4", "kCCAlgorithmCAST"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if weak.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Supply Chain

    static func checkHTTPPackageSource(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard filePath.hasSuffix("Package.swift") else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let stripped = stripLineComment(line)
            if stripped.contains(".package(url:") && stripped.contains("\"http://") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkFloatingDependency(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard filePath.hasSuffix("Package.swift") else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains(".branch(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Memory Corruption

    static func checkUnsafePointers(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["UnsafePointer<", "UnsafeMutablePointer<", "UnsafeRawPointer",
                        "UnsafeMutableRawPointer", "withUnsafeBytes {", "withUnsafeMutableBytes {",
                        "withUnsafePointer(", "withUnsafeMutablePointer("]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkManualMemory(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["Unmanaged<", ".takeRetainedValue()", ".takeUnretainedValue()",
                        ".passRetained(", ".passUnretained(", "Int(bitPattern:", "UInt(bitPattern:"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Cryptography

    static func checkWeakHash(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["CC_MD5(", "CC_MD5_Init", "CC_SHA1(", "CC_SHA1_Init",
                        "Insecure.MD5", "Insecure.SHA1", "HashAlgorithm.md5", ".md5.rawValue"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkECBMode(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains("kCCOptionECBMode") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkHardcodedIV(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let re = try? NSRegularExpression(
            pattern: #"(?i)\b(iv|nonce|initialVector|initializationVector)\s*[=:]\s*[\[\"]"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            let range = NSRange(code.startIndex..., in: code)
            if re.firstMatch(in: code, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Network Security

    static func checkHTTPURL(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let stripped = stripLineComment(line)
            guard stripped.contains("\"http://") else { continue }
            let lower = stripped.lowercased()
            if lower.contains("localhost") || lower.contains("127.0.0.1") || lower.contains("10.0.") { continue }
            out.append(viol(filePath, i, lines))
            if out.count >= maxViolations { break }
        }
        return out
    }

    static func checkCertValidationBypass(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["allowsAnyHTTPSCertificate",
                        "validatesDomainName = false",
                        "kCFStreamSSLValidatesCertificateChain, false",
                        ".useCredential, URLCredential(trust:"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkATSDisabled(_ repoPath: String) -> [APViolation] {
        var out: [APViolation] = []
        guard let enumerator = FileManager.default.enumerator(atPath: repoPath) else { return out }
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".plist") else { continue }
            if rel.lowercased().contains("test") { continue }
            let full = "\(repoPath)/\(rel)"
            guard let content = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            guard content.contains("NSAllowsArbitraryLoads") else { continue }
            let lines = content.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                guard line.contains("NSAllowsArbitraryLoads") else { continue }
                let window = lines[i ..< min(i + 3, lines.count)].joined(separator: " ")
                if window.contains("<true/>") {
                    out.append(APViolation(file: rel, fullPath: full, line: i + 1, snippet: snippet(line)))
                    break
                }
            }
        }
        return out
    }

    // MARK: Authentication

    static func checkKeychainAccessible(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["kSecAttrAccessibleAlways", "kSecAttrAccessibleAlwaysThisDeviceOnly"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkDeprecatedSecTrust(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains("SecTrustEvaluate(") && !code.contains("SecTrustEvaluateWithError(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Input/Output Validation

    static func checkPathTraversal(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.hasSuffix("Package.swift") { return [] }
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if line.contains("\"../") || line.contains("\"..\\") ||
               (line.contains("appendingPathComponent(") && line.contains("\"..\"")) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkShellInjection(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["/bin/sh", "/bin/bash", "/usr/bin/env",
                        "Process()", "NSTask()", "popen("]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Binary Protections

    static func checkDebugToolsInProduction(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let debugFrameworks = ["FLEX", "Reveal", "Chisel", "InjectionIII",
                               "Dotzu", "DBDebugToolkit", "GodEye", "Hyperion"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            guard line.contains("import ") else { continue }
            if debugFrameworks.contains(where: { line.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkJailbreakDetectionAbsent(_ repoPath: String) -> [APViolation] {
        let signals = ["cydia://", "Cydia.app", "sileo://", "isJailbroken",
                       "JailbreakDetect", "IOSSecuritySuite", "JailMonkey",
                       "/private/var/lib/apt", "/Applications/Cydia.app"]
        guard let enumerator = FileManager.default.enumerator(atPath: repoPath) else { return [] }
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".swift") || rel.hasSuffix(".m") else { continue }
            if rel.lowercased().contains("test") { continue }
            let full = "\(repoPath)/\(rel)"
            guard let content = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            if signals.contains(where: { content.contains($0) }) { return [] }
        }
        return [APViolation(file: "Project-wide", fullPath: repoPath, line: 0,
                            snippet: "No jailbreak detection patterns found in the codebase.")]
    }

    // MARK: Binary Protections — Anti-Tampering helpers

    private static func checkDebuggerAttached(_ filePath: String, _ lines: [String]) -> Bool {
        let patterns = ["PT_DENY_ATTACH", "ptrace(PT_DENY_ATTACH",
                        "proc_pid_debug", "kern.proc.pid",
                        "isDebuggerAttached", "AmIBeingDebugged"]
        return lines.contains { line in !isComment(line) && patterns.contains(where: { stripStrings(line).contains($0) }) }
    }

    private static func checkEmulatorOrSimulator(_ filePath: String, _ lines: [String]) -> Bool {
        let patterns = ["TARGET_OS_SIMULATOR", "TARGET_IPHONE_SIMULATOR",
                        "isSimulator", "isEmulator",
                        "SIMULATOR_DEVICE_NAME", "XCTestConfigurationFilePath"]
        return lines.contains { line in !isComment(line) && patterns.contains(where: { stripStrings(line).contains($0) }) }
    }

    private static func checkTweakInjectionSigns(_ filePath: String, _ lines: [String]) -> Bool {
        let patterns = ["DYLD_INSERT_LIBRARIES", "MSHookMessage", "MSHookFunction",
                        "fishhook", "/Library/MobileSubstrate/",
                        "/usr/lib/libsubstrate", "SubstrateLoader"]
        return lines.contains { line in !isComment(line) && patterns.contains(where: { stripStrings(line).contains($0) }) }
    }

    static func checkAntiTamperingAbsent(_ repoPath: String) -> [APViolation] {
        let allSignals = [
            "PT_DENY_ATTACH", "isDebuggerAttached", "AmIBeingDebugged",
            "proc_pid_debug", "kern.proc.pid",
            "TARGET_OS_SIMULATOR", "TARGET_IPHONE_SIMULATOR", "SIMULATOR_DEVICE_NAME",
            "DYLD_INSERT_LIBRARIES", "MSHookMessage", "MSHookFunction",
            "/Library/MobileSubstrate/", "SubstrateLoader", "fishhook",
        ]
        guard let enumerator = FileManager.default.enumerator(atPath: repoPath) else { return [] }
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".swift") || rel.hasSuffix(".m") || rel.hasSuffix(".mm") else { continue }
            if rel.lowercased().contains("test") { continue }
            let full = "\(repoPath)/\(rel)"
            guard let content = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            if allSignals.contains(where: { content.contains($0) }) { return [] }
        }
        return [APViolation(file: "Project-wide", fullPath: repoPath, line: 0,
                            snippet: "No runtime anti-tampering protections found (anti-debug, simulator guards, tweak injection detection).")]
    }

    // MARK: Privacy

    static func checkClipboardAccess(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if (code.contains("UIPasteboard.general") || code.contains("NSPasteboard.general")) &&
               (code.contains(".string") || code.contains(".strings") || code.contains(".data(")) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkDeviceFingerprint(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let patterns = [".advertisingIdentifier", "ASIdentifierManager",
                        ".identifierForVendor", "CTTelephonyNetworkInfo",
                        "currentRadioAccessTechnology"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: iOS Configuration

    static func checkFileSharingEnabled(_ repoPath: String) -> [APViolation] {
        var out: [APViolation] = []
        guard let enumerator = FileManager.default.enumerator(atPath: repoPath) else { return out }
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".plist") else { continue }
            if rel.lowercased().contains("test") { continue }
            let full = "\(repoPath)/\(rel)"
            guard let content = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                guard line.contains("UIFileSharingEnabled") || line.contains("NSFileProtectionNone") else { continue }
                let window = lines[i ..< min(i + 3, lines.count)].joined(separator: " ")
                if window.contains("<true/>") || line.contains("NSFileProtectionNone") {
                    out.append(APViolation(file: rel, fullPath: full, line: i + 1, snippet: snippet(line)))
                    break
                }
            }
        }
        return out
    }

    static func checkFileProtectionNone(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains(".noProtection") || code.contains("FileProtectionType.none") ||
               code.contains("NSFileProtectionNone") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Logic & State

    static func checkMainThreadBlocking(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains("Thread.sleep(forTimeInterval:") || code.contains("Thread.sleep(until:") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkNotificationLeak(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let hasAdd = lines.contains { !isComment($0) && stripStrings($0).contains("NotificationCenter.default.addObserver(") }
        guard hasAdd else { return [] }
        let hasRemove = lines.contains { !isComment($0) && stripStrings($0).contains("removeObserver(") }
        guard !hasRemove else { return [] }
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if stripStrings(line).contains("NotificationCenter.default.addObserver(") {
                return [viol(filePath, i, lines)]
            }
        }
        return []
    }

    // MARK: Low-level Binary

    static func checkObjCRuntimeHazards(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let ext = (filePath as NSString).pathExtension.lowercased()
        guard ext == "m" || ext == "mm" else { return [] }
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            // Direct objc_msgSend: caller must cast to exact function-pointer type; any mismatch is UB
            if containsCall(code, "objc_msgSend(") || containsCall(code, "objc_msgSendSuper(") ||
               containsCall(code, "objc_msgSend_stret(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { return out }
                continue
            }
            // performSelector: with NSSelectorFromString — no compile-time type check
            if code.contains("performSelector:") && code.contains("NSSelectorFromString(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { return out }
                continue
            }
            // NSInvocation: mismatched signature silently corrupts the call frame
            if code.contains("NSInvocation") &&
               (code.contains("invocationWithMethodSignature") ||
                code.contains("setSelector:") || code.contains("[inv invoke]") ||
                code.contains("invoke]")) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { return out }
            }
        }
        return out
    }

    static func checkRawCMemory(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let funcs = ["malloc(", "calloc(", "realloc(", "free(", "memcpy(", "memmove(", "memset(", "bzero("]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if funcs.contains(where: { containsCall(code, $0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkUnsafeBuffer(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let patterns = ["UnsafeBufferPointer<", "UnsafeMutableBufferPointer<",
                        "UnsafeRawBufferPointer", "UnsafeMutableRawBufferPointer",
                        ".baseAddress!", "assumingMemoryBound(to:"]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if patterns.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }
}

// MARK: - Phase 3 Detection Checks

private extension SecurityAnalyzer {

    // MARK: Insecure Data Storage

    // Per-file: CoreData + SQLite only. Realm is handled project-wide below.
    static func checkUnencryptedDatabaseLocal(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []

        // CoreData: addPersistentStore without file-protection options
        let hasCDEncryption = lines.contains {
            $0.contains("NSPersistentStoreFileProtectionKey") || $0.contains("NSFileProtectionComplete")
        }
        if !hasCDEncryption {
            for (i, line) in lines.enumerated() {
                if isComment(line) { continue }
                if stripStrings(line).contains("addPersistentStore") {
                    out.append(viol(filePath, i, lines))
                    if out.count >= maxViolations { return out }
                }
            }
        }

        // SQLite: sqlite3_open without SQLCipher's sqlite3_key
        let hasSQLiteCipher = lines.contains { $0.contains("sqlite3_key(") || $0.contains("SQLCipher") }
        if !hasSQLiteCipher {
            for (i, line) in lines.enumerated() {
                if isComment(line) { continue }
                let code = stripStrings(line)
                if containsCall(code, "sqlite3_open(") || containsCall(code, "sqlite3_open_v2(") {
                    out.append(viol(filePath, i, lines))
                    if out.count >= maxViolations { return out }
                }
            }
        }

        return out
    }

    // Project-wide: if encryptionKey appears anywhere in the codebase, Realm is considered safe.
    // This avoids false positives when encryption is configured once in a setup file.
    static func checkUnencryptedRealmProject(_ repoPath: String) -> [APViolation] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: repoPath) else { return [] }
        var swiftFiles: [String] = []
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".swift") else { continue }
            if rel.lowercased().contains("test") { continue }
            swiftFiles.append("\(repoPath)/\(rel)")
        }
        // If any file configures Realm encryptionKey, the whole project is covered
        let hasRealmEncryption = swiftFiles.contains { path in
            (try? String(contentsOfFile: path, encoding: .utf8))?.contains("encryptionKey") == true
        }
        guard !hasRealmEncryption else { return [] }
        // No encryption found — flag all Realm() call sites
        var out: [APViolation] = []
        for path in swiftFiles {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            let rel = String(path.dropFirst(repoPath.count + 1))
            for (i, line) in lines.enumerated() {
                if isComment(line) { continue }
                let code = stripStrings(line)
                if code.contains("Realm(") {
                    out.append(APViolation(file: rel, fullPath: path, line: i + 1, snippet: snippet(line)))
                    if out.count >= maxViolations { return out }
                }
            }
        }
        return out
    }

    static func checkSecretsInConfigFiles(_ repoPath: String) -> [APViolation] {
        let secretKeys = ["apikey", "api_key", "secret", "password", "passwd", "token",
                          "auth_key", "private_key", "client_secret", "access_key"]
        let skipWords = ["example", "test", "dummy", "fake", "sample", "placeholder",
                         "your_", "xxx", "todo", "changeme", "$(", "${"]
        var out: [APViolation] = []
        guard let enumerator = FileManager.default.enumerator(atPath: repoPath) else { return out }
        for case let rel as String in enumerator {
            let isXcconfig = rel.hasSuffix(".xcconfig")
            let isPlist = rel.hasSuffix(".plist")
            guard isXcconfig || isPlist else { continue }
            if rel.lowercased().contains("test") { continue }
            let full = "\(repoPath)/\(rel)"
            guard let content = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")

            if isXcconfig {
                for (i, line) in lines.enumerated() {
                    if isComment(line) { continue }
                    let lower = line.lowercased()
                    guard secretKeys.contains(where: { lower.contains($0) }) else { continue }
                    if skipWords.contains(where: { line.contains($0) }) { continue }
                    let parts = line.components(separatedBy: "=")
                    guard parts.count >= 2 else { continue }
                    let value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    if value.count >= 8 && !value.hasPrefix("$(") && !value.hasPrefix("${") {
                        out.append(APViolation(file: rel, fullPath: full, line: i + 1, snippet: snippet(line)))
                        if out.count >= maxViolations { break }
                    }
                }
            }

            if isPlist {
                var pendingSecretKey = false
                for (i, line) in lines.enumerated() {
                    if line.contains("<key>") {
                        let keyName = line.components(separatedBy: "<key>").last?
                            .components(separatedBy: "</key>").first?.lowercased() ?? ""
                        pendingSecretKey = secretKeys.contains(where: { keyName.contains($0) })
                    } else if pendingSecretKey && line.contains("<string>") {
                        let val = line.components(separatedBy: "<string>").last?
                            .components(separatedBy: "</string>").first ?? ""
                        if val.count >= 8 && !skipWords.contains(where: { val.contains($0) }) {
                            out.append(APViolation(file: rel, fullPath: full, line: i + 1, snippet: snippet(line)))
                        }
                        pendingSecretKey = false
                    } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        pendingSecretKey = false
                    }
                    if out.count >= maxViolations { break }
                }
            }
        }
        return out
    }

    static func checkSensitiveURLCaching(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            // URLCache with non-zero disk capacity
            if code.contains("URLCache(") && line.contains("diskCapacity:") {
                // Normalize whitespace so "diskCapacity:0" and "diskCapacity: 0" both match
                let normalized = line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
                if !normalized.contains("diskcapacity: 0") {
                    out.append(viol(filePath, i, lines))
                    if out.count >= maxViolations { break }
                    continue
                }
            }
            // WKWebsiteDataStore.default() persists cookies/auth tokens
            if code.contains("WKWebsiteDataStore.default()") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
                continue
            }
            // URLSessionConfiguration using the shared disk-backed cache
            if code.contains("urlCache") &&
               (code.contains("= URLCache.shared") || code.contains("= .shared")) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Cryptography

    static func checkHardcodedEncryptionKey(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        // let/var with any key-concept name assigned a string literal ≥ 8 chars
        guard let keyVarPattern = try? NSRegularExpression(
            pattern: #"(?i)(?:let|var)\s+\w*(?:key|secret|cipher|encrypt|credential|crypto|symmetric)\w*\s*[=:]"#
        ) else { return [] }
        guard let literalPattern = try? NSRegularExpression(
            pattern: #""[^"]{8,}""#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let lineRange = NSRange(line.startIndex..., in: line)
            // 1. Key-named variable assigned a string literal
            if keyVarPattern.firstMatch(in: line, range: lineRange) != nil &&
               literalPattern.firstMatch(in: line, range: lineRange) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
                continue
            }
            let code = stripStrings(line)
            // 2. SymmetricKey(data:) or SecKeyCreateWithData fed a literal — most common CryptoKit pattern
            if (code.contains("SymmetricKey(data:") || code.contains("SecKeyCreateWithData")) &&
               literalPattern.firstMatch(in: line, range: lineRange) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
                continue
            }
            // 3. [UInt8] array assigned to a key-named variable
            //    \bkey catches keyBytes/keyData but not monkey (no word boundary before k in "monkey")
            if code.contains("[UInt8]") && code.contains("= [") &&
               (code.contains("Key") || code.contains("Secret") || code.contains("Cipher") ||
                code.range(of: #"\bkey"#, options: .regularExpression) != nil) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkCBCWithoutMAC(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let hasCBC = lines.contains {
            let c = stripStrings($0)
            return !isComment($0) && (c.contains("kCCModeCBC") || c.contains(".cbc"))
        }
        guard hasCBC else { return [] }
        let hasMAC = lines.contains {
            let c = stripStrings($0)
            return c.contains("CCHmac") || c.contains("HMAC") ||
                   c.contains("kCCModeGCM") || c.contains(".gcm") ||
                   c.contains("AES.GCM") || c.contains("ChaChaPoly")
        }
        guard !hasMAC else { return [] }
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains("kCCModeCBC") || code.contains(".cbc") {
                return [viol(filePath, i, lines)]
            }
        }
        return []
    }

    static func checkPBKDF2Iterations(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        guard let pattern = try? NSRegularExpression(
            pattern: #"CCKeyDerivationPBKDF\s*\([^,]+,[^,]+,[^,]+,[^,]+,[^,]+,\s*(\d+)"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            guard line.contains("CCKeyDerivationPBKDF") else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = pattern.firstMatch(in: line, range: range),
               let roundsRange = Range(match.range(at: 1), in: line),
               let rounds = Int(line[roundsRange]), rounds < 10_000 {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Network Security

    static func checkHardcodedAuthHeader(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let stripped = stripLineComment(line)
            // setValue/addValue with a literal Bearer/Basic token
            let hasAuthField = stripped.contains("\"Authorization\"") ||
                               stripped.contains("forHTTPHeaderField: \"Authorization\"")
            let hasLiteralToken = stripped.contains("\"Bearer ") || stripped.contains("\"Basic ") ||
                                  stripped.contains("\"Token ")
            if hasAuthField && hasLiteralToken {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkURLSessionArbitraryLoads(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if code.contains(".allowsArbitraryLoads = true") || code.contains("allowsArbitraryLoads: true") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Network — URLSession delegate challenge bypass

    static func checkURLSessionDelegateBypass(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var inMethod = false
        var braceDepth = 0
        var bodyEntered = false
        var hasValidation = false
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if !inMethod {
                if code.contains("didReceive challenge:") {
                    inMethod = true; braceDepth = 0; bodyEntered = false; hasValidation = false
                } else { continue }
            }
            for ch in code {
                if ch == "{" { braceDepth += 1; bodyEntered = true }
                else if ch == "}" { braceDepth -= 1 }
            }
            if code.contains("SecTrustEvaluateWithError") ||
               code.contains("SecTrustCopyExceptions") ||
               code.contains("SecPolicyCreateSSL") ||
               code.contains("SecTrustSetPolicies") {
                hasValidation = true
            }
            if !hasValidation && code.contains(".useCredential") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { return out }
            }
            if bodyEntered && braceDepth <= 0 { inMethod = false }
        }
        return out
    }

    // MARK: Unsafe/Deprecated — UIWebView

    static func checkUIWebView(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if stripStrings(line).contains("UIWebView") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    // MARK: Privacy — Info.plist permission vs API mismatch (project-wide)

    static func checkPermissionMismatch(_ repoPath: String) -> [APViolation] {
        let permissionMap: [(key: String, apis: [String], label: String)] = [
            ("NSMicrophoneUsageDescription",  ["AVAudioSession", "AVAudioRecorder", "AVCaptureDevice"], "Microphone"),
            ("NSCameraUsageDescription",       ["AVCaptureDevice", "AVCaptureSession", "UIImagePickerController", "PHPickerViewController"], "Camera"),
            ("NSLocationWhenInUseUsageDescription", ["CLLocationManager", "startUpdatingLocation", "requestWhenInUseAuthorization"], "Location"),
            ("NSLocationAlwaysUsageDescription",    ["CLLocationManager", "requestAlwaysAuthorization", "startMonitoringSignificantLocationChanges"], "Location Always"),
            ("NSContactsUsageDescription",     ["CNContactStore", "CNContact"], "Contacts"),
            ("NSPhotoLibraryUsageDescription", ["PHPhotoLibrary", "PHAsset", "PHImageManager"], "Photo Library"),
            ("NSBluetoothAlwaysUsageDescription", ["CBCentralManager", "CBPeripheralManager"], "Bluetooth"),
            ("NSFaceIDUsageDescription",       ["LAContext", "evaluatePolicy"], "Face ID"),
            ("NSCalendarsUsageDescription",    ["EKEventStore", "EKCalendar"], "Calendars"),
            ("NSRemindersUsageDescription",    ["EKReminder", "EKEventStore"], "Reminders"),
        ]
        guard let enumerator = FileManager.default.enumerator(atPath: repoPath) else { return [] }
        var plists: [(String, String)] = []
        var corpus = ""
        for case let rel as String in enumerator {
            guard !rel.lowercased().contains("test") else { continue }
            let full = "\(repoPath)/\(rel)"
            if rel.hasSuffix("Info.plist") {
                if let c = try? String(contentsOfFile: full, encoding: .utf8) { plists.append((rel, c)) }
            } else if rel.hasSuffix(".swift") || rel.hasSuffix(".m") {
                if let c = try? String(contentsOfFile: full, encoding: .utf8) { corpus += c }
            }
        }
        guard !plists.isEmpty else { return [] }
        var out: [APViolation] = []
        for (rel, plist) in plists {
            let full = "\(repoPath)/\(rel)"
            let lines = plist.components(separatedBy: "\n")
            for perm in permissionMap {
                guard plist.contains(perm.key) else { continue }
                guard !perm.apis.contains(where: { corpus.contains($0) }) else { continue }
                for (i, line) in lines.enumerated() where line.contains(perm.key) {
                    out.append(APViolation(file: rel, fullPath: full, line: i + 1,
                        snippet: "\(perm.key) declared but no \(perm.label) API usage found"))
                    break
                }
                if out.count >= maxViolations { return out }
            }
        }
        return out
    }

    // MARK: Privacy — Crash reporter without data-scrubbing config

    static func checkCrashReporterDataLeak(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let sdkInits = ["PLCrashReporter(", "Crashlytics.crashlytics()", "FirebaseCrashlytics.crashlytics()",
                        "SentrySDK.start(", "Bugsnag.start(", "BugsnagConfiguration("]
        let scrubbingHooks = ["beforeSend", "onBeforeSend", "eventProcessor", "beforeBreadcrumb",
                              "redactedKeys", "setUserIdentifier", "anonymize", "sanitize"]
        guard lines.contains(where: { l in
            !isComment(l) && sdkInits.contains(where: { stripStrings(l).contains($0) })
        }) else { return [] }
        guard !lines.contains(where: { l in
            !isComment(l) && scrubbingHooks.contains(where: { stripStrings(l).contains($0) })
        }) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            if sdkInits.contains(where: { code.contains($0) }) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }
}
