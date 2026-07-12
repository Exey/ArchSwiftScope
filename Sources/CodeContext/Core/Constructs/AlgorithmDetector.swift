// Exey Panteleev
// Detects well-known algorithm implementations two ways:
//  1. Naming — token-based matching on function/type names (camelCase
//     tokenizer, most-specific rule wins). Mirrors the Go algorithms module.
//  2. Structural fingerprints — name-independent body analysis inspired by
//     algorithm-identification research (tree kernels on ASTs, graph kernels
//     on CFGs): arithmetic shape + control-flow shape + identifier vocabulary
//     must all agree before a match is reported.
import Foundation

// MARK: - Models

enum AlgoCategory: String, CaseIterable {
    case sorting   = "Sorting"
    case searching = "Searching & Selection"
    case graph     = "Graph · Shortest Path · Flow"
    case strMatch  = "String Matching"
    case numeric   = "Numeric & Classic"

    var icon: String {
        switch self {
        case .sorting:   return "🔃"
        case .searching: return "🔍"
        case .graph:     return "🗺️"
        case .strMatch:  return "🔤"
        case .numeric:   return "🧮"
        }
    }
}

struct AlgoMatch {
    let name: String
    let category: AlgoCategory
    var count: Int
    var occurrences: [(symbol: String, filePath: String, line: Int, module: String)]
}

// MARK: - Detector

struct AlgorithmDetector {

    private struct AlgoRule {
        let tokens: [String]
        let joined: String   // tokens concatenated, for run-together spelling check
        let name: String
        let category: AlgoCategory
        let blockers: Set<String>         // if any is present, this rule does NOT match
        let requiredContext: Set<String>  // if non-empty, at least one must ALSO be present

        func matches(tokenSet: Set<String>, joined j: String) -> Bool {
            // Disqualify acronym collisions (e.g. GCD = Grand Central Dispatch, not gcd)
            if !blockers.isEmpty && !blockers.isDisjoint(with: tokenSet) { return false }
            // A blocklist can't enumerate every false-friend context a bare surname
            // collides with (formatYen(), johnson as a plain last name with none of
            // the blocked co-occurring words nearby); requiring positive evidence of
            // the algorithm's own domain is the stronger check for these.
            if !requiredContext.isEmpty && requiredContext.isDisjoint(with: tokenSet) { return false }
            if tokens.allSatisfy({ tokenSet.contains($0) }) { return true }
            // The run-together fallback exists to catch multi-word names written with
            // no case boundary (`quicksort()`), not to substring-match single short
            // tokens/acronyms anywhere inside an unrelated longer identifier — e.g.
            // "loadFSCache" joins to "loadfscache", which contains "dfs" by accident.
            // A single-token rule already gets full recall from the exact-token check
            // above (the tokenizer isolates acronym runs like "BFS" as their own
            // token), so the substring fallback adds only false positives here.
            guard tokens.count > 1 else { return false }
            return j.contains(joined)
        }
    }

    // Tokens that mark an acronym as a false friend rather than the algorithm.
    // "GCD" is overwhelmingly Grand Central Dispatch in Swift/ObjC codebases.
    private static let gcdBlockers: Set<String> = [
        "async", "dispatch", "queue", "socket", "timer", "semaphore", "group",
        "serial", "concurrent", "barrier", "webserver", "server", "web", "legacy",
        "thread", "pool", "scheduler", "udp", "tcp", "main", "global", "worker",
        "connection", "interface", "delegate", "packet", "read", "write", "picker",
    ]

    // Bare single-token rules whose word doubles as a surname, currency code, or
    // an unrelated well-known concept in ordinary app code. Blockers name the
    // co-occurring vocabulary of the false-friend meaning, same idiom as gcdBlockers.
    private static let perRuleBlockers: [Set<String>: Set<String>] = [
        // SimplexNoise is a graphics/procedural-generation staple, not the LP algorithm.
        ["simplex"]: ["noise", "perlin", "terrain", "texture", "procedural", "fractal", "worley"],
        // "yen" the currency appears constantly in money/exchange-rate code.
        ["yen"]: ["currency", "exchange", "rate", "price", "usd", "jpy", "eur", "gbp",
                  "convert", "money", "cost", "fee", "amount", "payment", "wallet", "cart"],
        // "johnson" is a common surname (user/author/contact fields).
        ["johnson"]: ["family", "user", "name", "author", "employee", "contact",
                      "customer", "person", "staff", "account", "first", "last"],
        // "hungarian" is far more often the language/locale/notation than Kahn's algorithm's cousin.
        ["hungarian"]: ["notation", "locale", "language", "translation", "text",
                        "string", "localized", "localization"],
        // "kahn" collides with Khan Academy-style naming and ordinary surnames.
        ["kahn"]: ["academy", "user", "name", "family", "student", "course", "video", "lesson"],
    ]

    // Positive-evidence gate for the same bare-surname rules: a blocklist can
    // only name the false-friend contexts it already knows about (formatYen()
    // has no blocked word nearby at all), so these additionally require the
    // algorithm's own domain vocabulary to co-occur.
    private static let perRuleRequiredContext: [Set<String>: Set<String>] = [
        ["yen"]: ["path", "paths", "graph", "shortest", "route", "routes", "edge", "edges", "node", "nodes"],
        ["johnson"]: ["path", "paths", "shortest", "reweight", "reweighted", "allpairs",
                      "edge", "edges", "graph", "node", "nodes"],
        ["hungarian"]: ["assignment", "matching", "cost", "bipartite", "worker", "workers", "task", "tasks", "assign"],
        ["kahn"]: ["indegree", "indegrees", "topological", "toposort", "dag"],
    ]

