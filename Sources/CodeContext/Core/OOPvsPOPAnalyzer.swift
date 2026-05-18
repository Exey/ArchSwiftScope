// Exey Panteleev
import Foundation

// MARK: - Stats Model

struct OOPvsPOPStats {
    // ── Raw counts ────────────────────────────────────────────────────────────
    let totalClasses: Int
    let finalClasses: Int
    let totalStructs: Int
    let totalProtocols: Int
    let totalEnums: Int
    let totalActors: Int

    // Inheritance
    let maxInheritanceDepth: Int
    let avgInheritanceDepth: Double
    let deepInheritanceCount: Int       // depth ≥ 3
    let nsObjectCount: Int              // classes inheriting NSObject

    // Behavior
    let overrideCount: Int
    let extensionCount: Int             // extension X { … } on any type

    // Enum design
    let enumsWithAssocValues: Int

    // Protocol quality
    let protocolExtWithCode: Int
    let assocTypeCount: Int
    // Conformance breadth per protocol (Impl-pattern detection)
    let singleConformerProtocols: Int   // exactly 1 conformer → Java Impl pattern = OOP
    let multiConformerProtocols: Int    // 2+ conformers → real protocol capability = POP

    // Protocol composition: `TypeA & TypeB`
    let protocolCompositionCount: Int   // `\b[A-Z]\w* & [A-Z]\w*` pattern

    // `some` — split by target
    let someUserDefinedCount: Int       // `some MyProtocol` where MyProtocol is in this codebase
    let someFrameworkCount: Int         // `some View`, `some Hashable`, etc. — SwiftUI/stdlib

    // Conformance distribution
    let typesWithZeroConformances: Int
    let typesWithOneConformance: Int
    let typesWithTwoPlusConformances: Int

    // Informational (not scored)
    let singletonCount: Int             // static let/var shared / instance
    let genericFuncCount: Int           // func name<T>(...) or type<T>

    // ── Per-metric POP scores [0.0 … 1.0] ────────────────────────────────────

    // PROTOCOL DESIGN (category weight 0.55)
    // totalProtocols == 0: M1·0.60 + M2·0.40  (generics over stdlib still count)
    // totalProtocols > 0:  M1·0.25 + M2·0.15 + M3·0.20 + M4·0.15 + M5·0.10 + M6·0.10 + M7·0.05
    let s_protocolDensity: Double       // M1 W=0.25/0.60 — protocols defined vs types
    let s_genericFunc: Double           // M2 W=0.15/0.40 — constrained generics (always scored)
    let s_conformanceBreadth: Double    // M3 W=0.20 — multi-conformer protocols vs Impl-pattern
    let s_protoExt: Double              // M4 W=0.15 — default impls (proportional / implementedProtos)
    let s_assocType: Double             // M5 W=0.10 — associatedtype (full at 25% adoption)
    let s_someUser: Double              // M6 W=0.10 — `some MyProtocol` user-defined usages
    let s_protoComposition: Double      // M7 W=0.05 — A & B protocol composition

    // VALUE SEMANTICS (category weight 0.30)
    let s_structRatio: Double       // W=0.45 — structs vs classes
    let s_final: Double             // W=0.30 — final classes
    let s_enumAssoc: Double         // W=0.25 — enums with associated values

    // ANTI-INHERITANCE (category weight 0.15)
    let s_inheritDepth: Double      // W=0.40 — lower = POP (inverse)
    let s_overrideDensity: Double   // W=0.35 — fewer = POP (inverse)
    let s_nsObject: Double          // W=0.25 — fewer NSObject = POP (inverse)

    // ── Computed category + overall scores ───────────────────────────────────

