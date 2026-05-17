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
}

struct APCheck {
    let name: String
    let description: String
    let priority: APPriority
    let detect: (_ filePath: String, _ lines: [String]) -> [APViolation]
}

struct APResult {
    let check: APCheck
    let violations: [APViolation]
    var passed: Bool { violations.isEmpty }
}

// MARK: - Analyzer

struct AntipatternAnalyzer {
    static let maxViolations = 100

    static func run(files: [ParsedFile], repoPath: String = "") -> [APResult] {
        // Collect class names declared in the project — used by the inheritance check
        var projectClassNames = Set<String>()
        for file in files where file.filePath.hasSuffix(".swift") {
            for decl in file.declarations where decl.kind == .class {
                projectClassNames.insert(decl.name)
            }
        }

        let checks = allChecks(projectClasses: projectClassNames)
        let swiftFiles = files.filter { $0.filePath.hasSuffix(".swift") }

        // Per-check violation buckets; filled concurrently, merged under a lock
        var violationsPerCheck: [[APViolation]] = Array(repeating: [], count: checks.count)
        let lock = NSLock()

        // Parallel file I/O: each iteration reads one file and runs all checks on it
        DispatchQueue.concurrentPerform(iterations: swiftFiles.count) { idx in
            let filePath = swiftFiles[idx].filePath
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
            let lines = content.components(separatedBy: "\n")

            var local: [(Int, [APViolation])] = []
            for i in checks.indices {
                let vs = checks[i].detect(filePath, lines)
                if !vs.isEmpty { local.append((i, vs)) }
            }
            guard !local.isEmpty else { return }

            lock.lock()
            for (i, vs) in local {
                let have = violationsPerCheck[i].count
                if have < maxViolations {
                    violationsPerCheck[i].append(contentsOf: vs.prefix(maxViolations - have))
                }
            }
            lock.unlock()
        }

        var results = checks.indices.map { i in
            APResult(check: checks[i], violations: violationsPerCheck[i])
        }

        // Enrich violations with blame authors (sequential — git blame is already fast per-file)
        if !repoPath.isEmpty {
            let git = GitAnalyzer(repoPath: repoPath, commitLimit: 0)
            var blameCache: [String: [Int: String]] = [:]
            results = results.map { result in
                let enriched = result.violations.map { v -> APViolation in
                    if blameCache[v.fullPath] == nil {
                        blameCache[v.fullPath] = git.blameLines(filePath: v.fullPath)
                    }
                    var updated = v
                    updated.author = blameCache[v.fullPath]?[v.line]
                    return updated
                }
                return APResult(check: result.check, violations: enriched)
            }
        }

        return results
    }

    // MARK: - Path / Snippet Helpers

    static func displayPath(_ filePath: String) -> String {
        let parts = filePath.components(separatedBy: "/")
        return parts.count > 3 ? parts.suffix(3).joined(separator: "/") : parts.joined(separator: "/")
    }

    static func snippet(_ line: String) -> String {
        let s = line.trimmingCharacters(in: .whitespaces)
        return s.count > 100 ? String(s.prefix(100)) + "…" : s
    }

    static func viol(_ filePath: String, _ lineIdx: Int, _ lines: [String]) -> APViolation {
        APViolation(file: displayPath(filePath), fullPath: filePath, line: lineIdx + 1, snippet: snippet(lines[lineIdx]))
    }
}

// MARK: - Check Registry