    private static let rules: [AlgoRule] = {
        let rawRules: [([String], String, AlgoCategory)] = [
            // ── Sorting ──────────────────────────────────────────────────────
            (["bubble","sort"],             "Bubble Sort",              .sorting),
            (["insertion","sort"],          "Insertion Sort",           .sorting),
            (["selection","sort"],          "Selection Sort",           .sorting),
            (["merge","sort"],              "Merge Sort",               .sorting),
            (["quick","sort"],              "Quicksort",                .sorting),
            (["heap","sort"],               "Heapsort",                 .sorting),
            (["counting","sort"],           "Counting Sort",            .sorting),
            (["radix","sort"],              "Radix Sort",               .sorting),
            (["shell","sort"],              "Shellsort",                .sorting),
            (["bucket","sort"],             "Bucket Sort",              .sorting),
            (["tim","sort"],                "Timsort",                  .sorting),
            (["comb","sort"],               "Comb Sort",                .sorting),
            (["cocktail","sort"],           "Cocktail Shaker Sort",     .sorting),
            (["intro","sort"],              "Introsort",                .sorting),
            (["gnome","sort"],              "Gnome Sort",               .sorting),
            (["pancake","sort"],            "Pancake Sort",             .sorting),
            (["pigeonhole","sort"],         "Pigeonhole Sort",          .sorting),
            (["cycle","sort"],              "Cycle Sort",               .sorting),
            (["odd","even","sort"],         "Odd–Even Sort",            .sorting),
            (["brick","sort"],              "Odd–Even Sort",            .sorting),
            (["strand","sort"],             "Strand Sort",              .sorting),
            (["patience","sort"],           "Patience Sort",            .sorting),
            (["block","sort"],              "Block Sort",               .sorting),
            (["flash","sort"],              "Flashsort",                .sorting),
            (["bitonic","sort"],            "Bitonic Sort",             .sorting),
            (["spread","sort"],             "Spreadsort",               .sorting),
            (["american","flag","sort"],    "American Flag Sort",       .sorting),
            (["burst","sort"],              "Burstsort",                .sorting),
            (["msd","radix"],               "MSD Radix Sort",           .sorting),
            (["lsd","radix"],               "LSD Radix Sort",           .sorting),

            // ── Searching & Selection ────────────────────────────────────────
            (["binary","search"],           "Binary Search",            .searching),
            (["linear","search"],           "Linear Search",            .searching),
            (["sequential","search"],       "Linear Search",            .searching),
            (["interpolation","search"],    "Interpolation Search",     .searching),
            (["jump","search"],             "Jump Search",              .searching),
            (["exponential","search"],      "Exponential Search",       .searching),
            (["ternary","search"],          "Ternary Search",           .searching),
            (["fibonacci","search"],        "Fibonacci Search",         .searching),
            (["quick","select"],            "Quickselect",              .searching),
            (["quickselect"],               "Quickselect",              .searching),
            (["median","of","medians"],     "Median of Medians",        .searching),
            (["introselect"],               "Introselect",              .searching),
            (["saddleback","search"],       "Saddleback Search",        .searching),
            (["meet","in","middle"],        "Meet in the Middle",       .searching),
            (["reservoir","sampling"],       "Reservoir Sampling",      .searching),

            // ── Graph · Shortest Path · Flow ─────────────────────────────────
            (["dijkstra"],                  "Dijkstra",                 .graph),
            (["bellman","ford"],            "Bellman–Ford",             .graph),
            (["floyd","warshall"],          "Floyd–Warshall",           .graph),
            (["astar","search"],            "A* Search",                .graph),
            (["astar","path"],              "A* Search",                .graph),
            (["astar","pathfinding"],       "A* Search",                .graph),
            (["astar","heuristic"],         "A* Search",                .graph),
            (["breadth","first"],           "Breadth-First Search",     .graph),
            (["bfs"],                       "Breadth-First Search",     .graph),
            (["depth","first"],             "Depth-First Search",       .graph),
            (["dfs"],                       "Depth-First Search",       .graph),
            (["kruskal"],                   "Kruskal (MST)",            .graph),
            (["prims"],                     "Prim (MST)",               .graph),
            (["prim","mst"],                "Prim (MST)",               .graph),
            (["prim","spanning"],           "Prim (MST)",               .graph),
            (["topological","sort"],        "Topological Sort",         .graph),
            (["toposort"],                  "Topological Sort",         .graph),
            (["tarjan"],                    "Tarjan (SCC)",             .graph),
            (["kosaraju"],                  "Kosaraju (SCC)",           .graph),
            (["ford","fulkerson"],          "Ford–Fulkerson (Max Flow)",.graph),
            (["edmonds","karp"],            "Edmonds–Karp (Max Flow)",  .graph),
            (["dinic"],                     "Dinic (Max Flow)",         .graph),
            (["push","relabel"],            "Push–Relabel (Max Flow)",  .graph),
            (["hopcroft","karp"],           "Hopcroft–Karp (Matching)", .graph),
            (["hungarian"],                 "Hungarian (Assignment)",   .graph),
            (["johnson"],                   "Johnson (All-Pairs SP)",   .graph),
            (["yen"],                       "Yen (K Shortest Paths)",   .graph),
            (["bidirectional","dijkstra"],  "Bidirectional Dijkstra",   .graph),
            (["boruvka"],                   "Borůvka (MST)",            .graph),
            (["kahn"],                      "Kahn (Topological Sort)",  .graph),
            (["euler","tour"],              "Euler Tour",               .graph),
            (["hierholzer"],                "Hierholzer (Euler Path)",  .graph),
            (["articulation","point"],      "Articulation Points",      .graph),
            (["bridge","finding"],          "Bridge Finding",           .graph),
            (["lowest","common","ancestor"],"Lowest Common Ancestor",   .graph),
            (["strongly","connected"],      "Strongly Connected Components",.graph),
            (["bipartite","matching"],      "Bipartite Matching",       .graph),
            (["max","flow"],                "Maximum Flow",             .graph),
            (["min","cut"],                 "Minimum Cut",              .graph),
            // Tier-1 eponymous graph algorithms — distinctive proper names,
            // near-zero collision. Multi-token pairs require every token present.
            (["bron","kerbosch"],           "Bron–Kerbosch (Max Clique)",   .graph),
            (["gale","shapley"],            "Gale–Shapley (Stable Matching)",.graph),
            (["stable","marriage"],         "Gale–Shapley (Stable Matching)",.graph),
            (["karger"],                    "Karger (Min Cut)",             .graph),
            (["chu","liu"],                 "Chu–Liu/Edmonds (Arborescence)",.graph),
            (["held","karp"],               "Held–Karp (TSP)",              .graph),
            (["christofides"],              "Christofides (TSP)",           .graph),
            (["jump","point","search"],     "Jump Point Search",            .graph),
            (["iddfs"],                     "Iterative Deepening DFS",      .graph),
            (["iterative","deepening"],     "Iterative Deepening DFS",      .graph),
            (["warnsdorff"],                "Warnsdorff (Knight's Tour)",   .graph),
            (["blossom","matching"],        "Blossom (Matching)",           .graph),

            // ── String Matching ──────────────────────────────────────────────
            (["knuth","morris","pratt"],    "Knuth–Morris–Pratt",       .strMatch),
            (["kmp","search"],              "Knuth–Morris–Pratt",       .strMatch),
            (["kmp"],                       "Knuth–Morris–Pratt",       .strMatch),
            (["rabin","karp"],              "Rabin–Karp",               .strMatch),
            (["boyer","moore"],             "Boyer–Moore",              .strMatch),
            (["aho","corasick"],            "Aho–Corasick",             .strMatch),
            (["manacher"],                  "Manacher",                 .strMatch),
            (["z","algorithm"],             "Z-Algorithm",              .strMatch),
            (["suffix","automaton"],        "Suffix Automaton",         .strMatch),
            (["ukkonen"],                   "Ukkonen (Suffix Tree)",    .strMatch),
            (["levenshtein"],               "Levenshtein (Edit Distance)",.strMatch),
            (["edit","distance"],           "Levenshtein (Edit Distance)",.strMatch),
            (["damerau"],                   "Damerau–Levenshtein",      .strMatch),
            (["hamming","distance"],        "Hamming Distance",         .strMatch),
            (["jaro","winkler"],            "Jaro–Winkler",             .strMatch),
            (["soundex"],                   "Soundex",                  .strMatch),
            (["metaphone"],                 "Metaphone",                .strMatch),
            (["longest","common","subsequence"],"Longest Common Subsequence",.strMatch),
            (["longest","common","substring"],"Longest Common Substring",.strMatch),
            (["longest","palindromic"],     "Longest Palindromic Substring",.strMatch),
            (["wildcard","match"],          "Wildcard Matching",        .strMatch),
            // Tier-1 eponymous string / sequence-alignment / parsing algorithms.
            (["bitap"],                     "Bitap",                    .strMatch),
            (["hirschberg"],                "Hirschberg",               .strMatch),
            (["needleman","wunsch"],        "Needleman–Wunsch",         .strMatch),
            (["smith","waterman"],          "Smith–Waterman",           .strMatch),
            (["wagner","fischer"],          "Wagner–Fischer (Edit Distance)",.strMatch),
            (["boyer","moore","horspool"],  "Boyer–Moore–Horspool",     .strMatch),
            (["cyk"],                       "CYK (Parsing)",            .strMatch),
            (["cocke","younger","kasami"],  "CYK (Parsing)",            .strMatch),
            (["earley"],                    "Earley (Parsing)",         .strMatch),

            // ── Numeric & Classic ────────────────────────────────────────────
            (["greatest","common","divisor"],"Euclidean GCD",           .numeric),
            (["euclid","gcd"],              "Euclidean GCD",            .numeric),
            (["euclidean","algorithm"],     "Euclidean GCD",            .numeric),
            (["binary","gcd"],              "Binary GCD (Stein)",       .numeric),
            (["stein","gcd"],               "Binary GCD (Stein)",       .numeric),
            (["gcd"],                       "Euclidean GCD",            .numeric),
            (["least","common","multiple"], "Least Common Multiple",    .numeric),
            (["sieve","eratosthenes"],      "Sieve of Eratosthenes",    .numeric),
            (["eratosthenes"],              "Sieve of Eratosthenes",    .numeric),
            (["miller","rabin"],            "Miller–Rabin Primality",   .numeric),
            (["newton","raphson"],          "Newton–Raphson",           .numeric),
            (["fast","fourier"],            "Fast Fourier Transform",   .numeric),
            (["karatsuba"],                 "Karatsuba Multiplication", .numeric),
            (["binary","exponentiation"],   "Binary Exponentiation",    .numeric),
            (["modular","exponentiation"],  "Binary Exponentiation",    .numeric),
            (["knapsack"],                  "Knapsack (DP)",            .numeric),
            (["kadane"],                    "Kadane (Max Subarray)",    .numeric),
            (["huffman"],                   "Huffman Coding",           .numeric),
            (["fibonacci"],                 "Fibonacci",                .numeric),
            (["extended","euclid"],         "Extended Euclidean",       .numeric),
            (["chinese","remainder"],       "Chinese Remainder Theorem",.numeric),
            (["pollard","rho"],             "Pollard's Rho",            .numeric),
            (["fermat","primality"],        "Fermat Primality",         .numeric),
            (["lucas","lehmer"],            "Lucas–Lehmer",             .numeric),
            (["toom","cook"],               "Toom–Cook Multiplication", .numeric),
            (["schonhage","strassen"],      "Schönhage–Strassen",       .numeric),
            (["strassen"],                  "Strassen Matrix Multiply", .numeric),
            (["gaussian","elimination"],    "Gaussian Elimination",     .numeric),
            (["simplex"],                   "Simplex (LP)",             .numeric),
            (["bresenham"],                 "Bresenham Line",           .numeric),
            (["dda","line"],                "DDA Line",                 .numeric),
            (["convex","hull"],             "Convex Hull",              .numeric),
            (["graham","scan"],             "Graham Scan",              .numeric),
            (["andrew","monotone"],         "Andrew's Monotone Chain",  .numeric),
            (["jarvis","march"],            "Gift Wrapping (Jarvis)",   .numeric),
            (["quick","hull"],              "QuickHull",                .numeric),
            (["voronoi"],                   "Voronoi Diagram",          .numeric),
            (["delaunay"],                  "Delaunay Triangulation",   .numeric),
            (["marching","cubes"],          "Marching Cubes",           .numeric),
            (["marching","squares"],        "Marching Squares",         .numeric),
            (["reservoir","computing"],     "Reservoir Computing",      .numeric),
            (["monte","carlo"],             "Monte Carlo",              .numeric),
            (["metropolis","hastings"],     "Metropolis–Hastings",      .numeric),
            (["gradient","descent"],        "Gradient Descent",         .numeric),
            (["simulated","annealing"],     "Simulated Annealing",      .numeric),
            (["run","length","encoding"],   "Run-Length Encoding",      .numeric),
            (["burrows","wheeler"],         "Burrows–Wheeler Transform",.numeric),
            (["arithmetic","coding"],       "Arithmetic Coding",        .numeric),
            (["lempel","ziv"],              "Lempel–Ziv",               .numeric),
            (["reed","solomon"],            "Reed–Solomon",             .numeric),
            (["viterbi"],                   "Viterbi",                  .numeric),
            (["longest","increasing","subsequence"],"Longest Increasing Subsequence",.numeric),
            (["coin","change"],             "Coin Change (DP)",         .numeric),
            (["matrix","chain"],            "Matrix Chain Multiplication",.numeric),
            // Tier-1 eponymous numeric / geometry / ML / parsing / checksum
            // algorithms — distinctive proper names, near-zero collision.
            (["ramer","douglas","peucker"], "Ramer–Douglas–Peucker",    .numeric),
            (["douglas","peucker"],         "Ramer–Douglas–Peucker",    .numeric),
            (["bowyer","watson"],           "Bowyer–Watson (Delaunay)", .numeric),
            (["cuthill","mckee"],           "Cuthill–McKee",            .numeric),
            (["steinhaus","johnson","trotter"], "Steinhaus–Johnson–Trotter",.numeric),
            (["karplus","strong"],          "Karplus–Strong",           .numeric),
            (["baum","welch"],              "Baum–Welch (HMM)",         .numeric),
            (["hindley","milner"],          "Hindley–Milner (Type Inference)",.numeric),
            (["zeller"],                    "Zeller's Congruence",      .numeric),
            (["luhn"],                      "Luhn (Checksum)",          .numeric),
            (["verhoeff"],                  "Verhoeff (Checksum)",      .numeric),
            (["damm"],                      "Damm (Checksum)",          .numeric),
            (["zobrist"],                   "Zobrist Hashing",          .numeric),
            (["goertzel"],                  "Goertzel",                 .numeric),
            (["ziggurat"],                  "Ziggurat (Sampling)",      .numeric),
            (["q","learning"],              "Q-Learning (RL)",          .numeric),
            (["shunting","yard"],           "Shunting-Yard (Parsing)",  .numeric),
            (["alpha","beta","pruning"],    "Alpha–Beta Pruning",       .numeric),
            (["k","means"],                 "k-means (Clustering)",     .numeric),
            (["k","medoids"],               "k-medoids (Clustering)",   .numeric),
            (["dbscan"],                    "DBSCAN (Clustering)",      .numeric),
            // "AdaBoost" camelCases to ["ada","boost"]; the run-together
            // "adaboost" token only appears when written all-lowercase.
            (["ada","boost"],               "AdaBoost (Boosting)",      .numeric),
            (["adaboost"],                  "AdaBoost (Boosting)",      .numeric),
            (["chudnovsky"],                "Chudnovsky (π)",           .numeric),
            (["tonelli","shanks"],          "Tonelli–Shanks",           .numeric),
            (["berlekamp","massey"],        "Berlekamp–Massey",         .numeric),
            (["cooley","tukey"],            "Cooley–Tukey (FFT)",       .numeric),
            (["freivalds"],                 "Freivalds",                .numeric),
            (["kabsch"],                    "Kabsch",                   .numeric),
            (["levenberg","marquardt"],     "Levenberg–Marquardt",      .numeric),
            (["nelder","mead"],             "Nelder–Mead",              .numeric),
            (["gauss","newton"],            "Gauss–Newton",             .numeric),
            (["bfgs"],                      "BFGS",                     .numeric),
            (["fisher","yates"],            "Fisher–Yates Shuffle",     .numeric),
            (["boyer","moore","majority"],  "Boyer–Moore Majority Vote",.numeric),
            (["schensted"],                 "Robinson–Schensted",       .numeric),
        ]
        let built = rawRules.map { tokens, name, cat -> AlgoRule in
            // The bare "gcd" token collides with Grand Central Dispatch; block it.
            let blockers: Set<String> = (tokens == ["gcd"]) ? gcdBlockers
                : (perRuleBlockers[Set(tokens)] ?? [])
            let requiredContext = perRuleRequiredContext[Set(tokens)] ?? []
            return AlgoRule(tokens: tokens, joined: tokens.joined(), name: name,
                            category: cat, blockers: blockers, requiredContext: requiredContext)
        }
        // Most-specific first: more tokens → longer joined string
        return built.sorted {
            if $0.tokens.count != $1.tokens.count { return $0.tokens.count > $1.tokens.count }
            return $0.joined.count > $1.joined.count
        }
    }()

