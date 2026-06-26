# 🔬 ArchSwiftScope

**macOS CLI tool for Swift codebase intelligence** — find critical files, generate dependency graphs, detect traffic patterns, learning paths.

Built 100% in Swift. **Fully offline. No network required. No telemetry. No accounts.**

> AI-powered features (natural-language Q&A) are available as a separate opt-in — see [AI Integration (Opt-In)](#-ai-integration-opt-in).

---

## ⚡ Generate a Report in 10 Seconds

```bash
cd ArchSwiftScope

# Projects under 300K lines — just run directly
swift run codecontext analyze ~/path/to/your/project --open

# Large projects (300K+ lines) — release build is 5–10× faster
swift build -c release
.build/release/codecontext analyze ~/path/to/your/project --open
```

---

## 📊 How HTML Report looks

1. **Summary** — total files, lines of code, declarations by type (structs, classes, enums, protocols, actors), Swift version, deployment targets, app version, and package count

![ArchSwiftScope](https://exey.github.io/ArchScopeDocs/ass_summary.svg)


2. **🏛️ Architecture** — structural decomposition across 8 sub-sections:
   - **🎨 Arch Pattern** — MV, MVVV, VIPER, RIBs and other
   - **📐 Layers** — files classified by directory/naming patterns into UI/Views, Presentation, Models, API/Networking, Persistence, Auth, Config, Utilities, Tests, Core — with file counts, line counts, and proportional bar chart
   - **🧩 Components** — detected architectural components from Apple framework imports (SwiftUI, UIKit, CoreData, Combine, ARKit, CoreML, and 30+ more)
   - **🍎 Apple Frameworks** — all Apple SDK frameworks used, as a searchable tag cloud
   - **📦 External Libraries** — third-party package imports detected across the codebase
   - **🏠 Local Packages** — Swift Package Manager modules with file counts, line counts, build-system badges (SwiftUI/UIKit/AppKit), Metal shader indicators, and clickable navigation links
   - **🗺️ Architecture Graph** — top-level inter-package dependency graph
   - **🎨 Design Patterns** — detected GoF and architectural patterns (Singleton, Factory, Observer, Coordinator, and more) grouped by category with occurrence counts and example file links

![ArchSwiftScope](https://exey.github.io/ArchScopeDocs/ass_arch.svg)

![ArchSwiftScope](https://exey.github.io/ArchScopeDocs/ass_graph.svg)

3. **🛜 Traffic** — inbound and outbound connection signals detected across all source files *(shown only when signals are present)*:
   - **📥 Inbound** — Vapor/server-side Swift route definitions (`app.get`, `routes.post`, …) and TCP server declarations (`NWListener`)
   - **📤 Outbound** — HTTP/HTTPS/WebSocket URL string literals; TCP connections via `NWConnection` (Network.framework), `NWPathMonitor` (reachability), `SCNetworkReachabilityCreateWithName` (SystemConfiguration), BSD POSIX `socket(…SOCK_STREAM…)`, and `CFStreamCreatePairWithSocketToHost` (Core Foundation)
   - Each entry shows a protocol tag (REST · WebSocket · gRPC · GraphQL · TCP), URI or detected pattern, data format (JSON / Protobuf / XML), and a clickable VS Code link to the source file and line

4. **🧬 OOP vs POP** — style signal across all Swift types, scored across three weighted categories:
   - **Protocol Design (55%)** — protocol density, constrained generics, conformance breadth (Impl-pattern detection), default implementations, `associatedtype` usage, `some`-with-user-protocols, and `A & B` composition
   - **Value Semantics (30%)** — struct-to-class ratio, `final` keyword usage, enums with associated values
   - **Anti-inheritance (15%)** — average inheritance depth, `override` density, NSObject subclass count
   - Overall POP score (0–100%) shown on a gradient bar; each metric scored 0–100% with POP / Mixed / OOP signal tags

![ArchSwiftScope](https://exey.github.io/ArchScopeDocs/ass_oop.svg)

4.🚨 **Security Risks** - (55 active checks · index 0–1000)
   Higher index = more risk. DANGER INDEX aggregates 14 weighted categories; each category's risk scales with violation density. Per-category weight bars and clickable VS Code links to every violation. Categories without active checks are shown as *not assessed*.
   
![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_sec.svg)

5. **🐙 Git Analysis** — full git history intelligence across 6 sub-sections:
   - **👥 Team Contribution Map** — developer activity with files modified, commit counts, first/last change dates, and top-3 modules per author
   - **🌿 Branch Management** — total branch count (local + remote), avg branch lifetime, time-to-merge, integration delay, rollback rate, peak commit day, stale branches (>90 days inactive), and already-merged branches
   - **🔀 Branching Model** — role-based classifier that detects **Gitflow**, **Trunk-Based Development**, **GitHub Flow**, **GitLab Flow**, and **OneFlow** from the `.git` commit DAG. Scores all five models against the same evidence and displays ranked confidence bars. 
   - **🔥 Code Churn** — top 15 most frequently changed files by commit count, ranked from highest to lowest
   - **📐 Semantic Standards** — conventional commit compliance rate, semver tag count, and a breakdown of commit prefix types (feat, fix, chore, etc.)

![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_git.svg)

6. **🔥 Hot Zones** — files with the highest PageRank scores, identifying the most connected and architecturally significant code

![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_hot.svg)

7. **📏 Longest Functions** — ranked list of functions by line count, with clickable VS Code links jumping directly to the function definition

![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_funcs.svg)

8. **📋 Module Insights** — package penetration (which modules are foundational dependencies), plus TODO/FIXME density per module

![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_modules.svg)

9. **📦 Packages & Modules** — per-package breakdown with file inventory, declaration statistics, interactive force-directed dependency graph (colored by type), and inline documentation previews

![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_pkgs.svg)

10. **🎨 Assets** *(shown when `.xcassets` are present)* — media resource analysis: total bundle size in MB, file count and size breakdown by type (image, audio, video), and top-3 heaviest files per category with individual file sizes

![ArchSwiftScope Security Risks](https://exey.github.io/ArchScopeDocs/ass_assets.svg)

---

## 🔒 Offline by Design

Every core feature runs **entirely on your machine**:

- **Source parsing** — Apple's native SwiftSyntax, no external services
- **Dependency graphs & PageRank** — computed locally
- **Git history analysis** — reads your local `.git` directory
- **HTML report generation** — self-contained, no CDN links, no external assets
- **Caching** — actor-based file cache stored on disk

Your code never leaves your machine unless you explicitly enable the optional AI integration and send a query.

---

## 🏗️ Build & Install

### Option 1: Swift CLI (Recommended)

```bash
cd ArchSwiftScope

# Debug build (fast compilation)
swift build

# Run directly
swift run codecontext analyze ~/Projects/MyApp

# Release build (optimized, ~3× faster runtime)
swift build -c release

# The binary is at:
.build/release/codecontext
```

### Option 2: Install System-Wide

```bash
swift build -c release
sudo cp .build/release/codecontext /usr/local/bin/

# Now use from anywhere:
codecontext analyze ~/Projects/MyApp
codecontext evolution --months 12
```

### Option 3: One-Line Install

```bash
swift build -c release && sudo cp .build/release/codecontext /usr/local/bin/ && echo "✅ installed"
```

### Option 4: Xcode (for Development / Debugging)

```bash
open Package.swift
```

In Xcode:

1. Select the `codecontext` scheme
2. Edit Scheme → Run → Arguments → add: `analyze /path/to/your/project`
3. ⌘R to build and run

---

## 📖 Usage

### Analyze a Codebase

```bash
# Analyze current directory
codecontext analyze

# Analyze specific path
codecontext analyze ~/Projects/MyApp

# With options
codecontext analyze ~/Projects/MyApp --no-cache --verbose --open

# Skip the Packages & Modules section (faster for large codebases)
codecontext analyze ~/Projects/MyApp --skip-modules --open
```

### View Codebase Evolution

```bash
# Default: 6 months back, 30-day intervals
codecontext evolution

# Custom range
codecontext evolution --months 12 --interval 7
```

### Initialize Config

```bash
codecontext init
# Creates .codecontext.json with sensible defaults
```

---

## ⚙️ Configuration

Create `.codecontext.json` in your project root (or run `codecontext init`):

```json
{
    "excludePaths": [".git", ".build", "DerivedData", "Pods", "Carthage"],
    "maxFilesAnalyze": 5000,
    "gitCommitLimit": 1000,
    "enableCache": true,
    "enableParallel": true,
    "hotspotCount": 15,
    "fileExtensions": ["swift"]
}
```

All options above are offline. No network configuration needed.

---

## 🤖 AI Integration (Opt-In)

> **This is entirely optional.** Every feature described above works without it.

If you want to ask natural-language questions about your codebase, you can enable the AI module. This sends a context summary to an external LLM provider, so **review your provider's data policies before enabling**.

### Enable AI

Add an `ai` block to your `.codecontext.json`:

```json
{
    "ai": {
        "enabled": false,
        "provider": "anthropic",
        "apiKey": "",
        "model": "claude-sonnet-4-20250514"
    }
}
```

### Supported AI Providers

| Provider | `provider` | Model examples |
| -------- | ---------- | -------------- |
| Anthropic Claude | `"anthropic"` | `claude-sonnet-4-20250514` |
| Google Gemini | `"gemini"` | `gemini-2.5-flash` |

### Ask Questions

```bash
codecontext ask "Where is the authentication logic?"
codecontext ask "What would break if I refactored UserService?"
```

### What Gets Sent

When you run `ask`, a summary of your project structure and relevant code context is sent to the configured provider. Raw source files are not uploaded in full — the tool assembles a focused context window. No data is sent for any other command (`analyze`, `evolution`, `init`).

---

## 📁 Project Structure

```text
ArchSwiftScope/
├── Package.swift
├── Sources/CodeContext/
│   ├── CLI/
│   │   ├── CodeContextCLI.swift           # @main entry point
│   │   ├── AnalyzeCommand.swift           # Main analysis command
│   │   ├── AskCommand.swift               # AI Q&A command (opt-in)
│   │   ├── EvolutionCommand.swift         # Temporal analysis
│   │   └── InitCommand.swift              # Config initialization
│   ├── Core/
│   │   ├── AnalysisPipeline.swift         # Orchestrates all analysis passes
│   │   ├── ArchAnalyzer.swift             # Architecture pattern + layer classifier
│   │   ├── DesignPatternDetector.swift    # GoF / architectural pattern detection
│   │   ├── OOPvsPOPAnalyzer.swift         # OOP vs POP scoring
│   │   ├── SecurityAnalyzer.swift         # 55-check security index (0–1000)
│   │   ├── MonkeyPatchedLibs.swift        # Vendored C/C++ library detection
│   │   ├── Config/
│   │   │   └── CodeContextConfig.swift    # Config models + loader
│   │   ├── Cache/
│   │   │   └── CacheManager.swift         # Actor-based file cache
│   │   ├── Parser/
│   │   │   ├── ParsedFile.swift           # File model + git metadata
│   │   │   ├── SwiftParser.swift          # Swift source parser
│   │   │   ├── ObjCParser.swift           # Objective-C header parser
│   │   │   ├── ParserFactory.swift        # Extension → parser dispatch
│   │   │   └── ParallelParser.swift       # Concurrent parsing with cache
│   │   ├── Scanner/
│   │   │   ├── RepositoryScanner.swift    # Directory walker + exclusion rules
│   │   │   └── GitAnalyzer.swift          # Git history, branch stats,
│   │   │                                  # and branching model detection
│   │   │                                  # (Gitflow / TBD / GitHub Flow /
│   │   │                                  #  GitLab Flow / OneFlow)
│   │   ├── Graph/
│   │   │   └── DependencyGraph.swift      # Dependency graph + PageRank
│   │   ├── Generator/
│   │   │   └── LearningPathGenerator.swift
│   │   ├── Temporal/
│   │   │   └── TemporalAnalyzer.swift     # Codebase evolution tracking
│   │   ├── AI/
│   │   │   └── AICodeAnalyzer.swift       # URLSession AI client (opt-in)
│   │   └── Exceptions/
│   │       └── CodeContextError.swift
│   └── Output/
│       └── ReportGenerator.swift          # Self-contained HTML report
└── Tests/CodeContextTests/
    └── CodeContextTests.swift
```

---

## 🧪 Run Tests

```bash
swift test
```

---

## Requirements

- **macOS 13+** (Ventura or later)
- **Xcode 15+** / Swift 5.9+
- **git** (comes with Xcode Command Line Tools)
- **No internet connection required** for core features
