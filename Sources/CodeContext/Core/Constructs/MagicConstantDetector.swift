// Exey Panteleev
// Detects well-known algorithm implementations from the "magic constants" they
// depend on — literal values baked into an algorithm's definition (hash
// primes, checksum polynomials, cryptographic initialization vectors, PRNG
// coefficients) that only ever show up in code implementing that exact
// algorithm. Precision over recall: the constant table intentionally omits
// short/low-entropy literals (e.g. loop trip counts, small seeds) that
// collide with ordinary code, and every literal is matched by numeric value
// (not raw text), so `0x01000193`, `0x1000193`, and `16_777_619` all resolve
// to the same match regardless of how the author formatted it — except values
// under 2^16 (see `lowEntropyThreshold`), which are common enough in ordinary
// code (ports, counts, ids) that only their hex spelling counts as evidence.
import Foundation

// MARK: - Models

struct ConstantMatch {
    let name: String
    let category: AlgoCategory
    var count: Int
    var occurrences: [(symbol: String, filePath: String, line: Int, module: String)]
}

// MARK: - Detector

struct MagicConstantDetector {

    // Every literal maps to the algorithm it uniquely identifies, keyed by
    // decimal value (built from hex below so 0x01000193 and 16777619 are the
    // same table entry). Several cryptographic hashes share their leading
    // initialization words by design (MD5/SHA-1 both descend from the same
    // Merkle–Damgård lineage), so those are labeled jointly rather than
    // guessed apart.
    private static let rawConstants: [(UInt64, String, AlgoCategory)] = [
        // FNV-1 / FNV-1a
        (0x0100_0193, "FNV-1/1a (32-bit prime)", .numeric),
        (0x811c_9dc5, "FNV-1/1a (32-bit offset basis)", .numeric),
        (0x0000_0100_0000_01b3, "FNV-1/1a (64-bit prime)", .numeric),
        (0xcbf2_9ce4_8422_2325, "FNV-1/1a (64-bit offset basis)", .numeric),

        // Checksums
        (0xedb8_8320, "CRC-32 (reflected polynomial)", .numeric),
        (0x04c1_1db7, "CRC-32 (polynomial)", .numeric),
        (0x1edc_6f41, "CRC-32C / Castagnoli (polynomial)", .numeric),
        (0x8005, "CRC-16/IBM (polynomial)", .numeric),
        (0x1021, "CRC-16/CCITT (polynomial)", .numeric),
        (0x42f0_e1eb_a9ea_3693, "CRC-64/XZ (polynomial)", .numeric),

        // MD5 / SHA
        (0x6745_2301, "MD5 / SHA-1 (initialization vector)", .numeric),
        (0xefcd_ab89, "MD5 / SHA-1 (initialization vector)", .numeric),
        (0x98ba_dcfe, "MD5 / SHA-1 (initialization vector)", .numeric),
        (0x1032_5476, "MD5 / SHA-1 (initialization vector)", .numeric),
        (0xc3d2_e1f0, "SHA-1 (initialization vector)", .numeric),
        (0x6a09_e667, "SHA-256 (initialization vector)", .numeric),
        (0xbb67_ae85, "SHA-256 (initialization vector)", .numeric),
        (0x3c6e_f372, "SHA-256 (initialization vector)", .numeric),
        (0xa54f_f53a, "SHA-256 (initialization vector)", .numeric),
        (0x510e_527f, "SHA-256 (initialization vector)", .numeric),
        (0x9b05_688c, "SHA-256 (initialization vector)", .numeric),
        (0x1f83_d9ab, "SHA-256 (initialization vector)", .numeric),
        (0x5be0_cd19, "SHA-256 (initialization vector)", .numeric),

        // PRNGs
        (0x9908_b0df, "Mersenne Twister (MT19937 matrix A)", .numeric),
        (0x6c07_8965, "Mersenne Twister (MT19937 seed step)", .numeric),
        (0x2545_f491_4f6c_dd1d, "xorshift64star", .numeric),
        (0x9e37_79b9, "Fibonacci hashing (32-bit golden ratio)", .numeric),
        (0x9e37_79b9_7f4a_7c15, "Fibonacci hashing / SplitMix64 (64-bit golden ratio)", .numeric),
        (0xbf58_476d_1ce4_e5b9, "SplitMix64 (mix constant)", .numeric),
        (0x94d0_49bb_1331_11eb, "SplitMix64 (mix constant)", .numeric),

        // Non-cryptographic hashes
        (0x5bd1_e995, "MurmurHash2", .numeric),
        (0xcc9e_2d51, "MurmurHash3", .numeric),
        (0x1b87_3593, "MurmurHash3", .numeric),
        (0x85eb_ca6b, "MurmurHash3 (finalizer)", .numeric),
        (0xc2b2_ae35, "MurmurHash3 (finalizer)", .numeric),
        (0xff51_afd7_ed55_8ccd, "MurmurHash3 (64-bit finalizer)", .numeric),
        (0xc4ce_b9fe_1a85_ec53, "MurmurHash3 (64-bit finalizer)", .numeric),
        // djb2's seed (5381) is deliberately absent: it has no natural hex
        // spelling (nobody writes `0x1505`), so it can't be hex-gated the way
        // the low-entropy CRC-16 polynomials below are, and as a bare decimal
        // it's indistinguishable from an ordinary small integer literal.
    ]

