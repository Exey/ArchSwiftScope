// Exey Panteleev
import Foundation

// MARK: - Models

enum PatternCategory: String, CaseIterable {
    case creational = "Creational"
    case structural = "Structural"
    case behavioral = "Behavioral"
    // Not a GoF category — Monitor Object, Read–Write Lock, Double-Checked
    // Locking, and Thread Pool are POSA/concurrency patterns. Filing them
    // under Behavioral would misdescribe them: they're about thread-safety,
    // not object interaction, so they get their own column.
    case concurrency = "Concurrency"

    // FIX #9: explicit index for canonical GoF order (Creational → Structural → Behavioral)
    // rather than rawValue alphabetic sort which gives Behavioral → Creational → Structural.
    var order: Int {
        switch self {
        case .creational: return 0
        case .structural: return 1
        case .behavioral: return 2
        case .concurrency: return 3
        }
    }

    var icon: String {
        switch self {
        case .creational: return "🏗️"
        case .structural: return "🧱"
        case .behavioral: return "🔄"
        case .concurrency: return "🧵"
        }
    }
}

struct DetectedDesignPattern {
    let name: String
    let category: PatternCategory
    let count: Int
    let examplePath: String   // absolute path for VS Code link
    let detail: String
    var letter: String = ""   // mnemonic letter badge (e.g. "K" for Kommando)
    // True for Extension/Lazy Initialization/Monitor Object — constructs Swift
    // absorbed straight into the language, so virtually every real codebase
    // "has" them. Reporting them alongside a deliberate Factory/Observer/
    // Command implementation conflates "uses the language" with "chose a
    // pattern" — the UI uses this to render them as a distinct, muted row
    // instead of inflating the pattern count.
    var isLanguageIdiom: Bool = false
}

// MARK: - Detector

struct DesignPatternDetector {

    // Single-pass content scan result per file
    private struct FileScan {
        var singleton:      Bool = false
        var prototype:      Bool = false
        var obsContent:     Bool = false
        var cmdExecute:     Bool = false  // func execute()/run()/call() declared
        var cmdProto:       Bool = false  // protocol Command supertype or conformance
        var cmdInvoker:     Bool = false  // holds a [Command] list and dispatches it
        var cmdCallSite:    Bool = false  // .execute() called on an object
        var iterator:       Bool = false
        var templateMethod: Bool = false
        var stateProto:     Bool = false  // protocol State/StateProtocol supertype declared
        var stateConform:   Bool = false  // type conforms to State/StateProtocol
        var interpret:      Bool = false  // func interpret(...) declared
        var multiton:       Bool = false  // static dictionary of keyed shared instances
        var markerProtos:   [String] = [] // protocols declared with an empty body
        var handlerChain:   Bool = false  // next/successor field — CoR's defining trait
        var poolEvidence:   Bool = false  // acquire/release/checkout/reuse vocabulary
        var lazyVar:        Bool = false  // `lazy var` stored property — Lazy Initialization
        var barrierQueue:   Bool = false  // DispatchQueue + .barrier — Read–Write Lock
        var doubleCheckedLock: Bool = false // os_unfair_lock + repeated nil-check — Double-Checked Locking
        var threadPool:     Bool = false  // OperationQueue + maxConcurrentOperationCount — Thread Pool
        var fluentMethodCount: Int = 0    // methods declared `-> Self` — Fluent Interface
        var combineSignal:  Bool = false  // @Published / ObservableObject / import Combine — Observer via Combine/SwiftUI
        var swinjectImport: Bool = false  // import Swinject — Dependency Injection
    }

