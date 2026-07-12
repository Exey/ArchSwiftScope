// Exey Panteleev
// Detects developer-implemented data structures from type-declaration naming
// conventions. Mirrors the Go datastructures module: suffix-based matching,
// longest-suffix wins, type declarations only (no stdlib collections).
import Foundation

// MARK: - Models

enum DSCategory: String, CaseIterable {
    case linear = "Linear · Lists · Stacks · Queues"
    case tree   = "Trees · Heaps"
    case hashed = "Hash-Based"
    case graph  = "Graphs"
    case linked = "Self-Referential · Linked"
    case other  = "Specialized"

    var icon: String {
        switch self {
        case .linear: return "📚"
        case .tree:   return "🌲"
        case .hashed: return "#️⃣"
        case .graph:  return "🕸️"
        case .linked: return "🔗"
        case .other:  return "🧩"
        }
    }
}

struct DSMatch {
    let name: String
    let category: DSCategory
    var count: Int
    var occurrences: [(typeName: String, filePath: String, module: String, line: Int)]
}

// MARK: - Detector

struct DataStructureDetector {

    private static let rules: [(suffix: String, name: String, category: DSCategory)] = {
        let raw: [(String, String, DSCategory)] = [
            // ── Linear ──────────────────────────────────────────────────────
            ("SinglyLinkedList",    "Linked List",              .linear),
            ("DoublyLinkedList",    "Linked List",              .linear),
            ("CircularLinkedList",  "Linked List",              .linear),
            ("XorLinkedList",       "Linked List",              .linear),
            ("LinkedList",          "Linked List",              .linear),
            ("SkipList",            "Skip List",                .linear),
            ("UnrolledList",        "Unrolled Linked List",     .linear),
            ("SelfOrganizingList",  "Self-Organizing List",     .linear),
            ("AssociationList",     "Association List",         .linear),
            ("DifferenceList",      "Difference List",          .linear),
            ("SortedList",          "Sorted List",              .linear),
            ("FreeList",            "Free List",                .linear),
            ("ConcTree",            "Conc-Tree List",           .linear),
            ("ConcTreeList",        "Conc-Tree List",           .linear),
            ("VList",               "VList",                    .linear),
            ("DynamicArray",        "Dynamic Array",            .linear),
            ("GrowableArray",       "Dynamic Array",            .linear),
            ("ArrayList",           "Dynamic Array",            .linear),
            ("SortedArray",         "Sorted Array",             .linear),
            ("ParallelArray",       "Parallel Array",           .linear),
            ("HashedArrayTree",     "Hashed Array Tree",        .linear),
            ("SuffixArray",         "Suffix Array",             .linear),
            ("PriorityQueue",       "Priority Queue",           .linear),
            ("DoubleEndedQueue",    "Deque",                    .linear),
            ("BlockingQueue",       "Blocking Queue",           .linear),
            ("ConcurrentQueue",     "Concurrent Queue",         .linear),
            ("WorkQueue",           "Work Queue",               .linear),
            // Deliberately no "DispatchQueue" rule: it's GCD's concurrency
            // primitive, not a data structure the codebase implements — a
            // `MyDispatchQueue` GCD wrapper isn't a "data structure" any more
            // than a `MyLock` would be.
            ("MessageQueue",        "Message Queue",            .linear),
            ("EventQueue",          "Event Queue",              .linear),
            ("TaskQueue",           "Task Queue",               .linear),
            ("CircularQueue",       "Circular Buffer",          .linear),
            ("CircularBuffer",      "Circular Buffer",          .linear),
            ("RingBuffer",          "Circular Buffer",          .linear),
            ("DoubleBuffer",        "Double Buffer",            .linear),
            ("TripleBuffer",        "Triple Buffer",            .linear),
            ("Deque",               "Deque",                    .linear),
            ("Stack",               "Stack",                    .linear),
            ("Queue",               "Queue",                    .linear),

            // ── Trees & Heaps ────────────────────────────────────────────────
            ("BinarySearchTree",    "Binary Search Tree",       .tree),
            ("BinaryTree",          "Binary Tree",              .tree),
            ("CartesianTree",       "Cartesian Tree",           .tree),
            ("OrderStatisticTree",  "Order Statistic Tree",     .tree),
            ("AVLTree",             "AVL Tree",                 .tree),
            ("RedBlackTree",        "Red–Black Tree",           .tree),
            ("SplayTree",           "Splay Tree",               .tree),
            ("ScapegoatTree",       "Scapegoat Tree",           .tree),
            ("AATree",              "AA Tree",                  .tree),
            ("WeightBalancedTree",  "Weight-Balanced Tree",     .tree),
            ("BPlusTree",           "B+ Tree",                  .tree),
            ("BTree",               "B-Tree",                   .tree),
            ("Treap",               "Treap",                    .tree),
            ("SegmentTree",         "Segment Tree",             .tree),
            ("FenwickTree",         "Fenwick Tree",             .tree),
            ("IntervalTree",        "Interval Tree",            .tree),
            ("RangeTree",           "Range Tree",               .tree),
            ("FingerTree",          "Finger Tree",              .tree),
            ("SuffixTree",          "Suffix Tree",              .tree),
            ("RadixTree",           "Radix Tree",               .tree),
            ("CompressedTrie",      "Compressed Trie",          .tree),
            ("TernarySearchTrie",   "Ternary Search Trie",      .tree),
            ("PatriciaTrie",        "Patricia Trie",            .tree),
            ("PatriciaTree",        "Patricia Trie",            .tree),
            ("PrefixTree",          "Trie",                     .tree),
            ("Trie",                "Trie",                     .tree),
            ("VanEmdeBoasTree",     "van Emde Boas Tree",       .tree),
            ("LinkCutTree",         "Link-Cut Tree",            .tree),
            ("EulerTourTree",       "Euler Tour Tree",          .tree),
            ("KaryTree",            "K-ary Tree",               .tree),
            ("TernaryTree",         "Ternary Tree",             .tree),
            ("QuadTree",            "Quadtree",                 .tree),
            ("Quadtree",            "Quadtree",                 .tree),
            ("Octree",              "Octree",                   .tree),
            ("KDTree",              "k-d Tree",                 .tree),
            ("KdTree",              "k-d Tree",                 .tree),
            ("RStarTree",           "R* Tree",                  .tree),
            ("RPlusTree",           "R+ Tree",                  .tree),
            ("RTree",               "R-Tree",                   .tree),
            ("VPTree",              "VP-Tree",                  .tree),
            ("BKTree",              "BK-Tree",                  .tree),
            ("BSPTree",             "BSP Tree",                 .tree),
            ("HilbertRTree",        "Hilbert R-Tree",           .tree),
            ("CoverTree",           "Cover Tree",               .tree),
            ("MTree",               "M-Tree",                   .tree),
            ("XTree",               "X-Tree",                   .tree),
            ("UBTree",              "UB-Tree",                  .tree),
            ("TTree",               "T-Tree",                   .tree),
            ("TangoTree",           "Tango Tree",               .tree),
            ("TopTree",             "Top Tree",                 .tree),
            ("WAVLTree",            "WAVL Tree",                .tree),
            ("ZipTree",             "Zip Tree",                 .tree),
            ("ThreadedBinaryTree",  "Threaded Binary Tree",     .tree),
            ("RandomizedBST",       "Randomized Binary Search Tree", .tree),
            ("RapidlyExploringRandomTree", "Rapidly-Exploring Random Tree", .tree),
            ("BVH",                 "Bounding Volume Hierarchy",.tree),
            ("MerkleTree",          "Merkle Tree",              .tree),
            ("HashTree",            "Merkle (Hash) Tree",       .tree),
            ("LSMTree",             "Log-Structured Merge-Tree",.tree),
            ("AbstractSyntaxTree",  "Abstract Syntax Tree",     .tree),
            ("SyntaxTree",          "Syntax Tree",              .tree),
            ("ParseTree",           "Parse Tree",               .tree),
            ("DecisionTree",        "Decision Tree",            .tree),
            ("ExpressionTree",      "Expression Tree",          .tree),
            ("FibonacciHeap",       "Fibonacci Heap",           .tree),
            ("BinomialHeap",        "Binomial Heap",            .tree),
            ("PairingHeap",         "Pairing Heap",             .tree),
            ("LeftistHeap",         "Leftist Heap",             .tree),
            ("SkewHeap",            "Skew Heap",                .tree),
            ("DAryHeap",            "d-ary Heap",               .tree),
            ("BrodalHeap",          "Brodal Queue",             .tree),
            ("SoftHeap",            "Soft Heap",                .tree),
            ("BinaryHeap",          "Binary Heap",              .tree),
            ("IndexedHeap",         "Indexed Heap",             .tree),
            ("MinMaxHeap",          "Min-Max Heap",             .tree),
            ("MinHeap",             "Min-Heap",                 .tree),
            ("MaxHeap",             "Max-Heap",                 .tree),
            ("Heap",                "Heap",                     .tree),
            ("Tree",                "Tree",                     .tree),

            // ── Hash-Based ──────────────────────────────────────────────────
            ("HashArrayMappedTrie", "Hash Array Mapped Trie",  .hashed),
            ("HashTable",           "Hash Table",               .hashed),
            ("LinkedHashMap",       "Hash Map",                 .hashed),
            ("HashMap",             "Hash Map",                 .hashed),
            ("HashSet",             "Hash Set",                 .hashed),
            ("HashList",            "Hash List",                .hashed),
            ("BloomFilter",         "Bloom Filter",             .hashed),
            ("CountingBloomFilter", "Counting Bloom Filter",    .hashed),
            ("CuckooFilter",        "Cuckoo Filter",            .hashed),
            ("QuotientFilter",      "Quotient Filter",          .hashed),
            ("XorFilter",           "Xor Filter",               .hashed),
            ("CuckooHash",          "Cuckoo Hash Table",        .hashed),
            ("RobinHoodHash",       "Robin Hood Hash Table",    .hashed),
            ("HopscotchHash",       "Hopscotch Hash Table",     .hashed),
            ("OpenAddressing",      "Open-Addressed Hash Table",.hashed),
            ("CountMinSketch",      "Count–Min Sketch",         .hashed),
            ("HyperLogLog",         "HyperLogLog",              .hashed),
            ("ConsistentHash",      "Consistent Hashing",       .hashed),
            ("ConsistentHashRing",  "Consistent Hashing",       .hashed),
            ("RollingHash",         "Rolling Hash",             .hashed),
            ("MinHash",             "MinHash",                  .hashed),
            ("SimHash",             "SimHash",                  .hashed),
            ("HAMT",                "Hash Array Mapped Trie",   .hashed),

            // ── Graphs ──────────────────────────────────────────────────────
            ("DirectedAcyclicGraph","Directed Acyclic Graph",   .graph),
            ("DirectedGraph",       "Directed Graph",           .graph),
            ("UndirectedGraph",     "Undirected Graph",         .graph),
            ("SceneGraph",          "Scene Graph",              .graph),
            ("DisjointSet",         "Disjoint-Set (Union-Find)",.graph),
            ("UnionFind",           "Disjoint-Set (Union-Find)",.graph),
            ("AdjacencyList",       "Adjacency List",           .graph),
            ("AdjacencyMatrix",     "Adjacency Matrix",         .graph),
            ("IncidenceMatrix",     "Incidence Matrix",         .graph),
            ("EdgeList",            "Edge List",                .graph),
            ("DoublyConnectedEdgeList", "Doubly Connected Edge List (DCEL)", .graph),
            ("HalfEdgeList",        "Doubly Connected Edge List (DCEL)", .graph),
            ("ControlFlowGraph",    "Control-Flow Graph",       .graph),
            ("DependencyGraph",     "Dependency Graph",         .graph),
            ("CallGraph",           "Call Graph",               .graph),
            ("FlowNetwork",         "Flow Network",             .graph),
            ("DiGraph",             "Directed Graph",           .graph),
            ("Multigraph",          "Multigraph",               .graph),
            ("Hypergraph",          "Hypergraph",               .graph),
            ("DAG",                 "Directed Acyclic Graph",   .graph),
            ("Graph",               "Graph",                    .graph),

            // ── Specialized ─────────────────────────────────────────────────
            ("SparseMatrix",        "Sparse Matrix",            .other),
            ("RoutingTable",        "Routing Table",            .other),
            ("SymbolTable",         "Symbol Table",             .other),
            ("LookupTable",         "Lookup Table",             .other),
            ("JumpTable",           "Jump Table",               .other),
            ("TranspositionTable",  "Transposition Table",      .other),
            ("BitArray",            "Bit Array",                .other),
            ("SuccinctBitVector",   "Succinct Bit Vector",      .other),
            ("BitVector",           "Bit Vector",               .other),
            ("BitSet",              "Bit Set",                  .other),
            ("Bitset",              "Bit Set",                  .other),
            ("BitBoard",            "Bitboard",                 .other),
            ("BitField",            "Bit Field",                .other),
            ("WaveletTree",         "Wavelet Tree",             .other),
            ("GapBuffer",           "Gap Buffer",               .other),
            ("PieceTable",          "Piece Table",              .other),
            ("LRUCache",            "LRU Cache",                .other),
            ("LFUCache",            "LFU Cache",                .other),
            ("ARCache",             "Adaptive Replacement Cache",.other),
            ("TwoQCache",           "2Q Cache",                 .other),
            ("Multiset",            "Multiset (Bag)",           .other),
            ("OrderedSet",          "Ordered Set",              .other),
            ("OrderedMap",          "Ordered Map",              .other),
            ("OrderedDictionary",   "Ordered Dictionary",       .other),
            ("SortedSet",           "Sorted Set",               .other),
            ("SortedDictionary",    "Sorted Dictionary",        .other),
            ("SortedMap",           "Sorted Map",               .other),
            ("PersistentVector",    "Persistent Vector",        .other),
            ("ImmutableArray",      "Immutable Array",          .other),
            ("CopyOnWriteArray",    "Copy-on-Write Array",      .other),
            ("Rope",                "Rope",                     .other),
            ("Blockchain",          "Blockchain",               .other),
        ]
        // Longest suffix wins: sort descending by suffix length
        return raw.sorted { $0.0.count > $1.0.count }
    }()

