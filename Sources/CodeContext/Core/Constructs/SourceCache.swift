// Exey Panteleev
// Reads each Swift source file from disk exactly once and shares the result
// across every construct detector (design patterns, data structures,
// algorithms, complexity, magic constants). Previously each detector re-read
// the entire tree independently, and separately re-implemented its own
// per-line comment/string stripping — five near-identical copies that all
// shared the same blind spot: state reset at every line meant a `"""`
// multi-line string or a `/* */` block comment spanning several lines was
// invisible past its first line, so embedded JSON/prose inside one could be
// scanned as if it were real code. Stripping now runs once per file, as a
// single stateful pass over the whole text, and every detector reads the
// result from here instead of stripping its own copy.
import Foundation

/// One file's source, held in the shapes detectors need: `lines`/`text` for
/// callers that want the untouched original, and `strippedLines`/
/// `stringLiteralsByLine` for callers scanning code shape (comments and
/// string contents removed, so a doc comment or log message never
/// contributes a signal).
struct SourceCache {

    struct Entry {
        let lines: [String]                    // file contents split on "\n"
        let text: String                       // full file contents, for `contains` probes
        let strippedLines: [String]             // `lines`, with comments/string contents removed
        let stringLiteralsByLine: [[String]]    // contents of each single-line "..." literal, by line
    }

    private let entries: [String: Entry]

    /// Concurrently reads every distinct `.swift` path referenced by `files`.
    /// Files that can't be read are simply absent from the cache — callers
    /// treat a miss the same as the old `try?` failure (skip that file).
    init(files: [ParsedFile]) {
        // A path can appear more than once across package groupings; de-dup so a
        // shared file is read (and stored) exactly once.
        let uniquePaths = Array(Set(files.compactMap {
            $0.filePath.hasSuffix(".swift") ? $0.filePath : nil
        }))

        // Write through UnsafeMutableBufferPointer so concurrent writes to
        // distinct indices don't race through Swift's COW Array machinery
        // (same idiom the detectors used for their own scans).
        var buf = [(String, Entry)?](repeating: nil, count: uniquePaths.count)
        buf.withUnsafeMutableBufferPointer { p in
            DispatchQueue.concurrentPerform(iterations: uniquePaths.count) { idx in
                let fp = uniquePaths[idx]
                guard let text = try? String(contentsOfFile: fp, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: "\n")
                let stripped = Self.strip(text)
                p[idx] = (fp, Entry(lines: lines, text: text,
                                    strippedLines: stripped.lines,
                                    stringLiteralsByLine: stripped.strings))
            }
        }

        var dict = [String: Entry](minimumCapacity: uniquePaths.count)
        for case let entry? in buf { dict[entry.0] = entry.1 }
        self.entries = dict
    }

    /// Lines of `path`, or nil if the file was unreadable / not a `.swift` file.
    func lines(_ path: String) -> [String]? { entries[path]?.lines }

    /// Full text of `path`, or nil if the file was unreadable / not a `.swift` file.
    func text(_ path: String) -> String? { entries[path]?.text }

    /// `lines(path)` with `//` and `/* */` comments and every string literal's
    /// contents removed (quote delimiters dropped too) — braces, keywords, and
    /// identifiers are untouched, so brace-matching and structural scans see
    /// only code shape. Multi-line block comments and `"""`-strings are
    /// tracked correctly across line boundaries, unlike a per-line stripper.
    func strippedLines(_ path: String) -> [String]? { entries[path]?.strippedLines }

    /// `strippedLines(path)` joined back into one string, for callers that want
    /// a single `content.contains(...)` probe instead of a per-line scan.
    func strippedText(_ path: String) -> String? {
        entries[path].map { $0.strippedLines.joined(separator: "\n") }
    }

    /// The contents of every single-line `"..."` string literal on each line
    /// of `path` (index-aligned with `lines`/`strippedLines`). Triple-quoted
    /// strings are deliberately excluded — there's no single line to
    /// attribute a multi-line literal's contents to, and every real caller of
    /// this (matching a short constant string like ChaCha's "expand
    /// 32-byte k") only ever needs the single-line form anyway.
    func stringLiterals(_ path: String) -> [[String]]? { entries[path]?.stringLiteralsByLine }

    // MARK: - Stateful strip

    private struct Stripped { let lines: [String]; let strings: [[String]] }

    private enum StripState {
        case code
        case lineComment
        case blockComment(Int)   // nesting depth — Swift block comments nest
        case string
        case tripleString
    }

    /// One pass over the whole file, character by character, carrying comment/
    /// string state across line boundaries (the thing a per-line stripper
    /// structurally cannot do). A backslash immediately before a newline is
    /// never treated as escaping that newline — consuming it there would
    /// desync `strippedLines`' line count from `lines`, corrupting every
    /// line-number a detector reports downstream.
    private static func strip(_ text: String) -> Stripped {
        var state: StripState = .code
        var strippedOut: [[Character]] = [[]]
        var stringsOut: [[String]] = [[]]
        var currentString: [Character] = []
        let chars = Array(text)
        var i = 0

        func startNewLine() {
            strippedOut.append([])
            stringsOut.append([])
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" {
                switch state {
                case .lineComment:
                    state = .code
                case .string:
                    // Unterminated single-line string at end-of-line — reset
                    // defensively rather than let one malformed/edge-case line
                    // swallow the rest of the file as "inside a string".
                    state = .code
                    currentString = []
                default:
                    break
                }
                startNewLine()
                i += 1
                continue
            }
            switch state {
            case .code:
                if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    state = .lineComment; i += 2; continue
                }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    state = .blockComment(1); i += 2; continue
                }
                if c == "\"" {
                    if i + 2 < chars.count, chars[i + 1] == "\"", chars[i + 2] == "\"" {
                        state = .tripleString; i += 3; continue
                    }
                    state = .string; currentString = []; i += 1; continue
                }
                strippedOut[strippedOut.count - 1].append(c)
                i += 1
            case .lineComment:
                i += 1
            case .blockComment(let depth):
                if c == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                    state = depth <= 1 ? .code : .blockComment(depth - 1)
                    i += 2; continue
                }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    state = .blockComment(depth + 1); i += 2; continue
                }
                i += 1
            case .string:
                if c == "\\", i + 1 < chars.count, chars[i + 1] != "\n" {
                    currentString.append(c); currentString.append(chars[i + 1]); i += 2; continue
                }
                if c == "\"" {
                    stringsOut[stringsOut.count - 1].append(String(currentString))
                    currentString = []
                    state = .code
                    i += 1; continue
                }
                currentString.append(c)
                i += 1
            case .tripleString:
                if c == "\\", i + 1 < chars.count, chars[i + 1] != "\n" {
                    i += 2; continue
                }
                if c == "\"", i + 2 < chars.count, chars[i + 1] == "\"", chars[i + 2] == "\"" {
                    state = .code; i += 3; continue
                }
                i += 1
            }
        }

        return Stripped(lines: strippedOut.map { String($0) }, strings: stringsOut)
    }
}