    func detect(files: [ParsedFile], cache: SourceCache) -> [DetectedDesignPattern] {
        let swiftFiles = files.filter { $0.filePath.hasSuffix(".swift") &&
                                        !$0.filePath.contains("/Tests/") &&
                                        !$0.filePath.contains("/Test/") }

        // ── Declaration index ──────────────────────────────────────────
        struct Decl { let name: String; let kind: Declaration.Kind; let path: String }
        let decls: [Decl] = swiftFiles.flatMap { f in
            f.declarations.compactMap { d in
                d.kind == .extension ? nil : Decl(name: d.name, kind: d.kind, path: f.filePath)
            }
        }

        // Extension declarations (excluded from `decls` above) and actor
        // declarations (already included in `decls`, since only `.extension`
        // is filtered out) — both are plain declaration-kind facts, not
        // content heuristics, so they read from the full `swiftFiles` list
        // like every other byName/byPrefix lookup.
        let extensionDecls: [Decl] = swiftFiles.flatMap { f in
            f.declarations.filter { $0.kind == .extension }.map { Decl(name: $0.name, kind: $0.kind, path: f.filePath) }
        }
        let actorDecls = decls.filter { $0.kind == .actor }

        // Protocol names declared in each file, keyed by path — needed to check
        // which protocols have an empty body (Marker interface pattern) without
        // re-deriving declarations inside the concurrent scan below.
        var protocolNamesByPath: [String: [String]] = [:]
        for d in decls where d.kind == .protocol {
            protocolNamesByPath[d.path, default: []].append(d.name)
        }

        // The content-scan checks below are raw substring searches for code
        // shapes like ": Command {", "protocol State {", or "NotificationCenter
        // .default" — and this tool's own analyzer/detector/scanner sources spell
        // those exact shapes out in string literals (that's their job). Scanning
        // them self-triggers Singleton/Prototype/Observer/Iterator/Command/State/
        // Multiton false positives whenever this tool analyzes its own repo, with
        // zero relation to what those files actually declare. Declaration-name
        // matching (byName/byPrefix) is unaffected by this exclusion — it stays
        // on the full `swiftFiles` list below, so e.g. TemporalAnalyzer.swift's
        // genuine `CodebaseSnapshot` type still counts toward Memento.
        let contentScanFiles = swiftFiles.filter { f in
            let base = (f.filePath as NSString).lastPathComponent
            return !base.hasSuffix("Analyzer.swift") && !base.hasSuffix("Detector.swift") &&
                   !base.hasSuffix("Scanner.swift")
        }

        // ── Single-pass content scan ───────────────────────────────────
        // Source text/lines come from the shared cache (no per-detector disk
        // read); content-based heuristics below are intentionally coarse — all
        // results are approximate.
        //
        // FIX #1: write through UnsafeMutableBufferPointer so concurrent writes to
        // distinct indices don't race through Swift's COW Array machinery.
        var scans = [FileScan?](repeating: nil, count: contentScanFiles.count)
        scans.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: contentScanFiles.count) { idx in
                let path = contentScanFiles[idx].filePath
                // Stripped, not raw — every check below is a `content.contains(...)`
                // or per-line probe for a code *shape* (a protocol declaration, a
                // method call), and a doc comment or log message that happens to
                // spell out that shape in prose must not count as the real thing
                // any more than the self-referential-file exclusion above lets this
                // tool's own source spell out those shapes in string literals.
                guard let content = cache.strippedText(path),
                      let cachedLines = cache.strippedLines(path) else { return }
                var s = FileScan()

                // Checks the keyword starts a line (after trimming indentation),
                // not a fixed 0/4-space/tab offset — a member 8+ spaces deep (nested
                // type) or a 2-space-indented codebase was previously invisible to
                // this check. Reuses the cache's pre-split lines rather than
                // re-splitting content per call.
                //
                // Modifiers/attributes ahead of the keyword (`public static let
                // shared`, `private var next:`, `override func run()`,
                // `@discardableResult func acquire(`) are stripped first — real
                // declarations almost always carry at least one of these, so a
                // bare hasPrefix(kw) on the untouched line would miss the common
                // case. A modifier equal to kw's own first word is never stripped,
                // so atDecl("static let shared") isn't defeated by treating
                // "static" as noise to skip past.
                let contentLines = cachedLines
                func atDecl(_ kw: String) -> Bool {
                    let firstWord = Self.firstWord(of: kw)
                    return contentLines.contains {
                        Self.stripLeadingModifiers($0.trimmingCharacters(in: .whitespaces), keeping: firstWord).hasPrefix(kw)
                    }
                }
                // Like atDecl, but requires the prefix not just start the line but
                // end there too (word-boundary on the right) — "static var instance"
                // must not match "static var instances" (Multiton's plural), the
                // same way `hasPrefix` alone would conflate "instance" with "instances".
                func atDeclWord(_ kw: String) -> Bool {
                    let firstWord = Self.firstWord(of: kw)
                    return contentLines.contains { line in
                        let trimmed = Self.stripLeadingModifiers(line.trimmingCharacters(in: .whitespaces), keeping: firstWord)
                        guard trimmed.hasPrefix(kw) else { return false }
                        guard let c = trimmed.dropFirst(kw.count).first else { return true }
                        return !(c.isLetter || c.isNumber || c == "_")
                    }
                }

                // Singleton: static shared/instance property declaration. "instance"
                // requires a word boundary — "static var instance" must not match
                // Multiton's "static var instances" (plural) via prefix overlap.
                if atDecl("static let shared") || atDecl("static var shared") ||
                   atDeclWord("static let instance") || atDeclWord("static var instance") {
                    s.singleton = true
                }
                // Prototype: NSCopying conformance or copy/clone declaration
                if content.contains(": NSCopying") || content.contains(", NSCopying") ||
                   atDecl("func copy()") || atDecl("func clone()") {
                    s.prototype = true
                }
                // Observer: require actual NotificationCenter usage (not just the type name),
                // Combine publisher subscription, or addObserver call with a self argument
                if content.contains("NotificationCenter.default") ||
                   content.contains(".addObserver(self") ||
                   content.contains(".addObserver(forName") ||
                   content.contains(".publisher(for:") {
                    s.obsContent = true
                }
                // Command (K for Kommando): execute/run/call method at declaration level
                if atDecl("func execute()") || atDecl("func execute(") ||
                   atDecl("func run()") || atDecl("func call()") {
                    s.cmdExecute = true
                }
                // Command: protocol Command supertype declaration or type conformance
                if content.contains("protocol Command {") || content.contains("protocol Command:") ||
                   content.contains("protocol Commandable") ||
                   content.contains(": Command {") || content.contains(": Command,") ||
                   content.contains(", Command {") {
                    s.cmdProto = true
                }
                // Command: invoker holds a list of commands and dispatches them
                if content.contains(": [Command]") || content.contains("[any Command]") ||
                   content.contains("commands.forEach") ||
                   (content.contains("var commands") && content.contains(".execute()")) {
                    s.cmdInvoker = true
                }
                // Command: call sites — .execute() invoked on an object
                if content.contains(".execute()") {
                    s.cmdCallSite = true
                }
                // Iterator: require conformance syntax or declaration-level next()
                if content.contains(": IteratorProtocol") || content.contains(", IteratorProtocol") ||
                   atDecl("func next() ->") {
                    s.iterator = true
                }
                // Object Pool evidence: checkout/return vocabulary — what actually
                // distinguishes a pool (lend an object, get it back) from a cache
                // (memoize a computed value). Gates the *Pool suffix below.
                if atDecl("func acquire(") || atDecl("func release(") ||
                   atDecl("func checkout(") || atDecl("func checkin(") ||
                   atDecl("func borrow(") || atDecl("func reuse(") ||
                   atDecl("func recycle(") || atDecl("func returnObject(") ||
                   atDecl("func returnToPool(") {
                    s.poolEvidence = true
                }
                // Chain of Responsibility: a successor link — the trait that actually
                // distinguishes the pattern from every other "*Handler" in the codebase
                // (ErrorHandler, URLHandler, GestureHandler, completion handlers, …).
                if atDecl("var next:") || atDecl("let next:") ||
                   atDecl("var successor:") || atDecl("let successor:") {
                    s.handlerChain = true
                }
                // Template Method: declaration-level only (setup/configure removed — too broad)
                if atDecl("func templateMethod") {
                    s.templateMethod = true
                }
                // State: protocol State/StateProtocol supertype, and separately a
                // conformance to it — both signals may live in different files.
                if content.contains("protocol State {") || content.contains("protocol State:") ||
                   content.contains("protocol StateProtocol") {
                    s.stateProto = true
                }
                if content.contains(": State {") || content.contains(": State,") ||
                   content.contains(", State {") || content.contains(": StateProtocol") ||
                   content.contains(", StateProtocol") {
                    s.stateConform = true
                }
                // Interpreter: declaration-level interpret(...) method
                if atDecl("func interpret(") {
                    s.interpret = true
                }
                // Multiton: static dictionary of keyed shared instances — covers
                // both explicit (`: [Key: V]`) and type-inferred (`= [Key: V]()`)
                // declaration styles.
                if atDecl("static var instances: [") || atDecl("static let instances: [") ||
                   atDecl("static var instances = [") || atDecl("static let instances = [") ||
                   atDecl("static var instances=[") || atDecl("static let instances=[") {
                    s.multiton = true
                }
                // Lazy Initialization: a `lazy var` stored property, wherever it sits
                // (access modifiers before it defeat a prefix check, so this is a
                // plain substring search rather than atDecl).
                if contentLines.contains(where: { $0.contains("lazy var ") }) {
                    s.lazyVar = true
                }
                // Read–Write Lock: a concurrent DispatchQueue used with the .barrier
                // flag — Swift's idiom for GCD-backed multiple-readers/single-writer.
                if content.contains("DispatchQueue") && content.contains(".barrier") {
                    s.barrierQueue = true
                }
                // Double-Checked Locking: approximate — a raw os_unfair_lock
                // co-occurring with more than one nil-check in the same file, the
                // shape of "check outside the lock, lock, check again inside".
                // Swift's usual idiom for this (lazy var / static let) doesn't need
                // the pattern at all, so this only fires on the rarer manual-lock form.
                if content.contains("os_unfair_lock") &&
                   content.components(separatedBy: "== nil").count > 2 {
                    s.doubleCheckedLock = true
                }
                // Thread Pool: an OperationQueue with its concurrency explicitly
                // bounded to more than one — `= 1` is a serial queue, used for
                // ordering, not pooling, and is the single most common value
                // this property is set to.
                if content.contains("OperationQueue") && content.contains("maxConcurrentOperationCount") &&
                   !content.contains("maxConcurrentOperationCount = 1") &&
                   !content.contains("maxConcurrentOperationCount=1") {
                    s.threadPool = true
                }
                // Fluent Interface: methods declared to return Self, enabling
                // `.foo().bar().baz()` call chains.
                s.fluentMethodCount = contentLines.filter { $0.contains("func ") && $0.contains("-> Self") }.count
                // Observer via Combine/SwiftUI: @Published and ObservableObject are
                // Combine's actual implementation of Observer, distinct from the
                // NotificationCenter/publisher(for:) signals above. Deliberately NOT
                // triggered by a bare `import SwiftUI` — nearly every iOS file has
                // that import regardless of whether it observes anything, which would
                // flood this signal the same way a bare `.execute()` call site would
                // flood Command if it weren't gated (see the comment on cmdCallSite).
                if content.contains("@Published") || content.contains(": ObservableObject") ||
                   content.contains(", ObservableObject") || content.contains("import Combine") {
                    s.combineSignal = true
                }
                // Dependency Injection: Swinject is a strong, unambiguous signal on
                // its own — nobody imports it without using it for DI.
                if content.contains("import Swinject") {
                    s.swinjectImport = true
                }
                // Marker interface: a protocol declared with a body containing no
                // requirements (no func/var/subscript/associatedtype members) —
                // used purely to tag conforming types.
                if let protoNames = protocolNamesByPath[path] {
                    for name in protoNames {
                        if let body = Self.protocolBody(in: cachedLines, protocolName: name), Self.isEmptyBody(body) {
                            s.markerProtos.append(name)
                        }
                    }
                }

                buf[idx] = s
            }
        }

        var scanMap: [String: FileScan] = [:]
        for (idx, file) in contentScanFiles.enumerated() {
            if let s = scans[idx] { scanMap[file.filePath] = s }
        }

        func paths(where pred: (FileScan) -> Bool) -> [String] {
            scanMap.compactMap { pred($0.value) ? $0.key : nil }.sorted()
        }
        func byName(_ suffix: String, kinds: Set<Declaration.Kind>? = nil) -> [Decl] {
            decls.filter { $0.name.hasSuffix(suffix) && (kinds == nil || kinds!.contains($0.kind)) }
        }
        func byNames(_ suffixes: [String], kinds: Set<Declaration.Kind>? = nil) -> [Decl] {
            decls.filter { d in
                suffixes.contains { d.name.hasSuffix($0) } && (kinds == nil || kinds!.contains(d.kind))
            }
        }
        // Requires the character right after the prefix to start a new word
        // (uppercase) — "Null" + "Logger" is Null<X> naming, "Null" + "able" is
        // just the word "Nullable" and must not match.
        func byPrefix(_ prefix: String, kinds: Set<Declaration.Kind>? = nil) -> [Decl] {
            decls.filter { d in
                guard d.name.hasPrefix(prefix), d.name.count > prefix.count,
                      (kinds == nil || kinds!.contains(d.kind)) else { return false }
                let nextChar = d.name[d.name.index(d.name.startIndex, offsetBy: prefix.count)]
                return nextChar.isUppercase
            }
        }

        var result: [DetectedDesignPattern] = []

        // ── CREATIONAL ─────────────────────────────────────────────────

        let singletonPaths = paths { $0.singleton }
        if !singletonPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Singleton", category: .creational,
                count: singletonPaths.count, examplePath: singletonPaths[0],
                detail: "\(singletonPaths.count) static shared/instance"))
        }

        let factoryDecls = byName("Factory")
        if !factoryDecls.isEmpty {
            let protos = factoryDecls.filter { $0.kind == .protocol }
            let label  = protos.isEmpty ? "Factory Method" : "Abstract Factory"
            result.append(DetectedDesignPattern(
                name: label, category: .creational,
                count: factoryDecls.count, examplePath: factoryDecls[0].path,
                detail: "\(factoryDecls.count) Factory type\(factoryDecls.count == 1 ? "" : "s")" +
                    (protos.isEmpty ? "" : " · \(protos.count) protocols")))
        }

        let builderDecls = byName("Builder")
        if !builderDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Builder", category: .creational,
                count: builderDecls.count, examplePath: builderDecls[0].path,
                detail: "\(builderDecls.count) Builder type\(builderDecls.count == 1 ? "" : "s")"))
        }

        let protoPaths = paths { $0.prototype }
        if !protoPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Prototype", category: .creational,
                count: protoPaths.count, examplePath: protoPaths[0],
                detail: "NSCopying / copy() / clone()"))
        }

        let multitonPaths = paths { $0.multiton }
        if !multitonPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Multiton", category: .creational,
                count: multitonPaths.count, examplePath: multitonPaths[0],
                detail: "static instances: [Key: Self] in \(multitonPaths.count) file\(multitonPaths.count == 1 ? "" : "s")"))
        }

        let diDecls = byNames(["ServiceLocator", "DIContainer", "Injector"], kinds: [.class, .struct, .protocol, .actor])
        let swinjectPaths = paths { $0.swinjectImport }
        let diPathSet = Set(diDecls.map(\.path)).union(swinjectPaths)
        if !diPathSet.isEmpty {
            var parts: [String] = []
            if !diDecls.isEmpty       { parts.append("\(diDecls.count) ServiceLocator/DIContainer/Injector type\(diDecls.count == 1 ? "" : "s")") }
            if !swinjectPaths.isEmpty { parts.append("import Swinject in \(swinjectPaths.count) file\(swinjectPaths.count == 1 ? "" : "s")") }
            result.append(DetectedDesignPattern(
                name: "Dependency Injection", category: .creational,
                count: diPathSet.count, examplePath: diDecls.first?.path ?? swinjectPaths.sorted()[0],
                detail: parts.joined(separator: " · ")))
        }

        // Lazy Initialization: a `lazy var` stored property defers construction
        // until first access — Swift's built-in equivalent of the GoF pattern.
        let lazyVarPaths = paths { $0.lazyVar }
        if !lazyVarPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Lazy Initialization", category: .creational,
                count: lazyVarPaths.count, examplePath: lazyVarPaths[0],
                detail: "lazy var in \(lazyVarPaths.count) file\(lazyVarPaths.count == 1 ? "" : "s")",
                isLanguageIdiom: true))
        }

        // ── STRUCTURAL ─────────────────────────────────────────────────

        let structuralSuffixes: [(String, String)] = [
            ("Adapter",   "Adapter"),
            ("Decorator", "Decorator"),
            ("Facade",    "Facade"),
            ("Proxy",     "Proxy"),
            ("Composite", "Composite"),
            ("Bridge",    "Bridge"),
            // Distinct from the Cache/Pool-based "Object Pool" below (FIX #6) —
            // this only fires on the literal name "*Flyweight", i.e. explicit intent.
            ("Flyweight", "Flyweight"),
            ("FrontController", "Front Controller"),
        ]
        for (suffix, name) in structuralSuffixes {
            let found = byName(suffix)
            if !found.isEmpty {
                result.append(DetectedDesignPattern(
                    name: name, category: .structural,
                    count: found.count, examplePath: found[0].path,
                    detail: "\(found.count) \(suffix) type\(found.count == 1 ? "" : "s")"))
            }
        }

        // FIX #6: renamed from "Flyweight" — *Cache/*Pool types implement object pooling
        // or caching, not GoF Flyweight (shared immutable intrinsic state). Honest label.
        // Split further: caching and pooling are different intents (a cache
        // memoizes a computed value; a pool lends an object out and expects it
        // back via acquire/release-style checkout). *Pool naming alone is only
        // circumstantial — gate it on checkout/return vocabulary so an
        // unrelated "ConnectionPool" that just holds config isn't reported as
        // implementing object pooling it doesn't actually do.
        let poolEvidencePaths = Set(paths { $0.poolEvidence })
        let poolDecls  = byName("Pool", kinds: [.class, .struct, .actor])
            .filter { poolEvidencePaths.contains($0.path) }
        let cacheDecls = byName("Cache", kinds: [.class, .struct, .actor])
        if !poolDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Object Pool", category: .structural,
                count: poolDecls.count, examplePath: poolDecls[0].path,
                detail: "\(poolDecls.count) Pool type\(poolDecls.count == 1 ? "" : "s") · acquire/release evidence"))
        }
        if !cacheDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Caching", category: .structural,
                count: cacheDecls.count, examplePath: cacheDecls[0].path,
                detail: "\(cacheDecls.count) Cache type\(cacheDecls.count == 1 ? "" : "s")"))
        }

        // Marker interface: protocol declared with zero requirements, used purely
        // to tag conforming types (e.g. `protocol Trashable {}`).
        let markerEntries: [(name: String, path: String)] = scanMap.flatMap { path, s in
            s.markerProtos.map { (name: $0, path: path) }
        }.sorted { $0.name < $1.name }
        if !markerEntries.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Marker", category: .structural,
                count: markerEntries.count, examplePath: markerEntries[0].path,
                detail: "\(markerEntries.count) empty protocol\(markerEntries.count == 1 ? "" : "s") · e.g. \(markerEntries[0].name)"))
        }

        // Extension Object: adding behavior to an existing type from the outside,
        // without subclassing — Swift's `extension` is this pattern built into
        // the language.
        if !extensionDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Extension", category: .structural,
                count: extensionDecls.count, examplePath: extensionDecls[0].path,
                detail: "\(extensionDecls.count) extension\(extensionDecls.count == 1 ? "" : "s") adding behavior without subclassing",
                isLanguageIdiom: true))
        }

        // Fluent Interface: a method declared to return Self, enabling
        // `.foo().bar().baz()` chains — closely related to Builder, but a
        // general API-design technique in its own right. A single `-> Self`
        // method (e.g. one makeCopy() -> Self) isn't a fluent API on its own —
        // require at least 2 in the same file, the way a real chainable
        // builder actually reads.
        let fluentCounts = scanMap.mapValues(\.fluentMethodCount)
        let fluentPaths = fluentCounts.filter { $0.value >= 2 }.keys.sorted()
        if !fluentPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Fluent Interface", category: .structural,
                count: fluentPaths.count, examplePath: fluentPaths[0],
                detail: "≥2 -> Self methods in \(fluentPaths.count) file\(fluentPaths.count == 1 ? "" : "s") · chainable calls"))
        }

        // ── CONCURRENCY ─────────────────────────────────────────────────
        // POSA/concurrency patterns, not GoF — Swift-native or GCD-idiom
        // equivalents of classic synchronization techniques.

        // Monitor Object: `actor` is Swift's language-level monitor — mutual
        // exclusion enforced by the compiler rather than a manual lock.
        if !actorDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Monitor Object", category: .concurrency,
                count: actorDecls.count, examplePath: actorDecls[0].path,
                detail: "\(actorDecls.count) actor type\(actorDecls.count == 1 ? "" : "s") · compiler-enforced mutual exclusion",
                isLanguageIdiom: true))
        }

        // Read–Write Lock: a concurrent DispatchQueue read normally, written
        // with .barrier — GCD's idiom for multiple-readers/single-writer.
        let barrierPaths = paths { $0.barrierQueue }
        if !barrierPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Read–Write Lock", category: .concurrency,
                count: barrierPaths.count, examplePath: barrierPaths[0],
                detail: "DispatchQueue + .barrier in \(barrierPaths.count) file\(barrierPaths.count == 1 ? "" : "s")"))
        }

        // Double-Checked Locking: approximate — see the FileScan.doubleCheckedLock
        // comment for exactly what this looks for and why it's coarse.
        let dclPaths = paths { $0.doubleCheckedLock }
        if !dclPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Double-Checked Locking", category: .concurrency,
                count: dclPaths.count, examplePath: dclPaths[0],
                detail: "os_unfair_lock + repeated nil-check in \(dclPaths.count) file\(dclPaths.count == 1 ? "" : "s") · approximate"))
        }

        // Thread Pool: an OperationQueue with its concurrency explicitly bounded.
        let threadPoolPaths = paths { $0.threadPool }
        if !threadPoolPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Thread Pool", category: .concurrency,
                count: threadPoolPaths.count, examplePath: threadPoolPaths[0],
                detail: "OperationQueue + maxConcurrentOperationCount in \(threadPoolPaths.count) file\(threadPoolPaths.count == 1 ? "" : "s")"))
        }

        // ── BEHAVIORAL ─────────────────────────────────────────────────

        // Delegation: split out from Observer (FIX #4 used to union them into
        // one count) — delegation is one object forwarding responsibility to a
        // single designated other, which is a distinct claim from Observer's
        // one-to-many broadcast, even though both ship as `*Delegate` protocols
        // and NotificationCenter/Combine in this codebase's naming conventions.
        let delegateProtos = byName("Delegate", kinds: [.protocol])
        if !delegateProtos.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Delegation", category: .behavioral,
                count: delegateProtos.count, examplePath: delegateProtos[0].path,
                detail: "\(delegateProtos.count) delegate protocol\(delegateProtos.count == 1 ? "" : "s")"))
        }

        // FIX #4: Observer unified to file count — one file = one count, whichever
        // of its NC/Combine-publisher and @Published/ObservableObject signals fired.
        let obsPaths     = paths { $0.obsContent }
        let combinePaths = paths { $0.combineSignal }
        let allObsFiles  = Set(obsPaths).union(combinePaths).sorted()
        if !allObsFiles.isEmpty {
            var parts: [String] = []
            if !obsPaths.isEmpty     { parts.append("\(obsPaths.count) NC/Combine file\(obsPaths.count == 1 ? "" : "s")") }
            if !combinePaths.isEmpty { parts.append("\(combinePaths.count) @Published/ObservableObject file\(combinePaths.count == 1 ? "" : "s")") }
            result.append(DetectedDesignPattern(
                name: "Observer", category: .behavioral,
                count: allObsFiles.count, examplePath: allObsFiles[0],
                detail: parts.joined(separator: " · ")))
        }

        let strategyDecls = byName("Strategy")
        if !strategyDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Strategy", category: .behavioral,
                count: strategyDecls.count, examplePath: strategyDecls[0].path,
                detail: "\(strategyDecls.count) Strategy type\(strategyDecls.count == 1 ? "" : "s")"))
        }

        // Command (K for Kommando) — five-signal detection:
        // 1. Names containing Command/Action/Operation/Task  +  execute/run/call declared
        // 2. protocol Command supertype or conformance
        // 3. Invoker class holding a [Command] list
        // 4. Receiver dependency (implicit via name+execute co-occurrence)
        // 5. .execute() call sites
        let cmdTypeDecls: [Decl] = {
            let keywords = ["Command", "Action", "Operation", "Task"]
            return decls.filter { d in
                guard d.kind == .class || d.kind == .struct || d.kind == .protocol else { return false }
                guard keywords.contains(where: { d.name.contains($0) }) else { return false }
                // Non-Command names (Action/Operation/Task) require execute/run/call in same file
                if !d.name.contains("Command") {
                    return scanMap[d.path].map { $0.cmdExecute } ?? false
                }
                return true
            }
        }()
        let cmdExPaths    = paths { $0.cmdExecute }
        let cmdProtoPaths = paths { $0.cmdProto }
        let cmdInvPaths   = paths { $0.cmdInvoker }
        let cmdCallPaths  = paths { $0.cmdCallSite }
        // .execute() call sites alone are not Command evidence — `.execute()` is
        // also SQLite/GRDB's statement API, URLRequest-builder APIs, etc. They
        // only strengthen a match some OTHER signal already established; folded
        // in unconditionally, a codebase with zero Command types/protocols but
        // some unrelated `.execute()` call would still "detect" Command.
        let primaryCmdEvidence = Set(cmdTypeDecls.map(\.path))
            .union(cmdExPaths)
            .union(cmdProtoPaths)
            .union(cmdInvPaths)
        let allCmdEvidence = primaryCmdEvidence.isEmpty ? [] : primaryCmdEvidence.union(cmdCallPaths)
        // FIX #4 (Observer) unified mixed-unit counting to one union; Command's
        // `max(declCount, fileCount)` mixed two different units the same way.
        // Prefer the more granular decl count when type decls exist (matches how
        // every other suffix-based pattern below reports "N Foo types"); fall
        // back to the file-evidence count only when detection came purely from
        // content signals (protocol/invoker/execute with no named Command type).
        let cmdCount = cmdTypeDecls.isEmpty ? allCmdEvidence.count : cmdTypeDecls.count
        // FIX #8: guard non-empty path explicitly rather than relying on ?? ""
        if let cmdPath = cmdTypeDecls.first?.path ?? allCmdEvidence.sorted().first, cmdCount > 0 {
            var parts: [String] = []
            if !cmdTypeDecls.isEmpty  { parts.append("\(cmdTypeDecls.count) type\(cmdTypeDecls.count == 1 ? "" : "s")") }
            if !cmdProtoPaths.isEmpty { parts.append("proto · \(cmdProtoPaths.count) file\(cmdProtoPaths.count == 1 ? "" : "s")") }
            if !cmdInvPaths.isEmpty   { parts.append("\(cmdInvPaths.count) invoker\(cmdInvPaths.count == 1 ? "" : "s")") }
            if !cmdCallPaths.isEmpty  { parts.append(".execute() sites") }
            else if !cmdExPaths.isEmpty { parts.append("\(cmdExPaths.count) execute() impl\(cmdExPaths.count == 1 ? "" : "s")") }
            result.append(DetectedDesignPattern(
                name: "Command", category: .behavioral,
                count: cmdCount, examplePath: cmdPath,
                detail: parts.joined(separator: " · "),
                letter: "K"))
        }

        // "Handler" is the single most abused suffix in Swift (ErrorHandler,
        // URLHandler, GestureHandler, completion handlers) — almost none of it is
        // Chain of Responsibility. Gate on the pattern's defining trait instead:
        // a successor link (the same self-referencing-field signal
        // DataStructureDetector uses for linked structures).
        let chainLinkedPaths = Set(paths { $0.handlerChain })
        let chainDecls = byName("Handler").filter { chainLinkedPaths.contains($0.path) }
        if !chainDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Chain of Resp.", category: .behavioral,
                count: chainDecls.count, examplePath: chainDecls[0].path,
                detail: "\(chainDecls.count) Handler type\(chainDecls.count == 1 ? "" : "s") · next/successor link"))
        }

        let mediatorDecls = byName("Mediator")
        if !mediatorDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Mediator", category: .behavioral,
                count: mediatorDecls.count, examplePath: mediatorDecls[0].path,
                detail: "\(mediatorDecls.count) Mediator type\(mediatorDecls.count == 1 ? "" : "s")"))
        }

        let visitorDecls = byName("Visitor")
        if !visitorDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Visitor", category: .behavioral,
                count: visitorDecls.count, examplePath: visitorDecls[0].path,
                detail: "\(visitorDecls.count) Visitor type\(visitorDecls.count == 1 ? "" : "s")"))
        }

        let mementoDecls = byNames(["Memento", "Snapshot"], kinds: [.class, .struct])
        if !mementoDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Memento", category: .behavioral,
                count: mementoDecls.count, examplePath: mementoDecls[0].path,
                detail: "\(mementoDecls.count) Memento/Snapshot type\(mementoDecls.count == 1 ? "" : "s")"))
        }

        let iterPaths = paths { $0.iterator }
        if !iterPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Iterator", category: .behavioral,
                count: iterPaths.count, examplePath: iterPaths[0],
                detail: "IteratorProtocol in \(iterPaths.count) file\(iterPaths.count == 1 ? "" : "s")"))
        }

        // Tight heuristic — will under-report but avoids near-universal false positives
        let tmPaths = paths { $0.templateMethod }
        if !tmPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Template Method", category: .behavioral,
                count: tmPaths.count, examplePath: tmPaths[0],
                detail: "templateMethod() in \(tmPaths.count) file\(tmPaths.count == 1 ? "" : "s")"))
        }

        // State: require both a State/StateProtocol supertype declaration and at
        // least one conformance to it — two-signal gate avoids matching every
        // `enum LoadingState` naming convention that isn't the GoF pattern.
        let stateProtoPaths    = paths { $0.stateProto }
        let stateConformPaths  = paths { $0.stateConform }
        if !stateProtoPaths.isEmpty && !stateConformPaths.isEmpty {
            result.append(DetectedDesignPattern(
                name: "State", category: .behavioral,
                count: stateConformPaths.count, examplePath: stateProtoPaths[0],
                detail: "State protocol · \(stateConformPaths.count) conforming file\(stateConformPaths.count == 1 ? "" : "s")"))
        }

        // Interpreter: types named *Interpreter, or any declared interpret(...) method
        let interpreterDecls = byName("Interpreter")
        let interpretPaths    = paths { $0.interpret }
        let interpreterEvidence = Set(interpreterDecls.map(\.path)).union(interpretPaths)
        if !interpreterEvidence.isEmpty {
            let examplePath = interpreterDecls.first?.path ?? interpretPaths[0]
            result.append(DetectedDesignPattern(
                name: "Interpreter", category: .behavioral,
                count: interpreterEvidence.count, examplePath: examplePath,
                detail: "\(interpreterDecls.count) Interpreter type\(interpreterDecls.count == 1 ? "" : "s") · \(interpretPaths.count) interpret() file\(interpretPaths.count == 1 ? "" : "s")"))
        }

        // Null Object: types prefixed Null<X> — a no-op stand-in for a real <X>
        let nullObjectDecls = byPrefix("Null", kinds: [.class, .struct, .enum])
        if !nullObjectDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Null Object", category: .behavioral,
                count: nullObjectDecls.count, examplePath: nullObjectDecls[0].path,
                detail: "\(nullObjectDecls.count) Null-prefixed type\(nullObjectDecls.count == 1 ? "" : "s")"))
        }

        let specificationDecls = byName("Specification")
        if !specificationDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Specification", category: .behavioral,
                count: specificationDecls.count, examplePath: specificationDecls[0].path,
                detail: "\(specificationDecls.count) Specification type\(specificationDecls.count == 1 ? "" : "s")"))
        }

        // FIX #9: sort by explicit order index, then count desc within category
        return result.sorted {
            if $0.category.order != $1.category.order { return $0.category.order < $1.category.order }
            return $0.count > $1.count
        }
    }

    // MARK: - Declaration-modifier stripping

    // Access/behavior modifiers that can precede a declaration keyword. Order
    // doesn't matter — stripLeadingModifiers loops until none apply.
    private static let declModifiers: [String] = [
        "public", "private", "internal", "fileprivate", "open", "package",
        "final", "override", "required", "convenience", "class", "static",
        "lazy", "weak", "unowned", "nonisolated", "dynamic", "mutating", "indirect",
    ]

    private static func firstWord(of kw: String) -> String {
        kw.split(separator: " ", maxSplits: 1).first.map(String.init) ?? kw
    }

    /// Strips leading attributes (`@objc`, `@MainActor`, `@discardableResult`,
    /// `@Foo(args)`) and access/behavior modifiers from `line`, so a keyword
    /// check like `hasPrefix("static let shared")` still matches `public static
    /// let shared = Foo()`. A modifier equal to `keeping` (the target keyword's
    /// own first word) is left alone, so stripping "static" ahead of an
    /// `atDecl("static let shared")` check doesn't strip the very word the
    /// check is looking for.
    private static func stripLeadingModifiers(_ line: String, keeping: String) -> String {
        var s = line
        while true {
            if s.hasPrefix("@") {
                var idx = s.index(after: s.startIndex)
                while idx < s.endIndex, s[idx].isLetter || s[idx].isNumber || s[idx] == "_" {
                    idx = s.index(after: idx)
                }
                if idx < s.endIndex, s[idx] == "(" {
                    var depth = 1
                    idx = s.index(after: idx)
                    while idx < s.endIndex, depth > 0 {
                        if s[idx] == "(" { depth += 1 } else if s[idx] == ")" { depth -= 1 }
                        idx = s.index(after: idx)
                    }
                }
                s = String(s[idx...]).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let modifier = declModifiers.first(where: { $0 != keeping && s.hasPrefix($0 + " ") }) else {
                break
            }
            s = String(s.dropFirst(modifier.count)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    // MARK: - Marker interface helpers

    /// Extracts the body of `protocol <protocolName>` (contents between its
    /// outermost braces, braces themselves excluded) via brace matching.
    private static func protocolBody(in lines: [String], protocolName: String) -> String? {
        for (i, line) in lines.enumerated() {
            guard line.contains("protocol "), declaresProtocol(line, protocolName) else { continue }
            guard let openIdx = line.firstIndex(of: "{") else { return nil }

            var depth = 1
            var firstPiece = String(line[line.index(after: openIdx)...])
            for ch in firstPiece {
                if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1 }
            }
            if depth <= 0 {
                if let closeIdx = firstPiece.lastIndex(of: "}") { firstPiece = String(firstPiece[..<closeIdx]) }
                return firstPiece
            }

            var collected = [firstPiece]
            var j = i + 1
            while j < lines.count {
                let l = lines[j]
                var delta = 0
                for ch in l {
                    if ch == "{" { delta += 1 } else if ch == "}" { delta -= 1 }
                }
                if depth + delta <= 0 {
                    if let closeIdx = l.lastIndex(of: "}") { collected.append(String(l[..<closeIdx])) }
                    return collected.joined(separator: "\n")
                }
                collected.append(l)
                depth += delta
                j += 1
            }
            return collected.joined(separator: "\n")
        }
        return nil
    }

    /// True when `line` declares a protocol whose name is exactly `name` (boundary-checked).
    private static func declaresProtocol(_ line: String, _ name: String) -> Bool {
        guard let r = line.range(of: "protocol " + name) else { return false }
        if r.upperBound == line.endIndex { return true }
        let c = line[r.upperBound]
        return !(c.isLetter || c.isNumber || c == "_")
    }

    /// True when a protocol body has no requirements — no func/var/subscript/
    /// associatedtype members — meaning it exists only to tag conforming types.
    private static func isEmptyBody(_ body: String) -> Bool {
        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            if line.hasPrefix("func ") || line.hasPrefix("var ") || line.hasPrefix("let ") ||
               line.hasPrefix("subscript") || line.hasPrefix("associatedtype ") ||
               line.hasPrefix("static ") || line.hasPrefix("mutating ") ||
               line.hasPrefix("init(") || line.hasPrefix("init?(") || line.hasPrefix("init!(") ||
               line.hasPrefix("typealias ") {
                return false
            }
        }
        return true
    }
}
