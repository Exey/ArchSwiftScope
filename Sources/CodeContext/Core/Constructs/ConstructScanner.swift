// Exey Panteleev
// The single scanning core for code-construct detection. Owns the one shared
// SourceCache read and drives every construct detector (design patterns, data
// structures, algorithms) from it, returning one results bundle.
//
// ─── Adding a new detector ───────────────────────────────────────────────────
// This is the one place new detectors plug in. To add one:
//   1. Give it a `detect(files:cache:) -> [YourMatch]` method (take the shared
//      `SourceCache`; never read files from disk yourself).
//   2. Add a `yourMatches` field to `Results`.
//   3. Add one line to `scan(files:)` invoking it.
// Everything else — the single disk read, the caller wiring — is already here.
import Foundation

struct ConstructScanner {

    /// Everything the construct detectors found in one pass. New detectors add a
    /// field here (see the header note).
    struct Results {
        let patterns: [DetectedDesignPattern]
        let dataStructures: [DSMatch]
        let algorithms: [AlgoMatch]
        let complexity: ComplexityReport
        let magicConstants: [ConstantMatch]

        static let empty = Results(
            patterns: [], dataStructures: [], algorithms: [],
            complexity: ComplexityReport(usage: CollectionUsage(), timeViolations: [],
                                         spaceViolations: [], timeHealth: 100, spaceHealth: 100),
            magicConstants: [])
    }

    /// Builds the shared source cache once, then runs every detector against it.
    /// `log` receives one human-readable line per detector that found anything
    /// (the caller decides how/whether to print it).
    func scan(files: [ParsedFile], log: (String) -> Void = { _ in }) -> Results {
        // One read of every source file, shared by all detectors below —
        // replaces the independent full-tree re-reads they used to each do.
        let cache = SourceCache(files: files)

        let patterns = DesignPatternDetector().detect(files: files, cache: cache)
        if !patterns.isEmpty {
            log("Design patterns: \(patterns.count) detected (\(patterns.map(\.name).joined(separator: ", ")))")
        }

        let dataStructures = DataStructureDetector().detect(files: files, cache: cache)
        if !dataStructures.isEmpty {
            log("Data structures: \(dataStructures.count) detected")
        }

        let algorithms = AlgorithmDetector().detect(files: files, cache: cache)
        if !algorithms.isEmpty {
            log("Algorithms: \(algorithms.count) detected")
        }

        let complexity = ComplexityDetector().detect(files: files, cache: cache)
        if !complexity.timeViolations.isEmpty || !complexity.spaceViolations.isEmpty {
            log("Complexity: time \(complexity.timeHealth)/100 (\(complexity.timeViolations.count) hotspots) · space \(complexity.spaceHealth)/100 (\(complexity.spaceViolations.count))")
        }

        let magicConstants = MagicConstantDetector().detect(files: files, cache: cache)
        if !magicConstants.isEmpty {
            log("Magic constants: \(magicConstants.count) detected")
        }

        return Results(patterns: patterns, dataStructures: dataStructures,
                       algorithms: algorithms, complexity: complexity,
                       magicConstants: magicConstants)
    }
}