    private static let typeKinds: Set<Declaration.Kind> = [.class, .struct, .enum, .actor]

    // SwiftUI (and backport-library) layout/navigation types whose names end in
    // "Stack" but are views, never stack data structures. Rejected outright.
    private static let frameworkFalseFriends: Set<String> = [
        "HStack", "VStack", "ZStack",
        "LazyHStack", "LazyVStack",
        "NavigationStack",
    ]

    // Single-word suffixes that collide with framework/English names
    // (e.g. Stack → SwiftUI's ZStack/HStack/VStack). A match on one of these is
    // only accepted when the type's own body contains the structural vocabulary
    // of that data structure — proving it's an implementation, not a look-alike.
    //
    // Vocabulary follows the classic terminology map (node/vertex, edge/link,
    // head/front, tail/rear, top, next/previous, root, parent/child, leaf,
    // sibling, ancestor/descendant, subtree, depth/height, degree, adjacent,
    // cycle/acyclic, key/hash/collision). Terms match whole identifier tokens,
    // never substrings — "popover" no longer counts as "pop", ".top" alignment
    // no longer counts as "top" plus another term.
    //
    // Scoring: strong terms are unambiguous for the structure (2 points),
    // weak terms are shared vocabulary (1 point). A match needs ≥ 2 points,
    // so either one strong term or two distinct weak terms.
    private struct Evidence {
        let strong: Set<String>
        let weak: Set<String>
    }