    var protoDesignScore: Int {
        totalProtocols == 0
            ? Int((s_protocolDensity*0.60 + s_genericFunc*0.40) * 100)
            : Int((s_protocolDensity*0.25 + s_genericFunc*0.15 + s_conformanceBreadth*0.20 + s_protoExt*0.15 + s_assocType*0.10 + s_someUser*0.10 + s_protoComposition*0.05) * 100)
    }
    var valueSemanticsScore: Int {
        Int((s_structRatio*0.45 + s_final*0.30 + s_enumAssoc*0.25) * 100)
    }
    var antiInheritScore: Int {
        Int((s_inheritDepth*0.40 + s_overrideDensity*0.35 + s_nsObject*0.25) * 100)
    }
    var popScore: Int {
        let p: Double = totalProtocols == 0
            ? s_protocolDensity*0.60 + s_genericFunc*0.40
            : s_protocolDensity*0.25 + s_genericFunc*0.15 + s_conformanceBreadth*0.20 + s_protoExt*0.15 + s_assocType*0.10 + s_someUser*0.10 + s_protoComposition*0.05
        let v = s_structRatio*0.45 + s_final*0.30 + s_enumAssoc*0.25
        let a = s_inheritDepth*0.40 + s_overrideDensity*0.35 + s_nsObject*0.25
        return max(0, min(100, Int((p*0.55 + v*0.30 + a*0.15) * 100)))
    }

    var totalTypes: Int {
        totalClasses + totalStructs + totalProtocols + totalEnums + totalActors
    }
}

// MARK: - Analyzer

struct OOPvsPOPAnalyzer {

