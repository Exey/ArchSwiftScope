// Exey Panteleev
// Big-O Complexity Health — a heuristic reading of how the codebase works with
// the classic collections (Array, Dictionary, Set, Sequence). It counts their
// usage and estimates per-function complexity from iteration nesting:
//   · nested loops (for / while / repeat)
//   · higher-order iteration closures (.map / .filter / .reduce / .forEach / …)
//   · linear collection ops used inside a loop (.sorted / .filter / .first(where:) / …)
// A function whose deepest simultaneous iteration nesting is N levels is charged
// O(Nⁿ); anything O(N²) or worse is reported as a violation with a source link.
// Space is the same idea applied to collection allocations that happen inside a
// loop. Everything here is an approximation, surfaced as "health", not proof.
import Foundation

// MARK: - Models

struct CollectionUsage {
    var array = 0
    var dictionary = 0
    var set = 0
    var sequence = 0
    var lazy = 0               // .lazy usage — a modifier on the collections above, not its own category
    var total: Int { array + dictionary + set + sequence }
    var isEmpty: Bool { total == 0 }
}

struct ComplexityViolation {
    let symbol: String        // enclosing function / type
    let filePath: String
    let line: Int             // 1-based
    let module: String
    let order: Int            // 2 = O(N²), 3 = O(N³), …
    let reason: String

    var bigO: String {
        switch order {
        case ...1: return "O(N)"
        default:   return "O(N\(exponentChar))"
        }
    }

    /// The exponent alone (empty for O(N), where there's nothing to superscript),
    /// so callers can style the power distinctly from the rest of the badge.
    var exponentChar: String {
        switch order {
        case ...1: return ""
        case 2:    return "²"
        case 3:    return "³"
        case 4:    return "⁴"
        default:   return "ⁿ"
        }
    }
}

struct ComplexityReport {
    let usage: CollectionUsage
    let timeViolations: [ComplexityViolation]
    let spaceViolations: [ComplexityViolation]
    let timeHealth: Int       // 0–100
    let spaceHealth: Int      // 0–100
    var hasData: Bool { !usage.isEmpty || !timeViolations.isEmpty || !spaceViolations.isEmpty }
}

// MARK: - Detector

struct ComplexityDetector {

    func detect(files: [ParsedFile], cache: SourceCache) -> ComplexityReport {
        let swiftFiles = files.filter { $0.filePath.hasSuffix(".swift") }
        let moduleMap: [String: String] = Dictionary(uniqueKeysWithValues: files.map {
            ($0.filePath, $0.packageName.isEmpty ? $0.moduleName : $0.packageName)
        })

        var usage = CollectionUsage()
        var timeCandidates: [ComplexityViolation] = []
        var spaceCandidates: [ComplexityViolation] = []
        var iterationScopes = Set<String>()   // (file,symbol) that contain ≥1 loop

        for file in swiftFiles {
            guard let strippedLines = cache.strippedLines(file.filePath) else { continue }
            let mod = moduleMap[file.filePath] ?? ""
            Self.analyze(strippedLines: strippedLines, filePath: file.filePath, module: mod,
                         usage: &usage, time: &timeCandidates, space: &spaceCandidates,
                         iterationScopes: &iterationScopes)
        }

        // Dedup to one violation per (file, symbol): keep the worst order, and
        // among equal orders the first (structural) reason.
        let timeViolations = Self.dedup(timeCandidates)
        let spaceViolations = Self.dedup(spaceCandidates)

        // Health = share of loop-bearing functions that stay O(N) or better.
        // A density (not an absolute penalty) so the score means the same thing
        // in a 5-file tool and a 5,000-file monorepo instead of flooring to 0.
        let timeHealth = Self.cleanRatioHealth(violating: timeViolations.count, ofScopes: iterationScopes.count)
        let spaceHealth = Self.cleanRatioHealth(violating: spaceViolations.count, ofScopes: iterationScopes.count)

        return ComplexityReport(usage: usage,
                                timeViolations: timeViolations,
                                spaceViolations: spaceViolations,
                                timeHealth: timeHealth,
                                spaceHealth: spaceHealth)
    }