    // Below this value a literal is common enough in ordinary code (a port, a
    // count, an id) that decimal form alone isn't evidence — 0x8005 (CRC-16/
    // IBM) and 0x1021 (CRC-16/CCITT) only count as hits when the source
    // actually wrote them in hex. Above it, high-entropy values like the FNV/
    // SHA/Murmur constants are safe to match in either radix.
    private static let lowEntropyThreshold: UInt64 = 1 << 16

    // Duplicate values are possible in principle (e.g. a future MPEG-2 CRC
    // entry shares CRC-32's polynomial) — `uniquingKeysWith` joins the labels
    // instead of trapping the way `uniqueKeysWithValues` would.
    private static let constants: [String: (name: String, category: AlgoCategory)] =
        Dictionary(rawConstants.map { (String($0.0), ($0.1, $0.2)) },
                  uniquingKeysWith: { a, b in (a.0 + " / " + b.0, a.1) })

    // String literals that only ever appear as an algorithm's fixed constant.
    private static let stringConstants: [String: (name: String, category: AlgoCategory)] = [
        "expand 32-byte k": ("ChaCha20 / Salsa20 (256-bit key constant)", .numeric),
        "expand 16-byte k": ("ChaCha20 / Salsa20 (128-bit key constant)", .numeric),
    ]