    static func analyze(files: [ParsedFile]) -> OOPvsPOPStats {
        let swiftFiles = files.filter { $0.filePath.hasSuffix(".swift") }

        // ── Step 1: zero-I/O declarations pass ───────────────────────────────
        var allClassNames    = Set<String>()
        var allProtocolNames = Set<String>()
        var totalStructs  = 0
        var totalEnums    = 0
        var totalActors   = 0

        for file in swiftFiles {
            for decl in file.declarations {
                switch decl.kind {
                case .class:    allClassNames.insert(decl.name)
                case .struct:   totalStructs  += 1
                case .protocol: allProtocolNames.insert(decl.name)
                case .enum:     totalEnums    += 1
                case .actor:    totalActors   += 1
                case .extension: break
                }
            }
        }

        // ── Step 2: parallel content scan ────────────────────────────────────
        var finalClassesAcc  = 0
        var nsObjectAcc      = 0
        var overrideAcc      = 0
        var extensionAcc     = 0
        var parentMapAcc: [String: String] = [:]
        var conformancesAcc: [Int] = []         // per-type conformance counts
        var protoExtAcc      = 0
        var assocTypeAcc     = 0
        var protoConformersAcc: [String: Int] = [:]   // protocol name → count of conforming types
        var someUserAcc      = 0
        var someFrameAcc     = 0
        var protoCompositionAcc = 0
        var enumAssocAcc     = 0
        var singletonAcc     = 0
        var genericFuncAcc   = 0
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: swiftFiles.count) { idx in
            let filePath = swiftFiles[idx].filePath
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
            let lines = content.components(separatedBy: "\n")

            guard
                let classRe = try? NSRegularExpression(
                    pattern: #"^\s*((?:(?:public|internal|private|fileprivate|open|final)\s+)*)class\s+([A-Z]\w*)(?:\s*<[^>]+>)?\s*(?::\s*([^\{]+))?"#
                ),
                let structRe = try? NSRegularExpression(
                    pattern: #"^\s*(?:(?:public|internal|private|fileprivate)\s+)*struct\s+[A-Z]\w*(?:\s*<[^>]+>)?\s*(?::\s*([^\{]+))?"#
                ),
                let extRe = try? NSRegularExpression(
                    pattern: #"^\s*extension\s+(\w+)"#
                ),
                let someRe = try? NSRegularExpression(
                    pattern: #"\bsome\s+(\w+)"#
                ),
                let constrainedGenericRe = try? NSRegularExpression(
                    // inline: func name<T: Protocol> (uppercase after :); where clause: where T: Protocol
                    pattern: #"\bfunc\s+\w+\s*<[^>]*:\s*[A-Z]|\bwhere\s+\w+\s*:\s*[A-Z]"#
                ),
                let protoCompositionRe = try? NSRegularExpression(
                    pattern: #"\b[A-Z]\w*\s*&\s*[A-Z]\w*"#
                )
            else { return }

            var localFinal    = 0
            var localNSObject = 0
            var localOverride = 0
            var localExt      = 0
            var localParents: [(String, String)] = []
            var localConforms: [Int] = []
            var localProtoExt = 0
            var localAssoc    = 0
            var localProtoConformers: [String: Int] = [:]
            var localSomeUser = 0
            var localSomeFrame = 0
            var localProtoComposition = 0
            var localEnumAssoc = 0
            var localSingleton = 0
            var localGenericFunc = 0

            for (lineIdx, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") || t.hasPrefix("*") || t.hasPrefix("/*") { continue }
                let code = stripStrings(line)
                let range = NSRange(code.startIndex..., in: code)

                // ── class declaration ──────────────────────────────────────
                if let m = classRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let nameRange = Range(m.range(at: 2), in: line) {
                    let className = String(line[nameRange])
                    if let pfx = Range(m.range(at: 1), in: line),
                       String(line[pfx]).contains("final") { localFinal += 1 }

                    if let cr = Range(m.range(at: 3), in: line) {
                        let parts = parseConformances(String(line[cr]))
                        var hasClassParent = false
                        if let first = parts.first {
                            if first == "NSObject" {
                                localNSObject += 1
                                hasClassParent = true
                            } else if allClassNames.contains(first) {
                                localParents.append((className, first))
                                hasClassParent = true
                            } else if !allProtocolNames.contains(first) {
                                // Not a user-defined protocol → framework superclass
                                // (UIViewController, ObservableObject, etc.)
                                hasClassParent = true
                            }
                        }
                        // Protocol conformances only — exclude the superclass slot
                        let protoConformanceCount = parts.count - (hasClassParent ? 1 : 0)
                        localConforms.append(protoConformanceCount)
                        for part in parts where allProtocolNames.contains(part) {
                            localProtoConformers[part, default: 0] += 1
                        }
                    } else {
                        localConforms.append(0)
                    }
                }

                // ── struct declaration ─────────────────────────────────────
                if let sm = structRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if let cr = Range(sm.range(at: 1), in: line) {
                        let parts = parseConformances(String(line[cr]))
                        localConforms.append(parts.count)
                        for part in parts where allProtocolNames.contains(part) {
                            localProtoConformers[part, default: 0] += 1
                        }
                    } else {
                        localConforms.append(0)
                    }
                }

                // ── extension (any type) ───────────────────────────────────
                if t.hasPrefix("extension "),
                   let em = extRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    localExt += 1
                    // Protocol extension with body code
                    if let nr = Range(em.range(at: 1), in: line),
                       allProtocolNames.contains(String(line[nr])) {
                        let slice = lines[min(lineIdx+1, lines.count-1)..<min(lineIdx+6, lines.count)]
                        if slice.contains(where: {
                            let lt = $0.trimmingCharacters(in: .whitespaces)
                            return !lt.isEmpty && lt != "}" && !lt.hasPrefix("//")
                        }) { localProtoExt += 1 }
                    }
                }

                // ── override ───────────────────────────────────────────────
                if t.hasPrefix("override ") { localOverride += 1 }

                // ── associatedtype ─────────────────────────────────────────
                if t.hasPrefix("associatedtype ") { localAssoc += 1 }

                // ── enum cases with associated values ──────────────────────
                // `case Foo(...)` (no leading dot → enum declaration, not switch case)
                if t.hasPrefix("case ") && !t.hasPrefix("case .") && !t.hasPrefix("case let") && !t.hasPrefix("case var") {
                    let afterCase = t.dropFirst(5)
                    if afterCase.contains("(") { localEnumAssoc += 1 }
                }

                // ── some P / P & Q — split user-defined vs framework ───────
                var matchRange = range
                while let m = someRe.firstMatch(in: code, range: matchRange) {
                    if let nr = Range(m.range(at: 1), in: code) {
                        let name = String(code[nr])
                        if allProtocolNames.contains(name) { localSomeUser += 1 }
                        else { localSomeFrame += 1 }
                    }
                    let newStart = m.range.upperBound
                    let newLen   = range.upperBound - newStart
                    if newLen <= 0 { break }
                    matchRange = NSRange(location: newStart, length: newLen)
                }
                // Protocol composition: `TypeA & TypeB` (capitalised names either side)
                if protoCompositionRe.firstMatch(in: code, range: range) != nil { localProtoComposition += 1 }

                // ── constrained generic functions ──────────────────────────
                if constrainedGenericRe.firstMatch(in: code, range: range) != nil { localGenericFunc += 1 }

                // ── singletons ─────────────────────────────────────────────
                if code.contains("static let shared") || code.contains("static var shared") ||
                   code.contains("static let instance") || code.contains("static var instance") {
                    localSingleton += 1
                }
            }

            lock.lock()
            finalClassesAcc   += localFinal
            nsObjectAcc       += localNSObject
            overrideAcc       += localOverride
            extensionAcc      += localExt
            for (child, parent) in localParents { parentMapAcc[child] = parent }
            conformancesAcc.append(contentsOf: localConforms)
            protoExtAcc       += localProtoExt
            assocTypeAcc      += localAssoc
            for (proto, count) in localProtoConformers {
                protoConformersAcc[proto, default: 0] += count
            }
            someUserAcc          += localSomeUser
            someFrameAcc         += localSomeFrame
            protoCompositionAcc  += localProtoComposition
            enumAssocAcc      += localEnumAssoc
            singletonAcc      += localSingleton
            genericFuncAcc    += localGenericFunc
            lock.unlock()
        }

        // ── Inheritance depth ─────────────────────────────────────────────────
        func depth(of name: String, visited: inout Set<String>) -> Int {
            if visited.contains(name) { return 0 }
            visited.insert(name)
            guard let parent = parentMapAcc[name] else { return 1 }
            return 1 + depth(of: parent, visited: &visited)
        }
        var depths: [Int] = []
        for cls in allClassNames where parentMapAcc[cls] != nil {
            var vis = Set<String>()
            depths.append(depth(of: cls, visited: &vis))
        }
        let maxDepth  = depths.max() ?? 1
        let avgDepth  = depths.isEmpty ? 1.0 : Double(depths.reduce(0, +)) / Double(depths.count)
        let deepCount = depths.filter { $0 >= 3 }.count

        let totalClasses   = allClassNames.count
        let totalProtocols = allProtocolNames.count

        // Conformance distribution
        let zeroConform = conformancesAcc.filter { $0 == 0 }.count
        let oneConform  = conformancesAcc.filter { $0 == 1 }.count
        let twoPlusConform = conformancesAcc.filter { $0 >= 2 }.count
        // ── Per-metric scores [0.0 … 1.0] ────────────────────────────────────
        let totalNonProto = totalClasses + totalStructs

        // PROTOCOL DESIGN ─────────────────────────────────────────────────────

        // s_protocolDensity: 1 protocol per 4 non-protocol types = full score
        let s_protocolDensity: Double = totalNonProto > 0
            ? min(Double(totalProtocols) / Double(totalNonProto) * 4.0, 1.0)
            : (totalProtocols > 0 ? 1.0 : 0.0)

        // s_conformanceBreadth: among implemented protocols, fraction with 2+ conformers
        let singleConformerProtos = protoConformersAcc.values.filter { $0 == 1 }.count
        let multiConformerProtos  = protoConformersAcc.values.filter { $0 >= 2 }.count
        let implementedProtos     = singleConformerProtos + multiConformerProtos
        let s_conformanceBreadth: Double = implementedProtos > 0
            ? Double(multiConformerProtos) / Double(implementedProtos)
            : 0.0

        // s_protoExt: proportional over implemented protocols (avoids punishing unused abstract ones)
        let s_protoExt: Double = implementedProtos > 0
            ? min(Double(protoExtAcc) / Double(implementedProtos), 1.0)
            : 0.0

        // s_assocType: full score at 25% adoption (associatedtype is an advanced feature)
        let s_assocType: Double = totalProtocols > 0
            ? min(Double(assocTypeAcc) / Double(max(totalProtocols / 4, 1)), 1.0)
            : 0.0

        // s_someUser: 1 some-usage per protocol = full score
        let s_someUser: Double = totalProtocols > 0
            ? min(Double(someUserAcc) / Double(totalProtocols), 1.0)
            : 0.0

        // s_protoComposition: 1 A & B usage per 2 protocols = full score
        let s_protoComposition: Double = totalProtocols > 0
            ? min(Double(protoCompositionAcc) / Double(max(totalProtocols / 2, 1)), 1.0)
            : 0.0

        // s_genericFunc: 1 constrained generic per 5 non-proto types = full score
        let s_genericFunc: Double = totalNonProto > 0
            ? min(Double(genericFuncAcc) / Double(max(totalNonProto / 5, 1)), 1.0)
            : 0.5

        // VALUE SEMANTICS ─────────────────────────────────────────────────────

        // s_structRatio: structs / (structs + classes)
        let s_structRatio: Double = (totalStructs + totalClasses) > 0
            ? Double(totalStructs) / Double(totalStructs + totalClasses)
            : 0.5

        // s_final: capped at 1.0 to prevent >100% display
        let s_final: Double = totalClasses > 0
            ? min(Double(min(finalClassesAcc, totalClasses)) / Double(totalClasses), 1.0)
            : 0.5

        // s_enumAssoc: 30% of enums with associated values = full score; no enums → neutral
        let s_enumAssoc: Double = totalEnums > 0
            ? min(Double(enumAssocAcc) / Double(max(Int(Double(totalEnums) * 0.3), 1)), 1.0)
            : 0.5

        // ANTI-INHERITANCE ────────────────────────────────────────────────────

        // s_inheritDepth: lower avg = POP (inverse)
        let s_inheritDepth: Double = 1.0 - min(max(avgDepth - 1.0, 0) / 4.0, 1.0)

        // s_overrideDensity: fewer overrides per class = POP (inverse); no classes → neutral
        let s_overrideDensity: Double = totalClasses > 0
            ? max(1.0 - Double(overrideAcc) / Double(totalClasses * 3), 0.0)
            : 0.5

        // s_nsObject: fewer NSObject subclasses = POP (inverse)
        let s_nsObject: Double = totalClasses > 0
            ? max(1.0 - Double(nsObjectAcc) / Double(totalClasses), 0.0)
            : 0.5

        return OOPvsPOPStats(
            totalClasses: totalClasses,
            finalClasses: min(finalClassesAcc, totalClasses),
            totalStructs: totalStructs,
            totalProtocols: totalProtocols,
            totalEnums: totalEnums,
            totalActors: totalActors,
            maxInheritanceDepth: maxDepth,
            avgInheritanceDepth: avgDepth,
            deepInheritanceCount: deepCount,
            nsObjectCount: nsObjectAcc,
            overrideCount: overrideAcc,
            extensionCount: extensionAcc,
            enumsWithAssocValues: enumAssocAcc,
            protocolExtWithCode: protoExtAcc,
            assocTypeCount: assocTypeAcc,
            singleConformerProtocols: singleConformerProtos,
            multiConformerProtocols: multiConformerProtos,
            protocolCompositionCount: protoCompositionAcc,
            someUserDefinedCount: someUserAcc,
            someFrameworkCount: someFrameAcc,
            typesWithZeroConformances: zeroConform,
            typesWithOneConformance: oneConform,
            typesWithTwoPlusConformances: twoPlusConform,
            singletonCount: singletonAcc,
            genericFuncCount: genericFuncAcc,
            s_protocolDensity: s_protocolDensity,
            s_genericFunc: s_genericFunc,
            s_conformanceBreadth: s_conformanceBreadth,
            s_protoExt: s_protoExt,
            s_assocType: s_assocType,
            s_someUser: s_someUser,
            s_protoComposition: s_protoComposition,
            s_structRatio: s_structRatio,
            s_final: s_final,
            s_enumAssoc: s_enumAssoc,
            s_inheritDepth: s_inheritDepth,
            s_overrideDensity: s_overrideDensity,
            s_nsObject: s_nsObject
        )
    }

    // MARK: - Helpers

    private static func stripStrings(_ line: String) -> String {
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
            if c == "\"" { inString.toggle(); result.append(c) }
            else { result.append(inString ? " " : c) }
            idx = line.index(after: idx)
        }
        return result
    }

    private static func parseConformances(_ raw: String) -> [String] {
        let withoutWhere = raw.components(separatedBy: " where ").first ?? raw
        return withoutWhere
            .components(separatedBy: ",")
            .compactMap {
                $0.trimmingCharacters(in: .whitespaces)
                  .components(separatedBy: .whitespaces).first
            }
            .filter { !$0.isEmpty && $0 != "{" }
    }
}