private extension AntipatternAnalyzer {
    static func allChecks(projectClasses: Set<String> = []) -> [APCheck] {
        [
            // ─── HIGH ───────────────────────────────────────────────────────
            APCheck(
                name: "Hardcoded Secrets",
                description: "Hardcoding API keys, passwords, or tokens embeds credentials into version history permanently. Load secrets from environment variables, the Keychain, or a secure configuration system at runtime. Any credential found here must be rotated immediately — consider it compromised.",
                priority: .high,
                detect: checkHardcodedSecret
            ),
            APCheck(
                name: "Use Cryptographically Secure Randomness",
                description: "`arc4random()` and `arc4random_uniform()` are deprecated and cryptographically weak. For security-sensitive values — tokens, keys, nonces, session IDs — use `SecRandomCopyBytes` or `CryptoKit`. For non-security uses, prefer `Int.random(in:)` from Swift's standard library.",
                priority: .high,
                detect: checkInsecureRandom
            ),
            APCheck(
                name: "UserDefaults Only for Non-Sensitive Data",
                description: "UserDefaults is stored as a plain-text plist, unprotected and readable by any process with sandbox access. Never store passwords, tokens, or personal data there. Use the Keychain for secrets — it is encrypted and access-controlled by the OS.",
                priority: .high,
                detect: checkUserDefaultsSensitive
            ),
            APCheck(
                name: "Never Force Unwrap Optionals (!)",
                description: "Force-unwrapping a nil optional crashes the app with a fatal error, producing a poor user experience and no recovery path. Always use `if let`, `guard let`, `map`, or the nil-coalescing operator `??` to safely handle the absent case.",
                priority: .high,
                detect: checkForceUnwrap
            ),
            APCheck(
                name: "Never Force Try (try!)",
                description: "Ignoring errors with `try!` turns any thrown error into an unrecoverable crash. Wrap throwing calls in `do { try … } catch { … }` and handle the error gracefully, or use `try?` with proper nil handling if failure is acceptable.",
                priority: .high,
                detect: checkForceTry
            ),
            APCheck(
                name: "Avoid Force Casts (as!)",
                description: "A forced downcast that fails crashes the app. Use the conditional form `as?` combined with `if let` or `guard let` to safely attempt the cast and handle the failure case instead of aborting.",
                priority: .high,
                detect: checkForceCast
            ),
            APCheck(
                name: "Avoid Retain Cycles in Closures",
                description: "In escaping closures that capture `self`, a strong reference cycle prevents deallocation and leaks memory. Always use a capture list `[weak self]` (or `[unowned self]` only when self is guaranteed to outlive the closure) and unwrap with `guard let self` inside.",
                priority: .high,
                detect: checkRetainCycles
            ),

            // ─── MEDIUM ─────────────────────────────────────────────────────
            APCheck(
                name: "Mark Classes final Unless Subclassing Is Designed",
                description: "`final` disables dynamic dispatch, enabling the compiler to devirtualize and inline calls. It also signals that the class is not designed for inheritance. Add `final` unless subclassing is part of the deliberate public API or you are inheriting from a framework class.",
                priority: .medium,
                detect: checkMissingFinal
            ),
            APCheck(
                name: "Make @IBOutlet Properties private",
                description: "IBOutlets are an implementation detail of the view controller. Exposing them publicly breaks encapsulation and lets callers mutate UI state from outside the controller. Mark all IBOutlets `private` — or at worst `fileprivate` for storyboard-segue access within the same file.",
                priority: .medium,
                detect: checkIBOutletPrivate
            ),
            APCheck(
                name: "Prefer Protocols Over Class Inheritance",
                description: "Deep class hierarchies create tight coupling, make testing harder, and resist change. Favor protocol-oriented design: compose behaviors through protocol conformances and extensions. Reserve class inheritance for cases where the parent is a framework type and subclassing is the documented integration point.",
                priority: .medium,
                detect: { filePath, lines in checkProtocolsOverInheritance(filePath, lines, projectClasses: projectClasses) }
            ),
            APCheck(
                name: "Prefer Structs Over Classes for Value Types",
                description: "Structs provide value semantics — each copy is independent — eliminating shared-mutable-state bugs. They are also more stack-friendly. Use a class only when you need reference semantics, identity, or Objective-C interop. Models and data containers are almost always better as structs.",
                priority: .medium,
                detect: checkStructsOverClasses
            ),
            APCheck(
                name: "Always Handle Errors; Avoid Empty catch Blocks",
                description: "An empty `catch {}` silently swallows failures, making debugging extremely difficult. At minimum, log the error. Better still, propagate it to a layer that can present feedback to the user or trigger a retry. Never leave a catch block completely empty.",
                priority: .medium,
                detect: checkEmptyCatch
            ),
            APCheck(
                name: "Avoid Implicitly Unwrapped Optionals (IUOs)",
                description: "Implicitly unwrapped optionals (`Type!`) bypass optional safety: if nil when accessed, the app crashes. Use them only for IBOutlets and properties guaranteed to be set before first access (e.g., in `viewDidLoad`). For everything else, use a regular optional `?` and unwrap explicitly.",
                priority: .medium,
                detect: checkImplicitlyUnwrappedOptionals
            ),
            APCheck(
                name: "Add deinit to Classes That Register Observers",
                description: "A `deinit` that removes notification observers, invalidates timers, or releases resources prevents leaks and proves the class is being deallocated. Its absence in a class that calls `addObserver`, schedules timers, or holds external resources is a strong signal of a potential memory leak.",
                priority: .medium,
                detect: checkMissingDeinit
            ),

            // ─── LOW ────────────────────────────────────────────────────────
            APCheck(
                name: "Use toggle() for Booleans",
                description: "`flag.toggle()` is clearer, shorter, and expresses intent directly compared to `flag = !flag`. It also avoids the subtle bug of accidentally toggling the wrong variable.",
                priority: .low,
                detect: checkToggle
            ),
            APCheck(
                name: "No Redundant Optional Initialization",
                description: "Optional properties and variables are `nil` by default in Swift. Writing `var name: String? = nil` is redundant noise. Drop the `= nil` initializer — it adds visual clutter with no semantic benefit.",
                priority: .low,
                detect: checkRedundantNilInit
            ),
            APCheck(
                name: "Remove Unused Imports",
                description: "Leftover `import` statements add compilation overhead, clutter the file, and mislead readers about actual dependencies. Review and remove any framework import whose symbols are not referenced in the file.",
                priority: .low,
                detect: checkUnusedImports
            ),
            APCheck(
                name: "Prefer Explicit Type with .init() for Clarity",
                description: "Writing `let label: UILabel = .init()` over `let label = UILabel()` explicitly declares the type on the left-hand side and uses the concise `.init()` call on the right. This improves readability when the type is not obvious from context and helps the compiler in complex expressions.",
                priority: .low,
                detect: checkExplicitTypeInit
            ),
            APCheck(
                name: "Use guard for Early Exit to Reduce Nesting",
                description: "Deeply nested `if let` chains push the happy path inward, increasing cognitive load. Use `guard let` to bail out early and keep the successful condition at the base indentation level. This produces flatter, more readable functions.",
                priority: .low,
                detect: checkGuardEarlyExit
            ),
        ]
    }
}

