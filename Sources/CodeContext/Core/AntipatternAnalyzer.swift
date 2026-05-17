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
                name: "Never Force Unwrap or Force Try (! / try!)",
                description: "Force-unwrapping a nil optional (`x!`) and force-try (`try!`) both crash the app with a fatal error on failure, producing a poor user experience and no recovery path. Use `if let`, `guard let`, `??`, or `try?`/`do-catch` to handle the absent or error case safely. `try!` violations are listed first.",
                priority: .high,
                detect: checkForceUnwrap
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
            APCheck(
                name: "Avoid DispatchQueue.main.sync",
                description: "Calling `DispatchQueue.main.sync` from the main thread causes a guaranteed deadlock. Even guarding with `Thread.isMainThread` is fragile — use `DispatchQueue.main.async` instead, or restructure to avoid dispatching to main from main.",
                priority: .high,
                detect: checkDispatchMainSync
            ),
            APCheck(
                name: "Avoid Blocking the Main Thread",
                description: "Synchronous file and network I/O on the main thread freezes the UI until the operation completes. Move `String(contentsOfFile:)`, `Data(contentsOf:)`, and similar blocking calls to a background queue using `DispatchQueue.global()` or Swift Concurrency.",
                priority: .high,
                detect: checkBlockingMainThread
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
            APCheck(
                name: "Prefer Swift Native Types Over ObjC Bridges",
                description: "`NSDate`, `NSURL`, and `NSData` are Objective-C bridge types. In Swift code prefer `Date`, `URL`, and `Data` — they are lighter, work seamlessly with Swift generics and Codable, and avoid unnecessary bridging overhead.",
                priority: .medium,
                detect: checkNSObjCBridgeTypes
            ),
            APCheck(
                name: "Selector Without @objc",
                description: "A method referenced by `#selector(...)` must be visible to the Objective-C runtime. Without `@objc` (or `@IBAction`/`@IBOutlet`) the code compiles but fails silently at runtime. Add `@objc` to any method passed to `#selector`.",
                priority: .medium,
                detect: checkSelectorWithoutObjc
            ),
            APCheck(
                name: "Replace Deprecated openURL",
                description: "`UIApplication.shared.openURL(_:)` was deprecated in iOS 10. Use `open(_:options:completionHandler:)` instead — it supports the system to handle the transition and provides a completion callback.",
                priority: .medium,
                detect: checkDeprecatedOpenURL
            ),
            APCheck(
                name: "Missing super Call in Overridden Lifecycle Methods",
                description: "Overriding `viewDidLoad`, `viewWillAppear`, `viewDidAppear`, and similar UIKit lifecycle methods without calling `super` skips framework setup and can cause subtle, hard-to-diagnose bugs. Always call the `super` implementation.",
                priority: .medium,
                detect: checkMissingSuperCall
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
                name: "Use os_log Instead of NSLog",
                description: "`NSLog` writes synchronously to stderr and is significantly slower than the unified logging system. Use `os_log` or `Logger` (iOS 14+) for structured, performant logging that integrates with Console.app and Instruments.",
                priority: .low,
                detect: checkNSLogUsage
            ),
            APCheck(
                name: "Avoid #imageLiteral",
                description: "`#imageLiteral` embeds image references at compile time, inflates binary size, slows compilation, and makes code reviews harder. Load images at runtime with `UIImage(named:)` or SwiftUI's `Image(_:)` instead.",
                priority: .low,
                detect: checkImageLiteral
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

    static func checkInsecureRandom(_ filePath: String, _ lines: [String]) -> [APViolation] {
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

    static func checkRetainCycles(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let closurePattern = try? NSRegularExpression(pattern: #"\)\s*\{(?!\s*\[(?:weak|unowned)\s)"#),
              let selfRefPattern = try? NSRegularExpression(pattern: #"\bself\."#) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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
            if isComment(line) { continue }
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

}

// MARK: - New HIGH Checks

private extension AntipatternAnalyzer {

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

    static func checkBlockingMainThread(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let blockingCalls = [
            "String(contentsOfFile:", "String(contentsOf:",
            "Data(contentsOf:", "NSData(contentsOf:", "NSData(contentsOfFile:",
            "FileManager.default.contents(atPath:",
            "sendSynchronousRequest",
        ]
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let code = stripStrings(line)
            guard blockingCalls.contains(where: { code.contains($0) }) else { continue }
            let window = lines[max(0, i - 3)..<min(lines.count, i + 1)].map { stripStrings($0) }.joined()
            if window.contains("global()") || window.contains("background") ||
               window.contains("async {") || window.contains("Task {") ||
               window.contains("DispatchQueue.global") { continue }
            out.append(viol(filePath, i, lines))
            if out.count >= maxViolations { break }
        }
        return out
    }
}

// MARK: - New MEDIUM Checks

private extension AntipatternAnalyzer {

    static func checkNSObjCBridgeTypes(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let bridgeTypes = ["NSDate", "NSURL", "NSData"]
        guard let pattern = try? NSRegularExpression(
            pattern: #":\s*(NSDate|NSURL|NSData)\b"#
        ) else { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isComment(line) { continue }
            // Skip ObjC files
            if filePath.hasSuffix(".m") || filePath.hasSuffix(".h") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if pattern.firstMatch(in: line, range: range) != nil {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        _ = bridgeTypes
        return out
    }

    static func checkSelectorWithoutObjc(_ filePath: String, _ lines: [String]) -> [APViolation] {
        guard let selectorRe = try? NSRegularExpression(pattern: #"#selector\(\s*(\w+)"#) else { return [] }
        let content = lines.joined(separator: "\n")
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isComment(line) { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = selectorRe.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line) else { continue }
            let methodName = String(line[nameRange])
            // Search the file for the method declaration and check for @objc
            let declPattern = "func \(NSRegularExpression.escapedPattern(for: methodName))\\b"
            guard let declRe = try? NSRegularExpression(pattern: declPattern) else { continue }
            let fullRange = NSRange(content.startIndex..., in: content)
            guard let declMatch = declRe.firstMatch(in: content, range: fullRange),
                  let declSwiftRange = Range(declMatch.range, in: content) else { continue }
            // Check a small window before the declaration for @objc / @IBAction / @IBOutlet
            let start = content.index(declSwiftRange.lowerBound, offsetBy: -120, limitedBy: content.startIndex) ?? content.startIndex
            let window = String(content[start..<declSwiftRange.lowerBound])
            if window.contains("@objc") || window.contains("@IBAction") || window.contains("@IBOutlet") { continue }
            out.append(viol(filePath, i, lines))
            if out.count >= maxViolations { break }
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

    static func checkMissingSuperCall(_ filePath: String, _ lines: [String]) -> [APViolation] {
        let lifecycleMethods: Set<String> = [
            "viewDidLoad", "viewWillAppear", "viewDidAppear",
            "viewWillDisappear", "viewDidDisappear", "viewWillLayoutSubviews",
            "viewDidLayoutSubviews", "awakeFromNib", "prepareForReuse",
        ]
        guard let overrideRe = try? NSRegularExpression(
            pattern: #"override\s+func\s+(\w+)"#
        ) else { return [] }
        var out: [APViolation] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { i += 1; continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = overrideRe.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line) else { i += 1; continue }
            let methodName = String(line[nameRange])
            guard lifecycleMethods.contains(methodName) else { i += 1; continue }
            // Scan the body (until matching closing brace) for super.methodName(
            var depth = 0
            var foundSuper = false
            var j = i
            while j < min(lines.count, i + 60) {
                let bodyLine = lines[j]
                depth += bodyLine.components(separatedBy: "{").count - 1
                depth -= bodyLine.components(separatedBy: "}").count - 1
                if bodyLine.contains("super.\(methodName)(") || bodyLine.contains("super.\(methodName) (") {
                    foundSuper = true; break
                }
                if j > i && depth <= 0 { break }
                j += 1
            }
            if !foundSuper {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
            i += 1
        }
        return out
    }
}

// MARK: - New LOW Checks

private extension AntipatternAnalyzer {

    static func checkNSLogUsage(_ filePath: String, _ lines: [String]) -> [APViolation] {
        if filePath.lowercased().contains("test") { return [] }
        if lines.contains(where: { $0.contains("// LEGACY") }) { return [] }
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if stripStrings(line).contains("NSLog(") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }

    static func checkImageLiteral(_ filePath: String, _ lines: [String]) -> [APViolation] {
        var out: [APViolation] = []
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            if stripStrings(line).contains("#imageLiteral") {
                out.append(viol(filePath, i, lines))
                if out.count >= maxViolations { break }
            }
        }
        return out
    }
}
