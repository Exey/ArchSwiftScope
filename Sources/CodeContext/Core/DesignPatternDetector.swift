// Exey Panteleev
import Foundation

// MARK: - Models

enum PatternCategory: String, CaseIterable {
    case creational = "Creational"
    case structural = "Structural"
    case behavioral = "Behavioral"

    // FIX #9: explicit index for canonical GoF order (Creational → Structural → Behavioral)
    // rather than rawValue alphabetic sort which gives Behavioral → Creational → Structural.
    var order: Int {
        switch self {
        case .creational: return 0
        case .structural: return 1
        case .behavioral: return 2
        }
    }

    var icon: String {
        switch self {
        case .creational: return "🏗️"
        case .structural: return "🧱"
        case .behavioral: return "🔄"
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
    }

    func detect(files: [ParsedFile]) -> [DetectedDesignPattern] {
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

        // ── Single-pass content scan ───────────────────────────────────
        // NOTE: ParsedFile does not cache source text, so we re-read from disk here.
        // This is a second pass over the tree; content-based heuristics below are
        // intentionally coarse — all results are approximate.
        //
        // FIX #1: write through UnsafeMutableBufferPointer so concurrent writes to
        // distinct indices don't race through Swift's COW Array machinery.
        var scans = [FileScan?](repeating: nil, count: swiftFiles.count)
        scans.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: swiftFiles.count) { idx in
                guard let content = try? String(contentsOfFile: swiftFiles[idx].filePath,
                                                encoding: .utf8) else { return }
                var s = FileScan()

                // Require whitespace/newline before the keyword so patterns like
                //   content.contains("static let shared")
                // in this file's own source do NOT self-trigger (the preceding char is `"`
                // not a newline or indent). Actual declarations always appear after a newline.
                func atDecl(_ kw: String) -> Bool {
                    content.contains("\n" + kw) ||
                    content.contains("\n    " + kw) ||
                    content.contains("\n\t" + kw)
                }

                // Singleton: static shared/instance property declaration
                if content.contains("static let shared") || content.contains("static var shared") ||
                   content.contains("static let instance") || content.contains("static var instance") {
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
                // Template Method: declaration-level only (setup/configure removed — too broad)
                if atDecl("func templateMethod") {
                    s.templateMethod = true
                }

                buf[idx] = s
            }
        }

        var scanMap: [String: FileScan] = [:]
        for (idx, file) in swiftFiles.enumerated() {
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

        // ── STRUCTURAL ─────────────────────────────────────────────────

        let structuralSuffixes: [(String, String)] = [
            ("Adapter",   "Adapter"),
            ("Decorator", "Decorator"),
            ("Facade",    "Facade"),
            ("Proxy",     "Proxy"),
            ("Composite", "Composite"),
            ("Bridge",    "Bridge"),
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
        let poolDecls = byNames(["Cache", "Pool"], kinds: [.class, .struct, .actor])
        if !poolDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Object Pool", category: .structural,
                count: poolDecls.count, examplePath: poolDecls[0].path,
                detail: "\(poolDecls.count) Cache/Pool type\(poolDecls.count == 1 ? "" : "s")"))
        }

        // ── BEHAVIORAL ─────────────────────────────────────────────────

        // FIX #4: Observer unified to file count.
        // A file with a delegate protocol that also uses NC was previously counted twice
        // in two different units (protocol count + file count). Now we take the union of
        // files that exhibit either signal — one file = one count.
        let delegateProtos  = byName("Delegate", kinds: [.protocol])
        let obsPaths        = paths { $0.obsContent }
        let delegatePathSet = Set(delegateProtos.map(\.path))
        let allObsFiles     = delegatePathSet.union(obsPaths).sorted()
        if !allObsFiles.isEmpty {
            var parts: [String] = []
            if !delegateProtos.isEmpty { parts.append("\(delegateProtos.count) delegate protocol\(delegateProtos.count == 1 ? "" : "s")") }
            if !obsPaths.isEmpty       { parts.append("\(obsPaths.count) NC/Combine file\(obsPaths.count == 1 ? "" : "s")") }
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
        let allCmdEvidence = Set(cmdTypeDecls.map(\.path))
            .union(cmdExPaths)
            .union(cmdProtoPaths)
            .union(cmdInvPaths)
            .union(cmdCallPaths)
        let cmdCount = max(cmdTypeDecls.count, allCmdEvidence.count)
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

        let chainDecls = byName("Handler")
        if !chainDecls.isEmpty {
            result.append(DetectedDesignPattern(
                name: "Chain of Resp.", category: .behavioral,
                count: chainDecls.count, examplePath: chainDecls[0].path,
                detail: "\(chainDecls.count) Handler type\(chainDecls.count == 1 ? "" : "s")"))
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

        // FIX #9: sort by explicit order index, then count desc within category
        return result.sorted {
            if $0.category.order != $1.category.order { return $0.category.order < $1.category.order }
            return $0.count > $1.count
        }
    }
}