    // Algorithm-object type kinds (class/struct/actor whose name encodes an algorithm)
    private static let typeKinds: Set<Declaration.Kind> = [.class, .struct, .actor]

    // MARK: - Structural fingerprints
    //
    // Name-independent detection: a function called `arrange(_:)` that swaps
    // adjacent elements inside two nested loops IS bubble sort, whatever its
    // name says. Each rule combines signals from three axes:
    //   · arithmetic shape — normalized expressions ("(lo+hi)/2", "2*i+1")
    //   · control-flow shape — loop nesting depth, self-recursion count
    //   · vocabulary — whole identifier tokens of the body
    // String literals and line comments are stripped before analysis so prose
    // and log messages never count as code. Runs only on functions whose NAME
    // did not already match, so it adds recall without double counting.

    private struct FnFeatures {
        let norm: String          // lowercased body, strings/comments/whitespace stripped
        let spaced: String        // same, but original whitespace preserved — needed
                                   // wherever a regex must tell "while x" (keyword, space
                                   // after) apart from "whileX" (identifier, no space);
                                   // that distinction is unrecoverable once whitespace is
                                   // stripped, since both collapse to the same text in `norm`.
        let tokens: Set<String>   // whole identifier tokens of the body
        let loopNest: Int         // max nesting depth of for/while/repeat
        let selfCalls: Int        // recursive calls to the enclosing function
        var hasLoop: Bool { loopNest >= 1 }
        var loopOrRecursion: Bool { hasLoop || selfCalls >= 1 }
        func any(_ subs: [String]) -> Bool { subs.contains { norm.contains($0) } }
        func tok(_ ts: [String]) -> Bool { ts.contains { tokens.contains($0) } }
    }