    // MARK: - Numeric literal extraction

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    // Hex or decimal literal, Swift-style underscores allowed. Boundary
    // lookarounds keep a longer literal or identifier from donating a
    // matching substring (`0x0100_0193` must not also read as `100`), and the
    // trailing `\.[0-9]` lookahead keeps the integer part of a float from
    // being read as a standalone integer literal.
    private static let reNumeric = rx(#"(?<![\w.])(?:0[xX][0-9a-fA-F_]+|[0-9][0-9_]*)(?![\w])(?!\.[0-9])"#)

    private static func numericTokens(in line: String) -> [(value: String, isHex: Bool)] {
        guard line.contains(where: { $0.isNumber }) else { return [] }
        let ns = line as NSString
        let matches = reNumeric.matches(in: line, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { normalizedValue(ns.substring(with: $0.range)) }
    }

    private static func normalizedValue(_ raw: String) -> (value: String, isHex: Bool)? {
        let cleaned = raw.replacingOccurrences(of: "_", with: "")
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
            guard let v = UInt64(cleaned.dropFirst(2), radix: 16) else { return nil }
            return (String(v), true)
        }
        guard let v = UInt64(cleaned) else { return nil }
        return (String(v), false)
    }

    // MARK: - Symbol attribution
    //
    // Brace-matches every `func` declaration to its body range so a hit can
    // be attributed to the innermost enclosing function. Runs on `code`
    // (comments and string contents already stripped), so a brace character
    // inside a string literal never perturbs the count.

    private static func funcRanges(strippedLines: [String]) -> [(name: String, start: Int, end: Int)] {
        var ranges: [(String, Int, Int)] = []
        for (i, line) in strippedLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("func "), let r = trimmed.range(of: "func ") else { continue }
            let after = trimmed[r.upperBound...]
            let name = String(after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
            guard !name.isEmpty, let end = matchBraceEnd(strippedLines: strippedLines, startLine: i) else { continue }
            ranges.append((name, i, end))
        }
        return ranges
    }

    private static func matchBraceEnd(strippedLines: [String], startLine: Int) -> Int? {
        var depth = 0, started = false
        var j = startLine
        while j < strippedLines.count {
            for ch in strippedLines[j] {
                if ch == "{" { depth += 1; started = true }
                else if ch == "}" { depth -= 1 }
            }
            if started && depth <= 0 { return j }
            j += 1
        }
        return started ? strippedLines.count - 1 : nil
    }

    /// True for `*Detector.swift` / `*Analyzer.swift` / `*Scanner.swift` — this
    /// tool's own construct-detection source files, whose job is to spell out
    /// exactly the shapes/literals being searched for. Mirrors
    /// DesignPatternDetector's `contentScanFiles` exclusion.
    private static func isSelfReferential(_ path: String) -> Bool {
        let base = (path as NSString).lastPathComponent
        return base.hasSuffix("Detector.swift") || base.hasSuffix("Analyzer.swift") || base.hasSuffix("Scanner.swift")
    }

    // MARK: - Scan

    func detect(files: [ParsedFile], cache: SourceCache) -> [ConstantMatch] {
        var found: [String: ConstantMatch] = [:]
        let moduleMap: [String: String] = Dictionary(uniqueKeysWithValues: files.map {
            ($0.filePath, $0.packageName.isEmpty ? $0.moduleName : $0.packageName)
        })

        func record(name: String, category: AlgoCategory, symbol: String, path: String, line: Int) {
            let mod = moduleMap[path] ?? ""
            if found[name] == nil {
                found[name] = ConstantMatch(name: name, category: category, count: 0, occurrences: [])
            }
            found[name]!.count += 1
            found[name]!.occurrences.append((symbol: symbol, filePath: path, line: line, module: mod))
        }

        // Same self-trigger exclusion DesignPatternDetector applies to its
        // content scan: this file's own constant table spells out FNV, CRC,
        // MD5/SHA, MT19937, Murmur, djb2, and ChaCha's "expand 32-byte k" in
        // string/numeric literals — scanning this tool's own repo would
        // otherwise "detect" every algorithm in the table, in the one file that
        // implements none of them.
        for file in files where file.filePath.hasSuffix(".swift") && !Self.isSelfReferential(file.filePath) {
            guard let stripped = cache.strippedLines(file.filePath),
                  let stringsByLine = cache.stringLiterals(file.filePath) else { continue }
            let ranges = Self.funcRanges(strippedLines: stripped)

            func symbol(at line: Int) -> String {
                ranges.filter { $0.start <= line && line <= $0.end }
                    .min(by: { ($0.end - $0.start) < ($1.end - $1.start) })?
                    .name ?? "(top level)"
            }

            for (i, code) in stripped.enumerated() {
                for tok in Self.numericTokens(in: code) {
                    guard let hit = Self.constants[tok.value] else { continue }
                    // Below the threshold, decimal form alone isn't distinctive
                    // enough — require the source to have actually written hex.
                    if let v = UInt64(tok.value), v < Self.lowEntropyThreshold, !tok.isHex { continue }
                    record(name: hit.name, category: hit.category, symbol: symbol(at: i), path: file.filePath, line: i + 1)
                }
                for str in stringsByLine[i] {
                    if let hit = Self.stringConstants[str] {
                        record(name: hit.name, category: hit.category, symbol: symbol(at: i), path: file.filePath, line: i + 1)
                    }
                }
            }
        }

        return found.values.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.name < b.name
        }
    }
}