// MARK: - HIGH Checks

private extension AntipatternAnalyzer {

    static func checkHardcodedSecret(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        let skipWords = ["example", "test", "dummy", "fake", "sample", "placeholder", "your_", "xxx", "todo", "changeme", "insert", "enter"]
        guard let pattern = try? NSRegularExpression(
            pattern: #"(?i)(password|passwd|secret|apiKey|api_key|authKey|token)\s*=\s*"([^"]{8,})""#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
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

    static func checkInsecureRandom(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            if line.contains("arc4random()") || line.contains("arc4random_uniform(") {
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
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkForceUnwrap(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        guard let pattern = try? NSRegularExpression(
            pattern: #"[a-zA-Z0-9_\])]!(?!=)(?![a-zA-Z_(])"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if trimmed.contains("@IBOutlet") || trimmed.contains("@IBAction") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkForceTry(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            if line.contains("try!") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkForceCast(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            if line.contains(" as!") || line.contains("\tas!") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkRetainCycles(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let closurePattern = try? NSRegularExpression(pattern: #"\)\s*\{(?!\s*\[(?:weak|unowned)\s)"#),
              let selfRefPattern = try? NSRegularExpression(pattern: #"\bself\."#) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if line.contains("[weak self]") || line.contains("[unowned self]") { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard closurePattern.firstMatch(in: line, range: range) != nil else { continue }
            var hasSelf = false
            var hasCapture = false
            for j in (i + 1)..<min(lines.count, i + 15) {
                let next = lines[j]
                if next.contains("[weak self]") || next.contains("[unowned self]") { hasCapture = true; break }
                let nr = NSRange(next.startIndex..., in: next)
                if selfRefPattern.firstMatch(in: next, range: nr) != nil { hasSelf = true }
            }
            if hasSelf && !hasCapture {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }
}

// MARK: - MEDIUM Checks

private extension AntipatternAnalyzer {

    static func checkMissingFinal(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?class\s+\w+"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            if line.contains("final ") || line.contains("open ") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkIBOutletPrivate(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"@IBOutlet\s+(?!private\s)(?!fileprivate\s)weak\s"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkProtocolsOverInheritance(_ filePath: String, _ lines: [String], projectClasses: Set<String>) -> [APViolation] {
        guard !projectClasses.isEmpty else { return [] }
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:final\s+)?(?:\w+\s+)*class\s+\w+\s*:\s*(\w+)"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let baseRange = Range(match.range(at: 1), in: line) else { continue }
            let base = String(line[baseRange])
            // Only flag when the parent class is defined within the project itself
            guard projectClasses.contains(base) else { continue }
            out.append(viol(filePath, i, lines))
            if out.count >= maxViolations { break }
        }
        return out
    }

    static func checkStructsOverClasses(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        // Classes with no parent and no protocol conformances are candidates for structs
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:final\s+)?(?:\w+\s+)?class\s+(\w+)\s*\{"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkEmptyCatch(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            // Single-line: } catch { } or catch { }
            if (trimmed.hasPrefix("} catch") || trimmed.hasPrefix("catch")) && trimmed.hasSuffix("{") {
                // Check next line for immediate }
                if i + 1 < lines.count {
                    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if next == "}" || next == "} " {
                        out.append(viol(filePath, i, lines))
                        if out.count >= maxViolations { break }
                    }
                }
            }
        }
        return out
    }

    static func checkImplicitlyUnwrappedOptionals(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:var|let)\s+\w+\s*:\s*[\w<>\[\]]+!"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if line.contains("@IBOutlet") || line.contains("@IBAction") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkMissingDeinit(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let content = lines.joined(separator: "\n")
        let hasObserver = content.contains("addObserver(") || content.contains("NotificationCenter") ||
                          content.contains("addTarget(") || content.contains("Timer.scheduledTimer")
        guard hasObserver && !content.contains("deinit {") else { return [] }
        guard lines.contains(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && $0.contains("class ") && $0.contains("{")
        }) else { return [] }
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.hasPrefix("//") && line.contains("class ") && line.contains("{") {
                return [viol(filePath, i, lines)]
            }
        }
        return []
    }
}

// MARK: - LOW Checks

private extension AntipatternAnalyzer {