    private static let evidenceBySuffix: [String: Evidence] = [
        "Stack": Evidence(
            strong: ["lifo"],
            weak:   ["push", "pop", "peek", "top", "node", "isempty"]),
        "Queue": Evidence(
            strong: ["enqueue", "dequeue", "fifo"],
            weak:   ["front", "rear", "head", "tail", "peek", "poll", "offer", "node"]),
        "Deque": Evidence(
            strong: ["pushfront", "pushback", "popfront", "popback", "enqueuefront", "enqueueback"],
            weak:   ["front", "back", "head", "tail", "enqueue", "dequeue", "push", "pop", "node"]),
        "Heap": Evidence(
            strong: ["heapify", "siftup", "siftdown", "percolateup", "percolatedown",
                     "bubbleup", "bubbledown", "extractmin", "extractmax"],
            weak:   ["sift", "percolate", "parent", "child", "peek", "node", "root"]),
        "Tree": Evidence(
            strong: ["subtree", "inorder", "preorder", "postorder", "leaf", "leaves",
                     "sibling", "ancestor", "descendant", "rebalance"],
            weak:   ["root", "parent", "child", "children", "node", "nodes", "depth",
                     "height", "degree", "traverse", "rotate", "edge"]),
        "Trie": Evidence(
            strong: ["endofword", "isword", "isend", "isterminal", "wordend"],
            weak:   ["prefix", "children", "root", "node", "nodes", "word"]),
        "Graph": Evidence(
            strong: ["adjacency", "adjacent", "vertex", "vertices", "addedge", "addvertex",
                     "indegree", "outdegree", "acyclic"],
            weak:   ["edge", "edges", "node", "nodes", "neighbor", "neighbors",
                     "neighbour", "neighbours", "degree", "cycle", "link"]),
        "Rope": Evidence(
            strong: [],
            weak:   ["concat", "substring", "split", "weight", "rebalance", "leaf", "node"]),
        "Multiset": Evidence(
            strong: ["multiplicity"],
            weak:   ["occurrences", "count", "add", "remove", "contains"]),
    ]