    // MARK: Aggregation

    private static func dedup(_ cands: [ComplexityViolation]) -> [ComplexityViolation] {
        var best: [String: ComplexityViolation] = [:]
        for c in cands {
            let key = c.filePath + "\u{1}" + c.symbol
            if let cur = best[key], cur.order >= c.order { continue }
            best[key] = c
        }
        return best.values.sorted {
            if $0.order != $1.order { return $0.order > $1.order }
            if $0.symbol != $1.symbol { return $0.symbol < $1.symbol }
            return $0.line < $1.line
        }
    }

    private static func cleanRatioHealth(violating: Int, ofScopes total: Int) -> Int {
        guard total > 0 else { return 100 }
        let clean = max(0, total - violating)
        return Int((Double(clean) / Double(total) * 100).rounded())
    }

    // MARK: - Per-file structural analysis

    private struct Frame { let isLoop: Bool; let name: String? }
    private enum BraceRole { case loop(String); case named(String); case other }

    /// `strippedLines` must already be comment/string stripped (SourceCache.strippedLines).
    private static func analyze(strippedLines: [String], filePath: String, module: String,
                                usage: inout CollectionUsage,
                                time: inout [ComplexityViolation],
                                space: inout [ComplexityViolation],
                                iterationScopes: inout Set<String>) {
        var stack: [Frame] = []
        // Text since the last brace/`;` boundary that never resolved on its own
        // line — a multi-line `func foo(\n  a: Int,\n  b: Int\n) {` classifies
        // as `.other` (its segment is just ") ") without this, so the frame
        // never gets a name and every violation inside falls back to whatever
        // enclosing symbol exists (or "(top level)"). Carried across lines the
        // same way AlgorithmDetector's `pendingLoop` carries a loop keyword
        // whose `{` lands on a later line.
        var pendingSegment = ""

        func loopDepth() -> Int { stack.reduce(0) { $0 + ($1.isLoop ? 1 : 0) } }
        func currentSymbol() -> String { stack.last(where: { $0.name != nil })?.name ?? "(top level)" }

        for (li, line) in strippedLines.enumerated() {
            if line.isEmpty { continue }
            countCollections(line, into: &usage)

            let depthAtStart = loopDepth()

            // Linear collection op sitting inside a loop → effectively one level
            // deeper for this statement (e.g. `for x in a { b.sorted() }`).
            if depthAtStart >= 1, let op = linearOp(in: line) {
                time.append(ComplexityViolation(symbol: currentSymbol(), filePath: filePath,
                                                line: li + 1, module: module,
                                                order: depthAtStart + 1,
                                                reason: "\(op) inside loop"))
            }
            // Collection allocated inside a loop → grows space per iteration.
            if depthAtStart >= 1, let alloc = allocation(in: line) {
                space.append(ComplexityViolation(symbol: currentSymbol(), filePath: filePath,
                                                 line: li + 1, module: module,
                                                 order: depthAtStart + 1,
                                                 reason: "allocates \(alloc) inside loop"))
            }

            // Walk braces, classifying each opener by the text since the last
            // brace boundary — on this line, or carried over from prior lines
            // via `pendingSegment` if none of those boundaries showed up yet.
            var segStart = line.startIndex
            var idx = line.startIndex
            while idx < line.endIndex {
                let ch = line[idx]
                if ch == "{" {
                    let segText = pendingSegment.isEmpty
                        ? String(line[segStart..<idx])
                        : pendingSegment + " " + String(line[segStart..<idx])
                    pendingSegment = ""
                    let role = classify(segText)
                    let isLoop: Bool
                    var label = ""
                    var name: String? = nil
                    switch role {
                    case .loop(let l): isLoop = true; label = l
                    case .named(let n): isLoop = false; name = n
                    case .other: isLoop = false
                    }
                    if isLoop {
                        iterationScopes.insert(filePath + "\u{1}" + currentSymbol())
                        let newDepth = loopDepth() + 1
                        if newDepth >= 2 {
                            time.append(ComplexityViolation(symbol: currentSymbol(), filePath: filePath,
                                                            line: li + 1, module: module,
                                                            order: newDepth, reason: label))
                        }
                    }
                    stack.append(Frame(isLoop: isLoop, name: name))
                    segStart = line.index(after: idx)
                } else if ch == "}" {
                    if !stack.isEmpty { stack.removeLast() }
                    segStart = line.index(after: idx)
                    pendingSegment = ""
                } else if ch == ";" {
                    segStart = line.index(after: idx)
                    pendingSegment = ""
                }
                idx = line.index(after: idx)
            }
            // Nothing since `segStart` resolved into a boundary on this line —
            // e.g. mid-way through a multi-line func signature — so carry it
            // into the next line's classification. Capped defensively: a
            // pathological file that never closes a brace/statement shouldn't
            // make this grow without bound for the rest of the scan.
            if segStart < line.endIndex {
                let leftover = String(line[segStart...])
                let combined = pendingSegment.isEmpty ? leftover : pendingSegment + " " + leftover
                pendingSegment = combined.count > 500 ? String(combined.suffix(500)) : combined
            }
        }
    }