    static func checkToggle(_ filePath: String, _ lines: [String]) -> [APViolation] {
        // Anchored: must be a standalone statement, not inside a string or comment
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:self\.)?(\w[\w.]*)\s*=\s*!\s*\1\s*$"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkRedundantNilInit(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"\bvar\s+\w+\s*:\s*[\w<>\[\]]+\?\s*=\s*nil\b"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkUnusedImports(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let importRe = try? NSRegularExpression(pattern: #"^import\s+(\w+)"#) else { return [] }
        let alwaysUsed: Set<String> = ["Foundation", "UIKit", "AppKit", "SwiftUI", "Swift"]
        let content = lines.joined(separator: "\n")
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = importRe.firstMatch(in: line, range: range),
                  let modRange = Range(match.range(at: 1), in: line) else { continue }
            let mod = String(line[modRange])
            if alwaysUsed.contains(mod) { continue }
            // Heuristic: if the module name appears only once (the import line itself), it's likely unused
            if content.components(separatedBy: mod).count <= 2 {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkExplicitTypeInit(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let uiTypes: Set<String> = [
            "UILabel", "UIButton", "UIView", "UIImageView", "UITextField",
            "UITextView", "UIScrollView", "UIStackView", "UITableView",
            "UICollectionView", "UIActivityIndicatorView", "DispatchQueue",
            "OperationQueue", "DateFormatter", "NumberFormatter",
            "JSONDecoder", "JSONEncoder", "URLSession", "URLComponents",
        ]
        guard let pattern = try? NSRegularExpression(
            pattern: #"(?:let|var)\s+\w+\s*=\s*([A-Z]\w+)\(\)"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let typeRange = Range(match.range(at: 1), in: line) else { continue }
            if uiTypes.contains(String(line[typeRange])) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkGuardEarlyExit(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        var braceDepth = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            braceDepth += line.components(separatedBy: "{").count - 1
            braceDepth -= line.components(separatedBy: "}").count - 1
            braceDepth = max(0, braceDepth)
            // Flag `if let` / `if var` at nesting depth >= 3 (inside a function, inside another if/for)
            if braceDepth >= 3 &&
               (trimmed.hasPrefix("if let ") || trimmed.hasPrefix("if var ") || trimmed.contains(", let ")) {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }
}