    /// Splits an already-lowercased type body into identifier tokens
    /// (runs of letters/digits), so evidence terms match whole words only.
    private static func bodyTokens(_ body: String) -> Set<String> {
        var tokens = Set<String>()
        var cur = ""
        for ch in body {
            if ch.isLetter || ch.isNumber {
                cur.append(ch)
            } else if !cur.isEmpty {
                tokens.insert(cur)
                cur = ""
            }
        }
        if !cur.isEmpty { tokens.insert(cur) }
        return tokens
    }

    /// True when the body vocabulary scores enough points for the structure.
    private static func hasEvidence(_ ev: Evidence, body: String) -> Bool {
        // SwiftUI views are look-alikes by construction (CardStack, TabStack, …)
        if body.contains(": some view") { return false }
        let tokens = bodyTokens(body)
        var score = 0
        for t in tokens {
            if ev.strong.contains(t) { score += 2 }
            else if ev.weak.contains(t) { score += 1 }
            if score >= 2 { return true }
        }
        return false
    }

    func detect(files: [ParsedFile], cache: SourceCache) -> [DSMatch] {
        // Pass 1 — collect raw matches.
        struct RawMatch { let ruleName: String; let category: DSCategory; let suffix: String; let typeName: String; let filePath: String; let module: String; let line: Int }
        var raws: [RawMatch] = []

        for file in files {
            let mod = file.packageName.isEmpty ? file.moduleName : file.packageName
            // One scan of the file's declaration lines, shared by every match in
            // this file — cheaper than re-scanning per match.
            let declLines = cache.strippedLines(file.filePath).map(Self.declarationLines) ?? [:]
            for decl in file.declarations where Self.typeKinds.contains(decl.kind) {
                guard !Self.frameworkFalseFriends.contains(decl.name) else { continue }
                guard let rule = Self.matchRule(decl.name) else { continue }
                raws.append(RawMatch(ruleName: rule.name, category: rule.category, suffix: rule.suffix,
                                     typeName: decl.name, filePath: file.filePath, module: mod,
                                     line: declLines[decl.name] ?? 0))
            }
        }

        // Pass 2 — accept matches, gating generic suffixes behind body evidence
        // (source lines come from the shared cache; no per-detector disk read).
        var found: [String: DSMatch] = [:]
        var suffixReported = Set<String>()
        for r in raws {
            if let ev = Self.evidenceBySuffix[r.suffix] {
                guard let lines = cache.strippedLines(r.filePath),
                      let body = Self.typeBody(in: lines, typeName: r.typeName),
                      Self.hasEvidence(ev, body: body)
                else { continue }
            }
            if found[r.ruleName] == nil {
                found[r.ruleName] = DSMatch(name: r.ruleName, category: r.category, count: 0, occurrences: [])
            }
            found[r.ruleName]!.count += 1
            found[r.ruleName]!.occurrences.append((typeName: r.typeName, filePath: r.filePath, module: r.module, line: r.line))
            suffixReported.insert(r.typeName)
        }

        // Pass 3 — mx-find-linked-structures: type-graph based detection of
        // self-referential structures and the types that embed them.
        for m in Self.detectLinked(files: files, cache: cache, skip: suffixReported) {
            found[m.name] = m
        }

        return found.values.sorted { a, b in
            let ra = DSCategory.allCases.firstIndex(of: a.category) ?? 99
            let rb = DSCategory.allCases.firstIndex(of: b.category) ?? 99
            if ra != rb { return ra < rb }
            if a.count != b.count { return a.count > b.count }
            return a.name < b.name
        }
    }