    // MARK: - Line classification

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    private static let reLoopKw    = rx(#"(?<![\w.])(for|while|repeat)(?![\w])"#)
    private static let reControlKw = rx(#"(?<![\w.])(if|guard|switch|else|do|catch)(?![\w])"#)
    private static let reHOF       = rx(#"\.(map|filter|forEach|compactMap|flatMap|reduce|sorted|first|firstIndex|last|contains|allSatisfy|min|max|drop|dropFirst|dropLast|prefix|suffix|partition|split|reversed)(?![\w])[^{}]*$"#)
    private static let reFunc      = rx(#"(?<![\w])func\s+(\w+)"#)
    private static let reInit      = rx(#"(?<![\w])init[?!]?\s*[(<]"#)
    private static let reSubscript = rx(#"(?<![\w])subscript\s*[(<]"#)
    private static let reType      = rx(#"(?<![\w])(?:class|struct|enum|actor|extension)\s+(\w+)"#)
    private static let reComputed  = rx(#"(?<![\w])var\s+(\w+)\s*:\s*[^={]+$"#)

    private static func firstGroup(_ re: NSRegularExpression, _ s: String, group: Int = 1) -> String? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }
    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Classifies the brace whose preceding text (since the last brace/`;`
    /// boundary on the line) is `seg`.
    private static func classify(_ seg: String) -> BraceRole {
        if let kw = firstGroup(reLoopKw, seg) { return .loop("nested \(kw) loop") }
        // A control-flow brace (`if`/`guard`/`switch`/…) is NOT a loop, and it
        // also means any higher-order call on the line was a condition, not a
        // trailing closure — so don't mistake `if a.contains(x) {` for a loop.
        if matches(reControlKw, seg) { return .other }
        if let m = firstGroup(reHOF, seg) { return .loop(".\(m) {} closure") }
        if let n = firstGroup(reFunc, seg) { return .named(n) }
        if matches(reInit, seg) { return .named("init") }
        if matches(reSubscript, seg) { return .named("subscript") }
        if let n = firstGroup(reComputed, seg) { return .named(n) }
        if let n = firstGroup(reType, seg) { return .named(n) }
        return .other
    }

    // Unambiguously-linear collection scans that compound when run inside a
    // loop. Deliberately excludes .map/.reduce/.compactMap/.min/.max: those
    // inside a loop are often over a small, unrelated collection (legitimately
    // O(N+M), not O(N²)), so counting them here over-reports. Their genuinely
    // nested closure forms are still caught structurally by brace nesting.
    private static let linearOps: [(needle: String, label: String)] = [
        (".sorted(", ".sorted()"),
        (".filter(", ".filter()"),
        (".contains(where", ".contains(where:)"),
        (".first(where", ".first(where:)"),
        (".firstIndex(", ".firstIndex()"),
        (".allSatisfy(", ".allSatisfy()"),
    ]
    private static func linearOp(in line: String) -> String? {
        for op in linearOps where line.contains(op.needle) { return op.label }
        return nil
    }

    // Expressions that allocate a fresh collection.
    private static let allocs: [(needle: String, label: String)] = [
        (".map(", "array"), (".map {", "array"), (".map{", "array"),
        (".filter(", "array"), (".filter {", "array"), (".filter{", "array"),
        (".compactMap", "array"), (".flatMap", "array"),
        (".sorted", "array"), (".reversed(", "array"), (".joined(", "string/array"),
        (".reduce(into:", "collection"),
        ("Array(", "Array"), ("Set(", "Set"), ("Dictionary(", "Dictionary"),
        ("= [", "collection literal"),
    ]
    private static func allocation(in line: String) -> String? {
        for a in allocs {
            if a.needle == "= [" {
                if containsAssignmentArrayLiteral(line) { return a.label }
            } else if line.contains(a.needle) {
                return a.label
            }
        }
        return nil
    }

    /// True when `line` contains an assignment to an array literal (`x = []`,
    /// `arr = [1, 2]`) — but not a comparison that merely contains the same
    /// three characters (`x == []`, `x != []`, `x >= []`). The plain substring
    /// "= [" is present in all of those, since "==", "!=", and ">=" each end
    /// in "=" immediately followed by " [".
    private static func containsAssignmentArrayLiteral(_ line: String) -> Bool {
        var from = line.startIndex
        while let r = line.range(of: "= [", range: from..<line.endIndex) {
            let precededByComparisonOp = r.lowerBound > line.startIndex &&
                "=!<>".contains(line[line.index(before: r.lowerBound)])
            if !precededByComparisonOp { return true }
            from = line.index(after: r.lowerBound)
        }
        return false
    }

    // MARK: - Collection usage counting

    private static let reArrayType = rx(#":\s*\[[^:\[\]]+\]|->\s*\[[^:\[\]]+\]"#)
    private static let reDictType  = rx(#":\s*\[[^\[\]]*:[^\[\]]*\]|->\s*\[[^\[\]]*:[^\[\]]*\]"#)
    private static let reArrayTok  = rx(#"(?<![\w])Array(?![\w])"#)
    private static let reDictTok   = rx(#"(?<![\w])Dictionary(?![\w])"#)
    private static let reSetTok    = rx(#"(?<![\w])Set(?![\w])"#)
    private static let reSeqTok    = rx(#"(?<![\w])(?:Sequence|AnySequence|IteratorProtocol)(?![\w])"#)
    // `.lazy` — the property that turns an eager collection chain into a
    // lazily-evaluated one (`array.lazy.map{}.filter{}`). No lookbehind on the
    // `.` needed — that's normal member access and is expected to follow an
    // identifier; only the right boundary matters, to reject `.lazyValue`.
    private static let reLazyTok   = rx(#"\.lazy(?![\w])"#)

    private static func count(_ re: NSRegularExpression, _ s: String) -> Int {
        re.numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    private static func countCollections(_ line: String, into u: inout CollectionUsage) {
        u.array      += count(reArrayTok, line) + count(reArrayType, line)
        u.dictionary += count(reDictTok, line) + count(reDictType, line)
        u.set        += count(reSetTok, line)
        u.sequence   += count(reSeqTok, line)
        u.lazy       += count(reLazyTok, line)
    }

}