    private struct StructuralRule {
        let name: String
        let category: AlgoCategory
        let matches: (FnFeatures) -> Bool
    }

    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p)
    }

    // Compiled once; run against the normalized (whitespace-free) body.
    private static let reAdjCompare  = rx(#"\[(\w+)\][<>]=?[\w.]*\[\1\+1\]"#)   // a[j] > a[j+1]
    private static let reCopyUp      = rx(#"\[(\w+)\]=[\w.]*\[\1\+1\]"#)        // a[j] = a[j+1]
    private static let reShiftUp     = rx(#"\[(\w+)\+1\]=[\w.]*\[\1\]"#)        // a[j+1] = a[j]
    private static let reShiftDown   = rx(#"\[(\w+)\]=[\w.]*\[\1-1\]"#)         // a[j] = a[j-1]
    private static let reTupleSwap   = rx(#"\((\w+),(\w+)\)=\(\2,\1\)"#)        // (a,b) = (b,a)
    private static let reGCDTuple    = rx(#"\((\w+),(\w+)\)=\(\2,\1%\2\)"#)     // (a,b) = (b,a%b)
    // Run against `spaced` (whitespace preserved), not `norm`: a keyword needs
    // \s+ before its operand ("while b") to be told apart from an identifier
    // that merely starts with the same letters ("whileB") — a distinction that
    // whitespace-stripping destroys, since both read as "whileb" in `norm`.
    private static let reWhileNot0   = rx(#"\bwhile\s+(\w+)\s*!=\s*0"#)         // while b != 0
    private static let reRelax       = rx(#"(\w+)\[(\w+)\]\+[\w.\[\]]+?<\1\["#) // dist[u]+w < dist[v]
    private static let reKadane1     = rx(#"(\w+)=max\((\w+),\1\+\2\)"#)        // c = max(x, c+x)
    private static let reKadane2     = rx(#"(\w+)=max\(\1\+(\w+),\2\)"#)        // c = max(c+x, x)
    private static let reHalve       = rx(#"=(middle|mid)(?![\w])"#)            // lo = mid + 1
    private static let reSquare      = rx(#"(\w+)\*\1(?![\w])"#)                // p*p (sieve start)
    private static let reWhileLess   = rx(#"\bwhile\s+(\w+)\s*<\s*(\w+)"#)      // while l < r
    private static let reLoopKeyword = rx(#"(^|[^a-z0-9_])(for|while|repeat)($|[^a-z0-9_])"#)
    // Path-compressed union-find: parent[x] = find(parent[x])
    private static let reUnionFindCompress = rx(#"parent\[(\w+)\]=find\(parent\[\1\]\)"#)
    // Triple-nested matmul accumulation: C[i][j] += A[i][k] * B[k][j] — the three
    // backreferences enforce the exact index-reuse pattern (i shared by C/A, k
    // shared by A/B, j shared by B/C), not just three adjacent bracket pairs.
    private static let reMatMulAssign = rx(#"(\w+)\[(\w+)\]\[(\w+)\]\+=(\w+)\[\2\]\[(\w+)\]\*(\w+)\[\5\]\[\3\]"#)
    // In-place prefix-sum scan: sum[i] += sum[i-1] — the array reads/writes itself.
    private static let rePrefixSum   = rx(#"(\w+)\[(\w+)\]\+=\1\[\2-1\]"#)
    // A delay/backoff variable compound-multiplied by exactly 2 — the
    // self-doubling idiom that defines exponential backoff, not just any "*2".
    private static let reBackoffDouble = rx(#"(\w*delay\w*|\w*backoff\w*)\*=2(?![\w])"#)

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func allCaptures(_ re: NSRegularExpression, _ s: String) -> [[String]] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map {
                m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0))
            }
        }
    }

    /// Substring search with identifier boundaries: "l+=1" must not hit "total+=1",
    /// "%b" must not hit "%buffer". Boundaries are enforced only on the ends of
    /// the needle that are themselves word characters.
    private static func containsBounded(_ norm: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
        let needPre = isWord(needle.first!), needPost = isWord(needle.last!)
        var from = norm.startIndex
        while from < norm.endIndex, let r = norm.range(of: needle, range: from..<norm.endIndex) {
            let preOK = !needPre || r.lowerBound == norm.startIndex
                || !isWord(norm[norm.index(before: r.lowerBound)])
            let postOK = !needPost || r.upperBound == norm.endIndex || !isWord(norm[r.upperBound])
            if preOK && postOK { return true }
            from = norm.index(after: r.lowerBound)
        }
        return false
    }

    /// True when `spaced` contains `<varName> <op> 1` (any amount of whitespace
    /// around the operator). Unlike `containsBounded` against the whitespace-
    /// stripped `norm`, this survives a statement boundary right after the
    /// increment — e.g. "l += 1" on one line immediately followed on the next
    /// line by "r -= 1" reads as "l+=1r-=1" once whitespace is gone, which
    /// `containsBounded` misreads as "l+=1" running into a longer token "1r...".
    private static func hasIncrementBy1(_ spaced: String, _ varName: String, op: String) -> Bool {
        let escapedOp = op == "+=" ? #"\+="# : op
        let re = rx(#"\b"# + varName + #"\s*"# + escapedOp + #"\s*1\b"#)
        return matches(re, spaced)
    }

    // Midpoint computations that mark divide-in-half algorithms.
    private static let midpoints: [String] = [
        "(low+high)/2", "(lo+hi)/2", "(left+right)/2", "(l+r)/2",
        "(start+end)/2", "(first+last)/2",
        "low+(high-low)/2", "lo+(hi-lo)/2", "left+(right-left)/2", "start+(end-start)/2",
        "(low+high)>>1", "(lo+hi)>>1", "(left+right)>>1", "(l+r)>>1",
        "count/2", "count>>1",
    ]

    // Child/parent index arithmetic of an array-backed binary heap.
    private static let heapIndexMath: [String] = [
        "2*i+1", "i*2+1", "2*i+2", "i*2+2",
        "2*index+1", "index*2+1", "2*idx+1", "idx*2+1", "2*pos+1", "pos*2+1",
        "(i-1)/2", "(index-1)/2", "(idx-1)/2", "(pos-1)/2", "(child-1)/2",
    ]

    // Ordered most-specific → most-generic; first match wins per function.
    private static let structuralRules: [StructuralRule] = [
        StructuralRule(name: "Sieve of Eratosthenes", category: .numeric) { f in
            guard f.hasLoop, f.any(["=false", "=true"]) else { return false }
            // marking multiples: start at p*p, step by p
            return allCaptures(reSquare, f.norm).contains { caps in
                containsBounded(f.norm, "by:\(caps[0])") || containsBounded(f.norm, "+=\(caps[0])")
            }
        },
        StructuralRule(name: "Euclidean GCD", category: .numeric) { f in
            if matches(reGCDTuple, f.norm) { return true }
            // while b != 0 { ... a % b ... }
            return allCaptures(reWhileNot0, f.spaced).contains { caps in
                containsBounded(f.norm, "%\(caps[0])")
            }
        },
        StructuralRule(name: "Dijkstra", category: .graph) { f in
            matches(reRelax, f.norm)
                && f.tok(["dist", "distance", "distances", "cost", "costs", "shortest"])
        },
        StructuralRule(name: "Kahn (Topological Sort)", category: .graph) { f in
            f.tok(["indegree", "indegrees"])
                && (f.any(["removefirst(", "dequeue"]) || f.tok(["queue"]))
        },
        StructuralRule(name: "Union–Find (Disjoint Set)", category: .graph) { f in
            // Path compression (parent[x] = find(parent[x])) is a standalone
            // strong signal; a recursive function literally named `find` that
            // also touches a `parent` array is the other common shape (union-by-
            // rank/size implementations that skip the compression one-liner).
            f.tokens.contains("parent")
                && (matches(reUnionFindCompress, f.norm) || (f.tokens.contains("find") && f.selfCalls >= 1))
        },
        StructuralRule(name: "Heapify", category: .sorting) { f in
            f.loopOrRecursion
                && f.any(heapIndexMath)
                && (f.any(["swapat("]) || matches(reTupleSwap, f.norm))
        },
        StructuralRule(name: "Quicksort", category: .sorting) { f in
            f.tokens.contains("pivot")
                && (f.selfCalls >= 2 || (f.selfCalls >= 1 && f.tokens.contains("partition")))
        },
        StructuralRule(name: "Merge Sort", category: .sorting) { f in
            f.selfCalls >= 2
                && !f.tokens.contains("pivot")
                && f.any(midpoints)
                && !f.any(["mid-1", "mid+1"])   // mid±1 recursion is binary search
                && (f.tok(["merge", "merged", "merging"])
                    || (f.tokens.contains("left") && f.tokens.contains("right")))
        },
        StructuralRule(name: "Binary Search", category: .searching) { f in
            f.loopOrRecursion
                && f.any(midpoints)
                && (matches(reHalve, f.norm)
                    || (f.selfCalls >= 1 && f.any(["mid-1", "mid+1"])))
        },
        StructuralRule(name: "Bubble Sort", category: .sorting) { f in
            f.loopNest >= 2
                && matches(reAdjCompare, f.norm)
                && (f.any(["swapat("]) || matches(reTupleSwap, f.norm) || matches(reCopyUp, f.norm))
        },
        StructuralRule(name: "Insertion Sort", category: .sorting) { f in
            f.loopNest >= 2
                && (matches(reShiftUp, f.norm) || matches(reShiftDown, f.norm))
        },
        StructuralRule(name: "Breadth-First Search", category: .graph) { f in
            f.hasLoop
                && f.tokens.contains("visited")
                && f.any(["removefirst(", "dequeue"])
        },
        StructuralRule(name: "Depth-First Search", category: .graph) { f in
            // visited guard + neighbor loop; recursion alone is any cycle-safe
            // walk (e.g. following a parent chain), not depth-first search
            f.hasLoop
                && f.tokens.contains("visited")
                && (f.any(["removelast(", "poplast("]) || f.selfCalls >= 1)
        },
        StructuralRule(name: "Floyd's Cycle Detection", category: .graph) { f in
            // The defining trait isn't "two variables incrementing" (too common
            // to mean anything) — it's the fast pointer advancing two hops while
            // slow advances one, the tortoise-and-hare double-step itself.
            f.tokens.contains("slow") && f.tokens.contains("fast") && f.hasLoop
                && f.any(["fast.next.next", "fast?.next?.next", "fast!.next!.next",
                          "fast=fast.next.next", "fast=fast?.next?.next"])
        },
        // Placed after Depth-First Search so a genuine visited-set DFS still wins
        // there first; this only catches the recursive try/undo shape DFS's
        // stricter `visited` requirement doesn't already claim.
        StructuralRule(name: "Backtracking (DFS)", category: .searching) { f in
            f.selfCalls >= 1 && f.any(["append("]) && f.any(["removelast(", "poplast("])
        },
        StructuralRule(name: "Kadane (Max Subarray)", category: .numeric) { f in
            (f.hasLoop && (matches(reKadane1, f.norm) || matches(reKadane2, f.norm)))
                || (f.tokens.contains("maxsofar") && f.tokens.contains("maxendinghere"))
        },
        StructuralRule(name: "Prefix Sum", category: .numeric) { f in
            f.hasLoop && matches(rePrefixSum, f.norm)
        },
        StructuralRule(name: "Fisher–Yates Shuffle", category: .numeric) { f in
            f.hasLoop
                && f.any(["swapat("])
                && f.any(["random(", "arc4random"])
        },
        StructuralRule(name: "Binary Exponentiation", category: .numeric) { f in
            f.hasLoop
                && f.any(["&1", "%2==1", "%2!=0"])
                && f.any([">>=1", ">>1", "/=2"])
                && f.norm.contains("*=")
        },
        StructuralRule(name: "Matrix Multiplication", category: .numeric) { f in
            f.loopNest >= 3 && matches(reMatMulAssign, f.norm)
        },
        StructuralRule(name: "Bresenham Line", category: .numeric) { f in
            f.hasLoop
                && f.tok(["error", "err"])
                && f.any(["2*dy", "2*dx", "dy*2", "dx*2"])
        },
        StructuralRule(name: "Exponential Backoff", category: .numeric) { f in
            f.hasLoop && matches(reBackoffDouble, f.norm)
        },
        // Deliberately NOT the bare `retain`/`release` word check this started
        // from — "release" alone is ordinary UIKit vocabulary (button/gesture
        // "released" state) with nothing to do with memory management, and would
        // have flooded this signal. The real signal here is the rare, explicit
        // retainCount/refCount variable name — retain() and release() are almost
        // always separate methods (as in this rule's own test fixture), so
        // requiring both directions in the *same* function body, the way every
        // other per-function structural rule works, would just never fire; one
        // increment or decrement of that specific counter is evidence enough.
        StructuralRule(name: "Manual Reference Counting", category: .numeric) { f in
            f.tok(["retaincount", "refcount"])
                && f.any(["retaincount+=1", "refcount+=1", "retaincount-=1", "refcount-=1"])
        },
        StructuralRule(name: "Memoized Recursion (DP)", category: .numeric) { f in
            f.selfCalls >= 1
                && f.tok(["memo", "memoized", "memoization", "memotable"])
        },
        StructuralRule(name: "Levenshtein Distance", category: .strMatch) { f in
            // The three-way min() over the up/left/diagonal neighbors is what
            // distinguishes edit-distance DP from a lookalike like LCS, which
            // combines the same three cells with max() instead.
            f.hasLoop && f.norm.contains("min(")
                && f.norm.contains("[i-1][j]") && f.norm.contains("[i][j-1]") && f.norm.contains("[i-1][j-1]")
        },
        // "alpha"/"beta" alone are common outside game-tree search too (color/
        // opacity blending, statistical parameters) — recursion plus both names
        // together plus a min/max bound narrows this a lot, though it's still
        // an approximation, same as the name-based rule this complements.
        StructuralRule(name: "Alpha–Beta Pruning", category: .numeric) { f in
            f.selfCalls >= 1
                && f.tokens.contains("alpha") && f.tokens.contains("beta")
                && f.any(["max(", "min("])
        },
        StructuralRule(name: "Two-Pointer Technique", category: .searching) { f in
            allCaptures(reWhileLess, f.spaced).contains { caps in
                hasIncrementBy1(f.spaced, caps[0], op: "+=") && hasIncrementBy1(f.spaced, caps[1], op: "-=")
            }
        },
    ]

    /// Brace-matches the function body starting at its declaration line and
    /// extracts the fingerprint features. Returns nil for bodiless functions.
    /// `lines` must already be comment/string stripped (SourceCache.strippedLines) —
    /// this only lowercases, it doesn't strip.
    private static func fnFeatures(lines: [String], startLine: Int, funcName: String) -> FnFeatures? {
        var depth = 0, started = false
        var loopStack: [Int] = []      // brace depth at which each open loop began
        var maxNest = 0
        var cleaned: [String] = []
        var j = startLine
        // Persists across lines: a loop keyword on one line whose `{` is on a
        // later line (multi-line condition, or Swift's allow-newline-before-brace
        // style) must not lose its loop attribution.
        var pendingLoop = false
        while j < lines.count && cleaned.count < 1200 {
            let line = lines[j].lowercased()
            pendingLoop = pendingLoop || matches(reLoopKeyword, line)
            for ch in line {
                if ch == "{" {
                    depth += 1; started = true
                    if pendingLoop {
                        loopStack.append(depth); pendingLoop = false
                        maxNest = max(maxNest, loopStack.count)
                    }
                } else if ch == "}" {
                    depth -= 1
                    while let last = loopStack.last, last > depth { loopStack.removeLast() }
                }
            }
            cleaned.append(line)
            if started && depth <= 0 { break }
            j += 1
        }
        guard started else { return nil }

        let joined = cleaned.joined(separator: "\n")
        let norm = joined.filter { !$0.isWhitespace }

        var tokens = Set<String>()
        var cur = ""
        for ch in joined {
            if ch.isLetter || ch.isNumber { cur.append(ch) }
            else if !cur.isEmpty { tokens.insert(cur); cur = "" }
        }
        if !cur.isEmpty { tokens.insert(cur) }

        // The declaration itself normalizes to "func<name>(" — boundary check
        // rejects it, so every bounded hit of "<name>(" is a recursive call.
        var selfCalls = 0
        let needle = funcName.lowercased() + "("
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
        var from = norm.startIndex
        while from < norm.endIndex, let r = norm.range(of: needle, range: from..<norm.endIndex) {
            if r.lowerBound == norm.startIndex || !isWord(norm[norm.index(before: r.lowerBound)]) {
                selfCalls += 1
            }
            from = norm.index(after: r.lowerBound)
        }

        return FnFeatures(norm: norm, spaced: joined, tokens: tokens, loopNest: maxNest, selfCalls: selfCalls)
    }

    private static func matchStructural(lines: [String], startLine: Int,
                                        funcName: String) -> (name: String, category: AlgoCategory)? {
        guard let f = fnFeatures(lines: lines, startLine: startLine, funcName: funcName),
              f.norm.count >= 30 else { return nil }
        for rule in structuralRules where rule.matches(f) {
            return (rule.name, rule.category)
        }
        return nil
    }

    func detect(files: [ParsedFile], cache: SourceCache) -> [AlgoMatch] {
        var found: [String: AlgoMatch] = [:]
        let moduleMap: [String: String] = Dictionary(uniqueKeysWithValues: files.map {
            ($0.filePath, $0.packageName.isEmpty ? $0.moduleName : $0.packageName)
        })

        func record(name: String, category: AlgoCategory, symbol: String, path: String, line: Int) {
            let mod = moduleMap[path] ?? ""
            if found[name] == nil {
                found[name] = AlgoMatch(name: name, category: category, count: 0, occurrences: [])
            }
            found[name]!.count += 1
            found[name]!.occurrences.append((symbol: symbol, filePath: path, line: line, module: mod))
        }

        // Phase 1 — type declarations (class/struct/actor named after an algorithm)
        for file in files {
            // Same one-scan-per-file helper DataStructureDetector uses for its
            // own type matches, reused rather than duplicated.
            let declLines = cache.strippedLines(file.filePath).map(DataStructureDetector.declarationLines) ?? [:]
            for decl in file.declarations where Self.typeKinds.contains(decl.kind) {
                if let rule = Self.matchRule(decl.name) {
                    record(name: rule.name, category: rule.category,
                           symbol: decl.name, path: file.filePath, line: declLines[decl.name] ?? 0)
                }
            }
        }

        // Phase 2 — function declarations from source scan (stripped lines from
        // the shared cache; no per-detector disk read, no per-detector strip —
        // otherwise a doc comment or log message that happens to contain "func
        // dijkstra(" reads as a real declaration and records a bogus match).
        for file in files where file.filePath.hasSuffix(".swift") {
            let fp = file.filePath
            guard let lines = cache.strippedLines(fp) else { continue }
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("func ") else { continue }
                guard let funcRange = trimmed.range(of: "func ") else { continue }
                let after = trimmed[funcRange.upperBound...]
                let funcName = String(after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
                guard !funcName.isEmpty else { continue }
                if let rule = Self.matchRule(funcName) {
                    record(name: rule.name, category: rule.category,
                           symbol: funcName, path: fp, line: i + 1)
                } else if let s = Self.matchStructural(lines: lines, startLine: i, funcName: funcName) {
                    record(name: s.name, category: s.category,
                           symbol: funcName, path: fp, line: i + 1)
                }
            }
        }

        return found.values.sorted { a, b in
            let ra = AlgoCategory.allCases.firstIndex(of: a.category) ?? 99
            let rb = AlgoCategory.allCases.firstIndex(of: b.category) ?? 99
            if ra != rb { return ra < rb }
            if a.count != b.count { return a.count > b.count }
            return a.name < b.name
        }
    }

    private static func matchRule(_ name: String) -> (name: String, category: AlgoCategory)? {
        let (tokenSet, joined) = tokenize(name)
        for rule in rules where rule.matches(tokenSet: tokenSet, joined: joined) {
            return (rule.name, rule.category)
        }
        return nil
    }

    // MARK: - Tokenizer (port of Go tokenize)

    private static func tokenize(_ name: String) -> (tokenSet: Set<String>, joined: String) {
        var tokens: [String] = []
        var cur: [Character] = []
        var joinedChars: [Character] = []

        let runes = Array(name)
        let isUpper = { (c: Character) in c >= "A" && c <= "Z" }
        let isLower = { (c: Character) in c >= "a" && c <= "z" }
        let isDigit = { (c: Character) in c >= "0" && c <= "9" }
        let isAlNum = { (c: Character) in isUpper(c) || isLower(c) || isDigit(c) }
        let toLower = { (c: Character) -> Character in
            guard c >= "A" && c <= "Z" else { return c }
            return Character(UnicodeScalar(c.asciiValue! + 32))
        }

        func flush() {
            if !cur.isEmpty { tokens.append(String(cur).lowercased()); cur = [] }
        }

        for (i, ch) in runes.enumerated() {
            guard isAlNum(ch) else { flush(); continue }
            joinedChars.append(toLower(ch))

            if !cur.isEmpty {
                let prev = cur.last!
                if isUpper(ch) && (isLower(prev) || isDigit(prev)) {
                    flush()  // lower/digit → Upper
                } else if isUpper(ch) && isUpper(prev) && i + 1 < runes.count && isLower(runes[i + 1]) {
                    flush()  // end of acronym run
                } else if isDigit(ch) != isDigit(prev) {
                    flush()  // letter ↔ digit boundary
                }
            }
            cur.append(ch)
        }
        flush()
        return (Set(tokens), String(joinedChars))
    }
}