    private static func matchRule(_ name: String) -> (name: String, category: DSCategory, suffix: String)? {
        for rule in rules where name.hasSuffix(rule.suffix) {
            return (rule.name, rule.category, rule.suffix)
        }
        return nil
    }

    /// Maps every top-level `class/struct/enum/actor <Name>` declaration in the file to its
    /// 1-based line number, in one pass — cheaper than re-scanning per match when a file has
    /// several matches. First declaration wins on a (rare) duplicate name. `lines` must
    /// already be comment/string stripped (SourceCache.strippedLines). Not private:
    /// AlgorithmDetector's own Phase 1 (type declarations named after an algorithm)
    /// reuses this instead of duplicating it.
    static func declarationLines(_ lines: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        let keywords = ["class ", "struct ", "enum ", "actor "]
        for (i, line) in lines.enumerated() {
            guard keywords.contains(where: { line.contains($0) }) else { continue }
            for kw in keywords {
                guard let r = line.range(of: kw) else { continue }
                let after = line[r.upperBound...]
                let name = String(after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
                if !name.isEmpty && result[name] == nil { result[name] = i + 1 }
            }
        }
        return result
    }

    /// Extracts the lowercased body of `class/struct/enum/actor <typeName>` via brace matching.
    /// `lines` must already be comment/string stripped (SourceCache.strippedLines) — otherwise
    /// a doc comment or log message that happens to mention "push"/"pop"/"peek" prose reads as
    /// implementation evidence, and a stray comment containing "class Stack" can even
    /// mis-locate where the brace matching starts.
    private static func typeBody(in lines: [String], typeName: String) -> String? {
        let keywords = ["class ", "struct ", "enum ", "actor "]
        for (i, line) in lines.enumerated() {
            guard keywords.contains(where: { line.contains($0) }), declares(line, typeName) else { continue }
            var depth = 0, started = false
            var body: [String] = []
            var j = i
            while j < lines.count {
                let l = lines[j]
                for ch in l {
                    if ch == "{" { depth += 1; started = true }
                    else if ch == "}" { depth -= 1 }
                }
                if started { body.append(l) }
                if started && depth <= 0 { return body.joined(separator: "\n").lowercased() }
                j += 1
            }
            return body.joined(separator: "\n").lowercased()
        }
        return nil
    }

    // MARK: - Linked (self-referential) structures
    //
    // mx-find-linked-structures: name-free detection from
    // the type graph alone.
    //   Level 0 — a type with a stored property (or enum case payload) whose
    //             type references the type itself: `var next: Node?`,
    //             `children: [TreeNode]`, `indirect enum Expr { case add(Expr, Expr) }`.
    //   Level N — fixpoint propagation: a type with a field referencing a
    //             level-(N-1) linked type is itself part of a linked structure
    //             (the `list_head`-embedded-in-struct pattern).
    // Unlike the suffix rules, this finds `Employee.manager` and `Comment.replies`
    // just as readily as textbook nodes — that is the point: it reports which
    // types actually form recursive object graphs.

    private struct TypeScan {
        let name: String
        let filePath: String
        let module: String
        let line: Int                  // 1-based declaration line
        let selfFieldNames: [String]   // lowercased names of self-referencing stored props
        let selfViaCollection: Bool    // self reference wrapped in [ ] / Set< / Dictionary<
        let selfViaEnumCase: Bool      // self reference in an enum case payload
        let fieldRefs: Set<String>     // every capitalized type name referenced by fields
        var isSelfRef: Bool { !selfFieldNames.isEmpty || selfViaEnumCase }
    }

    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p)
    }

    private static let reTypeDecl = rx(
        #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|internal|fileprivate|open|package|final|indirect|nonisolated|dynamic)\s+)*(?:class|struct|enum|actor)\s+(\w+)"#)
    private static let reStoredProp = rx(
        #"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:public|private|internal|fileprivate|open|package|final|weak|unowned|lazy|nonisolated)(?:\([^)]*\))?\s+)*(?:var|let)\s+(\w+)\s*:\s*([^={]+)"#)
    private static let reCasePayload = rx(#"^\s*(?:indirect\s+)?case\s+\w+[^(]*\(([^)]*)\)"#)
    private static let reTypeName = rx(#"[A-Z][A-Za-z0-9_]*"#)

    private static func captures(_ re: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map {
            m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0))
        }
    }

    private static func typeNames(in s: String) -> Set<String> {
        let ns = s as NSString
        let ms = reTypeName.matches(in: s, range: NSRange(location: 0, length: ns.length))
        return Set(ms.map { ns.substring(with: $0.range) })
    }

    /// True when a `var`/`let` line is a computed property (`{ get }`, or a
    /// bare getter body) rather than a stored one — `var parent: Node? { lookup() }`
    /// creates no actual object-graph edge, so it must not count as a
    /// self-referencing field. `didSet`/`willSet` observers still decorate a
    /// genuinely stored property, so those are explicitly let through.
    private static func isComputedProperty(_ line: String) -> Bool {
        guard let braceIdx = line.firstIndex(of: "{") else { return false }
        let after = line[line.index(after: braceIdx)...].trimmingCharacters(in: .whitespaces)
        return !(after.hasPrefix("didSet") || after.hasPrefix("willSet"))
    }

    /// Scans one file for type declarations (any nesting depth) and collects
    /// each type's field-level type references. `lines` must already be
    /// comment/string stripped (SourceCache.strippedLines).
    private static func scanTypes(lines: [String], filePath: String, module: String) -> [TypeScan] {
        var out: [TypeScan] = []
        let stripped = lines

        for (i, line) in stripped.enumerated() {
            guard let caps = captures(reTypeDecl, line), !caps[0].isEmpty else { continue }
            let name = caps[0]
            guard !frameworkFalseFriends.contains(name) else { continue }

            var selfFieldNames: [String] = []
            var selfViaCollection = false
            var selfViaEnumCase = false
            var fieldRefs = Set<String>()

            // Walk the body; analyze only lines at depth 1 relative to this
            // type (its own members — nested types/functions sit deeper).
            var depth = 0, started = false
            var j = i
            while j < stripped.count {
                // On the declaration line itself, members can follow the brace
                // (one-line nodes: `final class Node { var next: Node? }`).
                let l = j == i
                    ? stripped[j].firstIndex(of: "{").map { String(stripped[j][stripped[j].index(after: $0)...]) } ?? ""
                    : stripped[j]
                if (started && depth == 1 && j > i) || (j == i && !l.isEmpty) {
                    if !l.contains("static ") && !l.contains(" class var") && !l.contains(" class let"),
                       !isComputedProperty(l),
                       let p = captures(reStoredProp, l) {
                        let propName = p[0], typeExpr = p[1]
                        let refs = typeNames(in: typeExpr)
                        fieldRefs.formUnion(refs)
                        if refs.contains(name) {
                            selfFieldNames.append(propName.lowercased())
                            if typeExpr.contains("[") || typeExpr.contains("Set<")
                                || typeExpr.contains("Dictionary<") || typeExpr.contains("Array<") {
                                selfViaCollection = true
                            }
                        }
                    } else if let c = captures(reCasePayload, l) {
                        let refs = typeNames(in: c[0])
                        fieldRefs.formUnion(refs)
                        if refs.contains(name) { selfViaEnumCase = true }
                    }
                }
                for ch in stripped[j] {
                    if ch == "{" { depth += 1; started = true }
                    else if ch == "}" { depth -= 1 }
                }
                if started && depth <= 0 { break }
                j += 1
            }

            fieldRefs.remove(name)
            out.append(TypeScan(name: name, filePath: filePath, module: module, line: i + 1,
                                selfFieldNames: selfFieldNames,
                                selfViaCollection: selfViaCollection,
                                selfViaEnumCase: selfViaEnumCase,
                                fieldRefs: fieldRefs))
        }
        return out
    }

    // One-line explanations for the name-free "Self-Referential · Linked"
    // matches — unlike every other category, these names describe a *shape*
    // detected from the type graph rather than a well-known textbook
    // structure, so the name alone ("Embeds Linked Structure (nested)")
    // doesn't say what was actually observed.
    private static let linkedMatchDetail: [String: String] = [
        "Recursive Enum": "Indirect enum case whose payload references the enum itself — a recursive type (e.g. an expression or JSON tree).",
        "Binary Tree Node": "Type with both `left` and `right` fields referencing its own type — a binary tree node.",
        "Doubly Linked Node": "Type with `next` and `prev`/`previous` fields referencing its own type — a doubly linked list node.",
        "Tree Node (self collection)": "Type holding a collection ([…] / Set / Dictionary) of its own type — an N-ary tree or graph node.",
        "Singly Linked Node": "Type with a `next` field referencing its own type — a singly linked list node.",
        "Self-Referential Type": "Type with a stored property referencing its own type, in a shape other than the patterns above.",
        "Embeds Linked Structure (direct)": "Not self-referential itself, but has a field whose type is one of the self-referential types above.",
        "Embeds Linked Structure (nested)": "Not self-referential itself, but has a field whose type embeds one of the self-referential types above, one hop further in.",
    ]

    /// Short explanation of what a linked-structure match name means, or nil
    /// for every other category (whose names are already self-explanatory,
    /// well-known structure names).
    static func detail(forLinkedMatch name: String) -> String? {
        linkedMatchDetail[name]
    }

    /// Names the level-0 shape from its self-referencing fields.
    private static func classifyShape(_ t: TypeScan) -> String {
        let f = Set(t.selfFieldNames)
        if t.selfViaEnumCase { return "Recursive Enum" }
        if f.contains("left") && f.contains("right") { return "Binary Tree Node" }
        if f.contains("next") && (f.contains("prev") || f.contains("previous")) {
            return "Doubly Linked Node"
        }
        if t.selfViaCollection { return "Tree Node (self collection)" }
        if f.contains("next") { return "Singly Linked Node" }
        return "Self-Referential Type"
    }

    /// mx-find-linked-structures: level 0 = self-linking types, then a fixpoint
    /// finds every type that (transitively) embeds one.
    private static func detectLinked(files: [ParsedFile], cache: SourceCache, skip: Set<String>) -> [DSMatch] {
        let swiftFiles = files.filter { $0.filePath.hasSuffix(".swift") }
        guard !swiftFiles.isEmpty else { return [] }

        // Lines come from the shared cache (no disk read); the type-graph scan
        // itself is CPU-bound, so it stays parallel.
        var buf: [[TypeScan]] = Array(repeating: [], count: swiftFiles.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: swiftFiles.count) { idx in
            let file = swiftFiles[idx]
            guard let lines = cache.strippedLines(file.filePath) else { return }
            let mod = file.packageName.isEmpty ? file.moduleName : file.packageName
            let scans = scanTypes(lines: lines, filePath: file.filePath, module: mod)
            lock.lock(); buf[idx] = scans; lock.unlock()
        }
        let scans = buf.flatMap { $0 }

        // Level 0
        var levelOf: [String: Int] = [:]
        for t in scans where t.isSelfRef { levelOf[t.name] = 0 }

        // Fixpoint: field references into the linked set pull the owner in.
        // Capped at L2 — in a large real codebase the fixpoint otherwise keeps
        // pulling in embedders-of-embedders until most of the model layer is
        // "linked" (anything that transitively holds a Node holds a Node), which
        // buries the interesting L0/L1 signal in noise. L1/L2 (does this type
        // directly, or one hop away, embed a linked structure) is the useful
        // question; deeper transitive membership isn't worth reporting.
        var linked = Set(levelOf.keys)
        var lvl = 0
        while lvl < 2 {
            lvl += 1
            var added: [String] = []
            for t in scans where levelOf[t.name] == nil && !t.fieldRefs.isDisjoint(with: linked) {
                levelOf[t.name] = lvl
                added.append(t.name)
            }
            if added.isEmpty { break }
            linked.formUnion(added)
        }

        // Aggregate into DSMatches; skip types the suffix rules already report.
        var found: [String: DSMatch] = [:]
        var reported = Set<String>()
        for t in scans {
            guard let level = levelOf[t.name], !skip.contains(t.name),
                  reported.insert(t.name).inserted else { continue }
            // The hop distance used to be baked into the occurrence name as a
            // "· L1"/"· L2" suffix, which read as noise next to the type name.
            // It's clearer as the match name itself — direct vs. nested embedding
            // are different enough claims to deserve their own group and
            // description (see `detail(forLinkedMatch:)`), leaving the occurrence
            // name to just be the type name plus its real source line.
            let ruleName: String
            switch level {
            case 0:  ruleName = classifyShape(t)
            case 1:  ruleName = "Embeds Linked Structure (direct)"
            default: ruleName = "Embeds Linked Structure (nested)"
            }
            if found[ruleName] == nil {
                found[ruleName] = DSMatch(name: ruleName, category: .linked, count: 0, occurrences: [])
            }
            found[ruleName]!.count += 1
            found[ruleName]!.occurrences.append((typeName: t.name, filePath: t.filePath, module: t.module, line: t.line))
        }
        return Array(found.values)
    }

    /// True when `line` declares a type whose name is exactly `name` (boundary-checked).
    private static func declares(_ line: String, _ name: String) -> Bool {
        for kw in ["class ", "struct ", "enum ", "actor "] {
            guard let r = line.range(of: kw + name) else { continue }
            if r.upperBound == line.endIndex { return true }
            let c = line[r.upperBound]
            if !(c.isLetter || c.isNumber || c == "_") { return true }
        }
        return false
    }
}
