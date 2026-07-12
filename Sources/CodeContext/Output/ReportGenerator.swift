// Exey Panteleev
import Foundation

// MARK: - Report Graph Models

struct GraphNode: Codable {
    let id: String
    let label: String
    let sublabel: String
    let kind: String
    let score: Double
    let group: String
}

struct GraphLink: Codable {
    let source: String
    let target: String
}

struct GraphData: Codable {
    let nodes: [GraphNode]
    let links: [GraphLink]
}

// MARK: - Import Classification

enum ImportKind: Comparable {
    case apple, external, local
    var label: String {
        switch self { case .apple: return "Apple Frameworks"; case .external: return "External Dependencies"; case .local: return "Local Packages" }
    }
    var icon: String {
        switch self { case .apple: return "🍎"; case .external: return "📦"; case .local: return "🏠" }
    }
}

// MARK: - Package Summary

struct PackageSummary {
    let name: String
    let files: [ParsedFile]
    var totalLines: Int { files.reduce(0) { $0 + $1.lineCount } }

    var declarations: [Declaration] { files.flatMap(\.declarations).filter { !Declaration.invalidNames.contains($0.name) } }
    var realDeclarations: [Declaration] { declarations.filter { $0.kind != .extension } }
    var protocolCount: Int { declarations.filter { $0.kind == .protocol }.count }
    var classCount: Int { declarations.filter { $0.kind == .class }.count }
    var structCount: Int { declarations.filter { $0.kind == .struct }.count }
    var enumCount: Int { declarations.filter { $0.kind == .enum }.count }
    var actorCount: Int { declarations.filter { $0.kind == .actor }.count }
    var extensionCount: Int { declarations.filter { $0.kind == .extension }.count }
}

// MARK: - Report Generator

struct ReportGenerator {

    // Complete Apple public frameworks list (from developer.apple.com)
    private let appleFrameworks: Set<String> = [
        // A
        "Accelerate", "Accessibility", "AccessoryNotifications", "AccessorySetupKit",
        "AccessoryTransportExtension", "AccountDataTransfer", "AccountOrganizationalDataSharing",
        "Accounts", "ActivityKit", "AdAttributionKit", "AddressBook", "AddressBookUI",
        "AdServices", "AdSupport", "AlarmKit", "AppClips", "AppDataTransfer", "AppIntents",
        "AppKit", "AppleArchive", "ApplePencil", "ApplicationServices", "AppMigrationKit",
        "AppTrackingTransparency", "ARKit", "AssetsLibrary", "AudioToolbox", "AudioUnit",
        "AuthenticationServices", "AutomaticAssessmentConfiguration", "Automator",
        // AV
        "AVFAudio", "AVFoundation", "AVKit", "AVRouting",
        // B
        "BackgroundAssets", "BackgroundTasks", "BrowserEngineCore", "BrowserEngineKit",
        "BundleResources", "BusinessChat",
        // C
        "CallKit", "CareKit", "CarKey", "CarPlay", "CFNetwork", "Cinematic", "ClassKit",
        "ClockKit", "CloudKit", "Collaboration", "ColorSync", "Combine", "Compression",
        "CompositorServices", "ContactProvider", "Contacts", "ContactsUI",
        "CoreAnimation", "CoreAudio", "CoreAudioKit", "CoreAudioTypes", "CoreBluetooth",
        "CoreData", "CoreFoundation", "CoreGraphics", "CoreHaptics", "CoreHID", "CoreImage",
        "CoreLocation", "CoreLocationUI", "CoreMedia", "CoreMediaIO", "CoreMIDI", "CoreML",
        "CoreMotion", "CoreNFC", "CoreServices", "CoreSpotlight", "CoreTelephony", "CoreText",
        "CoreTransferable", "CoreVideo", "CoreWLAN", "CreateML", "CreateMLComponents",
        "CryptoKit", "CryptoTokenKit",
        // D
        "Darwin", "DarwinNotify", "DataDetection", "DeveloperToolsSupport", "DeviceActivity",
        "DeviceCheck", "DeviceDiscoveryExtension", "DeviceDiscoveryUI", "DeviceManagement",
        "DiskArbitration", "Dispatch", "Distributed", "dnssd", "DockKit", "DriverKit",
        // E
        "EndpointSecurity", "EnergyKit", "EventKit", "EventKitUI", "ExceptionHandling",
        "ExecutionPolicy", "ExposureNotification", "ExtensionFoundation", "ExtensionKit",
        "ExternalAccessory",
        // F
        "FamilyControls", "FileProvider", "FileProviderUI", "FinanceKit", "FinanceKitUI",
        "FinderSync", "FindMyDevice", "ForceFeedback", "Foundation", "FoundationModels",
        "FSKit",
        // G
        "GameController", "GameKit", "GameplayKit", "GameSave", "GLKit", "GroupActivities", "GSS",
        // H
        "HealthKit", "HealthKitUI", "HomeKit", "Hypervisor",
        // I
        "iAd", "ImageIO", "ImagePlayground", "ImageCaptureCore", "InputMethodKit",
        "Intents", "IntentsUI", "IOBluetooth", "IOBluetoothUI", "IOKit", "IOSurface",
        "IOUSBHost", "iTunesLibrary",
        // J
        "JavaScriptCore", "JournalingSuggestions",
        // K
        "Kernel",
        // L
        "LatentSemanticMapping", "LinkPresentation", "LiveCommunicationKit",
        "LocalAuthentication", "LocalAuthenticationEmbeddedUI", "LockedCameraCapture",
        // M
        "MailKit", "ManagedApp", "ManagedAppDistribution", "ManagedSettings", "ManagedSettingsUI",
        "MapKit", "Matter", "MatterSupport", "MediaAccessibility", "MediaExtension",
        "MediaLibrary", "MediaPlayer", "MediaSetup", "MediaToolbox", "MessageUI", "Messages",
        "Metal", "MetalFX", "MetalKit", "MetalPerformanceShaders", "MetalPerformanceShadersGraph",
        "MetricKit", "MLCompute", "ModelIO", "MultipeerConnectivity", "MusicKit",
        // N
        "NaturalLanguage", "NearbyInteraction", "Network", "NetworkExtension",
        "NotificationCenter",
        // O
        "ObjectiveCRuntime", "Observation", "OpenDirectory", "OpenGLES", "os", "OSLog",
        // P
        "PackageDescription", "PaperKit", "ParavirtualizedGraphics", "PassKit", "PDFKit",
        "PencilKit", "PHASE", "Photos", "PhotosUI",
        "PlaygroundBluetooth", "PlaygroundSupport", "PreferencePanes",
        "ProximityReader", "PushKit", "PushToTalk",
        // Q
        "Quartz", "QuartzCore", "QuickLook", "QuickLookThumbnailing", "QuickLookUI",
        // R
        "RealityKit", "RegexBuilder", "ReplayKit", "ResearchKit", "RoomPlan",
        // S
        "SafariServices", "SafetyKit", "SceneKit", "ScreenCaptureKit", "ScreenSaver",
        "ScreenTime", "ScriptingBridge", "Security", "SecurityFoundation", "SecurityInterface",
        "SensorKit", "SensitiveContentAnalysis", "ServiceManagement", "ShazamKit",
        "SharedWithYou", "simd", "SiriKit", "Social", "SoundAnalysis", "Spatial", "Speech",
        "SpriteKit", "StoreKit", "StoreKitTest",
        "Swift", "SwiftData", "SwiftUI", "SwiftTesting", "Symbols", "Synchronization",
        "System", "SystemConfiguration", "SystemExtensions",
        // T
        "TabletopKit", "TabularData", "ThreadNetwork", "TipKit", "Translation",
        "TVMLKit", "TVServices", "TVUIKit",
        // U
        "UIKit", "UniformTypeIdentifiers", "UserNotifications", "UserNotificationsUI",
        // V
        "VideoSubscriberAccount", "VideoToolbox", "Virtualization", "Vision", "VisionKit",
        // W
        "WalletOrders", "WalletPasses", "WatchConnectivity", "WatchKit", "WeatherKit",
        "WebKit", "WidgetKit", "WorkoutKit",
        // X
        "XCTest", "XPC",
        // Misc/lowercase
        "zlib", "sqlite3", "notify", "ObjectiveC", "Cocoa", "Glibc", "ucrt",
        "MobileCoreServices",
        // Submodule imports
        "os.signpost", "os.OSAllocatedUnfairLock",
        "CoreImage.CIFilterBuiltins", "UIKit.UIGestureRecognizerSubclass",
        "Accelerate.vImage"
    ]

    /// Known Apple private frameworks (from iOS-Private-Frameworks repo).
    /// We match by exact name; this is a representative set of commonly encountered ones.
    private let privateFrameworks: Set<String> = [
        "ACTFramework", "AMPCoreUI", "AOPHaptics", "AOSKit", "APTransport",
        "AccessibilityPlatformTranslation", "AccessibilitySharedSupport", "AccessibilityUtilities",
        "AccountNotification", "AccountSettings", "AccountsDaemon", "AccountsUI",
        "ActionPredictionHeuristics", "ActivityAchievements", "ActivitySharing",
        "AdAnalytics", "AdCore", "AdID", "AdPlatforms", "AdPlatformsInternal",
        "AirPlayReceiver", "AirPlaySender", "AirPlaySupport", "AirTraffic",
        "AnnotationKit", "AppConduit", "AppLaunchStats", "AppPredictionClient",
        "AppPredictionInternal", "AppStoreDaemon", "AppStoreUI",
        "AssertionServices", "AssetCacheServices", "BackBoardServices",
        "BaseBoard", "BiometricKit", "BluetoothManager", "BulletinBoard",
        "CacheDelete", "CalendarUIKit", "CameraKit", "CelestialUI",
        "ChatKit", "ChronoKit", "CloudDocs", "CloudPhotoLibrary",
        "CommonUtilities", "CommunicationsFilter", "ContentKit",
        "ControlCenterUI", "ControlCenterUIKit", "CoreBrightness", "CoreCDP",
        "CoreDuet", "CoreFollowUp", "CoreHandwriting", "CoreMediaStream",
        "CorePDF", "CorePhoneNumbers", "CorePrediction", "CoreRecents",
        "CoreSDB", "CoreSpeech", "CoreSuggestions", "CoreSymbolication",
        "CoverSheet", "DataDetectorsCore", "DeviceIdentity",
        "DiagnosticExtensions", "DiagnosticLogCollection",
        "DuetActivityScheduler", "DuetExpertCenter",
        "FMClient", "FMCore", "FMCoreLite", "FMF", "FMFSupport",
        "FMIPClient", "FTServices", "FrontBoard", "FrontBoardServices",
        "GeoServices", "GraphicsServices",
        "HMFoundation", "HomeSharing",
        "IMCore", "IMDPersistence", "IMFoundation", "IMSharedUtilities",
        "IMAVCore", "IDSFoundation",
        "MailServices", "ManagedConfiguration", "MapsSupport",
        "MediaRemote", "MediaServices", "MobileBackup", "MobileBluetooth",
        "MobileCoreServices", "MobileIcons", "MobileInstallation",
        "MobileKeyBag", "MobileTimer", "MobileWiFi",
        "NanoPreferencesSync", "NanoRegistry", "NavigationKit",
        "NewsCore", "NotesShared", "NotesUI",
        "OfficeImport", "PBBridgeSupport", "Pegasus", "PersistentConnection",
        "PhotoFoundation", "PhotoLibrary", "PhotosGraph", "PhotosPlayer",
        "PowerLog", "Preferences", "PreferencesUI",
        "ProactiveSupport", "ProtectedCloudStorage", "PrototypeTools",
        "RemoteManagement", "RemoteUI",
        "ScreenReading", "SearchFoundation", "Sharing",
        "SlideshowKit", "SoftwareUpdateServices", "SpringBoardFoundation",
        "SpringBoardServices", "SpringBoardUI", "SpringBoardUIServices",
        "StoreServices", "Symbolication",
        "TCC", "TelephonyUI", "TextInput", "TextInputUI",
        "TouchRemote", "TrustedPeers",
        "UIAccessibility", "UIFoundation", "UIKitCore", "UIKitServices",
        "UsageTracking", "VoiceServices", "VoiceTrigger",
        "WeatherFoundation", "WebBookmarks", "WebCore",
        "WiFiKit", "WorkflowKit"
    ]

    /// Max declarations to show in one package graph (performance + readability)
    private let maxGraphDeclarations = 100

    func generate(
        graph: DependencyGraph,
        outputPath: String,
        parsedFiles: [ParsedFile],
        branchName: String,
        authorStats: [String: AuthorStats],
        projectName: String = "",
        metadata: ProjectMetadata = ProjectMetadata(),
        monkeyPatchedLibs: [MonkeyPatchedLibs.DetectedLib] = [],
        branchStats: BranchStats = BranchStats(),
        semanticStats: SemanticStats = SemanticStats(),
        churnFiles: [FileChurnStat] = [],
        repoPath: String = "",
        apResults: [APResult] = [],
        oopStats: OOPvsPOPStats? = nil,
        securityScore: SecurityScore? = nil,
        renderModules: Bool = true,
        githubURL: String = "",
        headCommit: String = ""
    ) throws {
        // Filter out monkey-patched library files
        let mpLibPaths = monkeyPatchedLibs.map(\.path)
        let isMonkeyPatched: (String) -> Bool = { filePath in
            mpLibPaths.contains { filePath.contains("/\($0)/") }
        }
        let projectFiles = parsedFiles.filter { !isMonkeyPatched($0.filePath) }

        // Hotspots: exclude monkey-patched libs
        let hotspots = graph.getTopHotspots(limit: 20).filter { !isMonkeyPatched($0.path) }.prefix(15)
        let fileMap = Dictionary(uniqueKeysWithValues: parsedFiles.map { ($0.filePath, $0) })
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        print("\(ts())  Generating HTML sections...")

        // ─── 1. Team ───
        // Compute per-author module counts from file git metadata
        var authorModuleCounts: [String: [String: Int]] = [:]
        for file in projectFiles {
            let pkg = file.packageName.isEmpty ? "App" : file.packageName
            for author in file.gitMetadata.topAuthors {
                authorModuleCounts[author, default: [:]][pkg, default: 0] += 1
            }
        }

        let topTeam = authorStats.sorted {
            if $0.value.totalCommits != $1.value.totalCommits {
                return $0.value.totalCommits > $1.value.totalCommits
            }
            return $0.value.filesModified > $1.value.filesModified
        }.prefix(15)
        let teamRows = topTeam.map { (author, info) -> String in
            let first = info.firstCommitDate > 0 ? dateFmt.string(from: Date(timeIntervalSince1970: info.firstCommitDate)) : "—"
            let last = info.lastCommitDate > 0 ? dateFmt.string(from: Date(timeIntervalSince1970: info.lastCommitDate)) : "—"
            let name = info.displayName.isEmpty ? author : info.displayName
            // Top-3 modules for this author
            let modules = (authorModuleCounts[author] ?? [:])
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { mod -> String in
                    let anchor = mod.key.replacingOccurrences(of: " ", with: "-")
                    return "<a href='#pkg-\(anchor)' class='tag tag-local pkg-link-inline' style='font-size:11px'>\(esc(mod.key))</a>"
                }
                .joined(separator: " ")
            let loc = info.totalLOCAdded > 0 ? info.totalLOCAdded.formatted() : "—"
            let locPerCommit = info.totalCommits > 0 && info.totalLOCAdded > 0
                ? (info.totalLOCAdded / info.totalCommits).formatted()
                : "—"
            return "<tr><td>\(esc(name))</td><td>\(info.filesModified)</td><td>\(info.totalCommits)</td><td>\(loc)</td><td>\(locPerCommit)</td><td>\(first)</td><td>\(last)</td><td>\(modules)</td></tr>"
        }.joined(separator: "\n")

        // ─── 2. Imports ───
        let allImports = Set(projectFiles.flatMap(\.imports))
        let localPackageNames = Set(projectFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })
        let localModuleNames = Set(projectFiles.filter { !$0.packageName.isEmpty }.map(\.moduleName)).union(localPackageNames)
        let localFileNames = Set(projectFiles.map(\.fileNameWithoutExtension))

        // C/C++ standard headers and system includes to exclude from External Dependencies
        let cStandardHeaders: Set<String> = [
            "stdio", "stdlib", "string", "strings", "math", "time", "errno", "assert", "float",
            "stdint", "stdbool", "stddef", "stdarg", "limits", "inttypes", "ctype",
            "signal", "setjmp", "locale", "wchar", "wctype", "complex", "tgmath", "fenv",
            // C++ standard library
            "iostream", "fstream", "sstream", "ostream", "istream", "streambuf",
            "string_view", "array", "vector", "list", "deque", "set", "map", "stack", "queue",
            "unordered_map", "unordered_set", "bitset", "tuple", "variant", "optional", "any",
            "memory", "new", "functional", "algorithm", "iterator", "numeric", "utility",
            "atomic", "mutex", "condition_variable", "thread", "future", "chrono",
            "initializer_list", "type_traits", "typeindex", "typeinfo", "exception",
            "cassert", "cerrno", "cmath", "cstdio", "cstdlib", "cstring", "cstddef", "cstdint",
            "cstdbool", "cinttypes", "cfloat", "climits", "csignal", "clocale",
            // POSIX / Unix system headers
            "unistd", "fcntl", "pthread", "poll", "dlfcn",
            "sys", "net", "netdb", "netinet", "arpa", "ifaddrs",
            "mach", "mach-o", "libkern", "dispatch", "objc",
            // x86/ARM intrinsics
            "emmintrin", "immintrin", "xmmintrin", "arm_neon", "intrin",
            // Windows
            "windows", "winsock2", "ws2tcpip", "mswsock", "d3d11", "direct", "vadefs",
            // Junk from relative imports
            "..", ".", "",
        ]

        var classifiedImports: [ImportKind: Set<String>] = [.apple: [], .external: [], .local: []]
        var detectedPrivateFrameworks: Set<String> = []
        for imp in allImports {
            let baseName = imp.components(separatedBy: ".").first ?? imp
            let lowerBase = baseName.lowercased()
            // Skip C/C++ standard headers and junk
            if cStandardHeaders.contains(baseName) || cStandardHeaders.contains(lowerBase) { continue }
            // Skip short single-word imports that look like C headers (all lowercase, no uppercase)
            if imp.count <= 3 && imp == imp.lowercased() { continue }
            if appleFrameworks.contains(imp) || appleFrameworks.contains(baseName) {
                classifiedImports[.apple, default: []].insert(imp)
            } else if localModuleNames.contains(imp) || localPackageNames.contains(imp) {
                classifiedImports[.local, default: []].insert(imp)
            } else if localFileNames.contains(imp) {
                continue
            } else {
                if privateFrameworks.contains(baseName) {
                    detectedPrivateFrameworks.insert(imp)
                }
                classifiedImports[.external, default: []].insert(imp)
            }
        }
        var packageBuildSystem: [String: BuildSystem] = [:]
        for file in projectFiles where !file.packageName.isEmpty {
            if packageBuildSystem[file.packageName] == nil || file.buildSystem != .unknown {
                packageBuildSystem[file.packageName] = file.buildSystem
            }
        }

        let metalPackages = Set(metadata.metalFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })

        // ─── Architecture ───
        let externalLibsCount = classifiedImports[.external]?.count ?? 0
        let externalLibsHTML: String = {
            guard let extNames = classifiedImports[.external], !extNames.isEmpty else { return "" }
            let cleaned = Set(extNames.map { $0.components(separatedBy: ":").first ?? $0 })
            return buildCategorizedFrameworksHTML(frameworks: cleaned, tagClass: "tag-external")
        }()

        // Architecture LAYERS — classify files by path patterns
        let archAnalyzer = ArchAnalyzer()
        var layerCounts: [String: (files: Int, lines: Int)] = [:]
        for file in projectFiles {
            let layer = archAnalyzer.classifyLayer(file.filePath)
            var entry = layerCounts[layer] ?? (files: 0, lines: 0)
            entry.files += 1
            entry.lines += file.lineCount
            layerCounts[layer] = entry
        }
        let layerOrder = ["UI / Views", "Models", "API / Networking", "Persistence", "Auth", "Config", "Utilities", "Tests", "Core"]
        let layerEmoji: [String: String] = [
            "UI / Views":       "📱",
            "Models":           "📦",
            "API / Networking": "🌐",
            "Persistence":      "🗄️",
            "Auth":             "🔐",
            "Config":           "⚙️",
            "Utilities":        "🧰",
            "Tests":            "🧪",
            "Core":             "🔩",
        ]
        let layersHTML: String = {
            let sorted = layerOrder.compactMap { name -> (String, Int, Int)? in
                guard let e = layerCounts[name] else { return nil }
                return (name, e.files, e.lines)
            } + layerCounts.keys
                .filter { !layerOrder.contains($0) }
                .sorted()
                .compactMap { name -> (String, Int, Int)? in
                    guard let e = layerCounts[name] else { return nil }
                    return (name, e.files, e.lines)
                }
            guard !sorted.isEmpty else { return "" }
            let maxLines = sorted.map(\.2).max() ?? 1
            let items = sorted.map { (name, files, lines) -> String in
                let pct = maxLines > 0 ? Int(Double(lines) / Double(maxLines) * 100) : 0
                let icon = layerEmoji[name] ?? "•"
                let locStr = lines.formatted()
                return """
                <div class="arch-layer">\
                <div class="layer-bar-row">\
                <span class="layer-icon">\(icon)</span>\
                <span class="layer-name">\(esc(name))</span>\
                <span class="layer-count">\(files) files · \(locStr) loc</span>\
                </div>\
                <div class="layer-bar-track"><div class="layer-bar-fill" style="width:\(pct)%"></div></div>\
                </div>
                """
            }.joined(separator: "\n")
            return "<div class='arch-layers'>\(items)</div>"
        }()

        // Architecture PATTERN — detect from file/declaration naming conventions
        // Exclude build-system infrastructure (bazel rules, BSP servers, etc.) — not app logic
        let buildSystemComponents: [String] = [
            "/build-system/", "/bazel-rules/", "/rules_apple/", "/rules_swift/",
            "/rules_xcodeproj/", "/apple_support/", "/bazel-", "/.build/",
        ]
        let isBuildSystem: (String) -> Bool = { path in
            buildSystemComponents.contains { path.contains($0) }
                || URL(fileURLWithPath: path).pathComponents.contains { $0.hasPrefix("rules_") }
        }
        let archFiles = projectFiles.filter { !isBuildSystem($0.filePath) }
        print("\(ts())  Detecting architecture pattern...")
        let archDetection = archAnalyzer.detectPattern(files: archFiles)
        if let top = archDetection.top {
            let alts = archDetection.patterns.dropFirst().map { "\($0.name) \(Int($0.confidence * 100))%" }.joined(separator: ", ")
            let altStr = alts.isEmpty ? "" : "  (also: \(alts))"
            print("\(ts())  Architecture: \(top.name) \(Int(top.confidence * 100))%\(altStr)")
        } else {
            print("\(ts())  Architecture: not detected")
        }
        let archPatternSubCardHTML: String = {
            let hasTop = archDetection.top.map { $0.confidence >= 0.15 } ?? false
            guard hasTop || archDetection.commandLetter != nil || archDetection.eventBusLetter != nil else { return "" }

            func makeLetterCard(_ l: ArchLetter, orthogonal: Bool = false) -> String {
                let healthClass: String
                switch l.health {
                case .present: healthClass = "health-present"
                case .weak:    healthClass = "health-weak"
                case .missing: healthClass = "health-missing"
                }
                let extraClass = orthogonal ? " orthogonal" : ""
                let primaryCount = l.fileCount > 0 ? l.fileCount : l.declCount
                let countStr = primaryCount > 0 ? String(primaryCount) : "—"
                let linkHTML: String = {
                    let paths = l.examplePaths.prefix(3)
                    guard !paths.isEmpty else { return "" }
                    let links = paths.map { path -> String in
                        let fname = URL(fileURLWithPath: path).lastPathComponent
                        return vsLink(path: path, label: esc(fname))
                    }
                    return "<div class='arch-letter-link'>\(links.joined(separator: " "))</div>"
                }()
                return """
                <div class='arch-letter-card \(healthClass)\(extraClass)'>\
                <div class='arch-letter-big'>\(esc(l.letter))</div>\
                <div class='arch-letter-name'>\(esc(l.fullName))</div>\
                <div class='arch-letter-count'>\(countStr)</div>\
                <div class='arch-letter-detail'>\(esc(l.detail))</div>\
                \(linkHTML)\
                </div>
                """
            }

            guard let top = archDetection.top, top.confidence >= 0.15 else {
                // No arch pattern detected — show Cmd and E standalone if available
                let cmdCard = archDetection.commandLetter.map { makeLetterCard($0) } ?? ""
                let eCard = archDetection.eventBusLetter.map { makeLetterCard($0) } ?? ""
                let allCards = [cmdCard, eCard].filter { !$0.isEmpty }.joined(separator: "\n")
                guard !allCards.isEmpty else { return "" }
                return """
                <div class='arch-pattern-wrap'>
                <div class='arch-letter-row'>\(allCards)</div>
                </div>
                """
            }

            let patternCards = top.letters.map { makeLetterCard($0) }.joined(separator: "\n")
            let cmdCard = archDetection.commandLetter.map { makeLetterCard($0, orthogonal: true) } ?? ""
            let eCard = archDetection.eventBusLetter.map { makeLetterCard($0, orthogonal: true) } ?? ""
            let modifierCards = [cmdCard, eCard].filter { !$0.isEmpty }
            let letterCards: String
            if modifierCards.isEmpty {
                letterCards = patternCards
            } else {
                let sep = "<div class='arch-letter-sep'></div>"
                letterCards = patternCards + "\n" + sep + "\n" + modifierCards.joined(separator: "\n")
            }

            let confBars = archDetection.patterns.map { p -> String in
                let pct = Int(p.confidence * 100)
                let isTop = p.name == top.name
                let nameStyle = isTop ? "font-weight:700;color:var(--text)" : "color:var(--text2)"
                let barColor = isTop ? "var(--accent)" : "var(--text3)"
                let attrsHTML: String = {
                    let nonZero = p.letters.filter { $0.fileCount > 0 || $0.declCount > 0 }
                    if !nonZero.isEmpty {
                        let attrs = nonZero.map { l -> String in
                            let count = l.fileCount > 0 ? l.fileCount : l.declCount
                            return "\(esc(l.fullName)) \(count)"
                        }.joined(separator: ", ")
                        return "<span class='arch-conf-attrs'>similarity based on: \(attrs)</span>"
                    } else if let hint = p.hint {
                        return "<span class='arch-conf-attrs'>similarity based on: \(esc(hint))</span>"
                    }
                    return ""
                }()
                return """
                <div class='arch-conf-row'>\
                <span class='arch-conf-name' style='\(nameStyle)'>\(esc(p.name))</span>\
                <div class='arch-conf-track'><div class='arch-conf-fill' style='width:\(pct)%;background:\(barColor)'></div></div>\
                <span class='arch-conf-pct' style='color:\(barColor)'>\(pct)%</span>\
                \(attrsHTML)\
                </div>
                """
            }.joined(separator: "\n")
            return """
            <div class='arch-pattern-wrap'>
            <div class='arch-conf-list'>\(confBars)</div>
            <div class='arch-letter-row'>\(letterCards)</div>
            </div>
            """
        }()

        // Architecture COMPONENTS — detect from Apple frameworks used
        let usedAppleFrameworks = classifiedImports[.apple] ?? []
        let detectedComponents = archAnalyzer.detectComponents(appleFrameworks: usedAppleFrameworks)
        // Every framework name claimed by a detected component — excluded from the raw list below
        let componentCoveredFrameworks: Set<String> = detectedComponents.reduce(into: []) { $0.formUnion($1.frameworks) }
        let componentsHTML: String = {
            guard !detectedComponents.isEmpty else { return "" }
            let items = detectedComponents.map { c -> String in
                "<div class='component-item'><span class='component-icon'>\(c.icon)</span><div><div class='component-name'>\(esc(c.name))</div><div class='component-detail'>\(esc(c.detail))</div></div></div>"
            }.joined(separator: "\n")
            return "<div class='component-grid'>\(items)</div>"
        }()

        // ─── Programming Methods (design patterns · data structures · algorithms · magic constants) ───
        // Always rendered. Runs through the single ConstructScanner core — one
        // shared source read for all detectors.
        print("\(ts())  Detecting programming methods...")
        let constructs = ConstructScanner().scan(files: archFiles) { print("\(ts())  \($0)") }
        let detectedPatterns = constructs.patterns
        let dsMatches = constructs.dataStructures
        let algoMatches = constructs.algorithms
        let constantMatches = constructs.magicConstants

        // Design Patterns
        let designPatternsSubCardHTML: String = {
            guard !detectedPatterns.isEmpty else { return "" }
            let byCategory = Dictionary(grouping: detectedPatterns, by: \.category)
            let cols = PatternCategory.allCases.map { cat -> String in
                let items = (byCategory[cat] ?? []).map { p -> String in
                    let fileName = URL(fileURLWithPath: p.examplePath).lastPathComponent
                    let fileLink = vsLink(path: p.examplePath, label: esc(fileName))
                    let nameHTML: String
                    if let url = WikipediaLinks.url(forPattern: p.name) {
                        nameHTML = "<a class='dp-item-name ds-wiki-link' href=\"\(url)\" target='_blank' rel='noopener noreferrer' title='Wikipedia: \(esc(p.name))'>\(esc(p.name))</a>"
                    } else {
                        nameHTML = "<span class='dp-item-name'>\(esc(p.name))</span>"
                    }
                    let idiomBadge = p.isLanguageIdiom ? " <span class='dp-idiom-badge' title='Absorbed into the language — most real Swift codebases have this, not necessarily a deliberate pattern choice'>language feature</span>" : ""
                    return """
                    <div class='dp-item\(p.isLanguageIdiom ? " dp-item-idiom" : "")'>\
                    <div class='dp-item-top'>\(nameHTML)\(idiomBadge)<span class='dp-item-count'>\(p.count)</span></div>\
                    <div class='dp-item-detail'>\(esc(p.detail))</div>\
                    <div class='dp-item-link'>\(fileLink)</div>\
                    </div>
                    """
                }.joined(separator: "\n")
                return "<div class='dp-col'><div class='dp-col-head'>\(cat.icon) \(cat.rawValue)</div>\(items.isEmpty ? "<div style='color:var(--text3);font-size:12px;font-style:italic'>None detected</div>" : items)</div>"
            }.joined(separator: "\n")
            return "<div class='dp-grid'>\(cols)</div>"
        }()
        // Deliberate pattern choices only — Extension/Lazy Initialization/Monitor
        // Object are language features almost every codebase "has", not a signal
        // of how many patterns were chosen, so they're shown (muted, badged) but
        // excluded from this headline count.
        let totalPatternCount = detectedPatterns.filter { !$0.isLanguageIdiom }.count

        // Data Structures
        let dsSubCardHTML: String = buildDSHTML(dsMatches)

        // Algorithms
        let algoSubCardHTML: String = buildAlgoHTML(algoMatches)

        // Magic Constants
        let constantsSubCardHTML: String = buildConstantsHTML(constantMatches)

        // Apple Frameworks — exclude any already shown in Components
        let filteredAppleFrameworks = usedAppleFrameworks.subtracting(componentCoveredFrameworks)
        let appleFrameworksCount = filteredAppleFrameworks.count
        let appleFrameworksHTML: String = {
            guard !filteredAppleFrameworks.isEmpty else { return "" }
            return buildCategorizedFrameworksHTML(frameworks: filteredAppleFrameworks, tagClass: "tag-apple")
        }()

        // ─── Security Risks ───
        print("\(ts())  Running security checks...")
        let resolvedAPResults = apResults.isEmpty
            ? SecurityAnalyzer.run(files: projectFiles, repoPath: repoPath)
            : apResults
        let swiftFileCountForScore = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count
        let resolvedSecurityScore = securityScore
            ?? SecurityAnalyzer.computeScore(resolvedAPResults, fileCount: swiftFileCountForScore)
        let apCardHTML = buildSecurityHTML(resolvedAPResults, score: resolvedSecurityScore)
        let securityScoreJSONLiteral = securityScoreJSON(resolvedSecurityScore)

        // ─── Traffic ───
        print("\(ts())  Scanning traffic signals...")
        let trafficResult = TrafficScanner().scan(files: projectFiles)
        if trafficResult.hasData {
            print("\(ts())  Traffic: \(trafficResult.inbound.count) inbound · \(trafficResult.outbound.count) outbound")
        }

        // ─── OOP vs POP ───
        let resolvedOOPStats = oopStats ?? OOPvsPOPAnalyzer.analyze(files: projectFiles)
        let oopCardHTML = buildOOPvsPOPHTML(resolvedOOPStats)

        // ─── Pre-computed card HTML strings ───

        // Git: Branch Management
        let branchSubCard: String = {
            guard branchStats.total > 0 else { return "" }

            func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }

            let rollbackRate: String = {
                guard branchStats.totalMainCommits > 0 else { return "0%" }
                let pct = Double(branchStats.rollbackCount) / Double(branchStats.totalMainCommits) * 100
                return "\(fmt1(pct))%"
            }()

            var h = "<div class='bm-grid'>"
            if branchStats.avgLifetimeDays > 0 {
                h += "<div class='bm-card'><div class='bm-value'>\(fmt1(branchStats.avgLifetimeDays)) days</div><div class='bm-label'>Avg Branch Lifetime</div></div>"
            }
            if branchStats.avgTTMDays > 0 {
                h += "<div class='bm-card'><div class='bm-value'>\(fmt1(branchStats.avgTTMDays)) days</div><div class='bm-label'>Avg Time to Merge</div></div>"
            }
            if branchStats.avgIntegDelayHours > 0 {
                h += "<div class='bm-card'><div class='bm-value'>\(fmt1(branchStats.avgIntegDelayHours))h</div><div class='bm-label'>Integration Delay</div></div>"
            }
            h += "<div class='bm-card'><div class='bm-value'>\(branchStats.maxDepth)</div><div class='bm-label'>Branch Depth</div></div>"
            h += "<div class='bm-card'><div class='bm-value'>\(rollbackRate)</div><div class='bm-label'>Rollback Rate</div></div>"
            if !branchStats.peakCommitDay.isEmpty {
                h += "<div class='bm-card'><div class='bm-value' style='font-size:16px'>\(esc(branchStats.peakCommitDay))</div><div class='bm-label'>Peak Commit Day</div></div>"
            }
            h += "</div>"

            if branchStats.rollbackCount > 0 {
                h += "<p style='font-size:12px;color:var(--text3);margin:0 0 12px'>\(branchStats.rollbackCount) revert/rollback commits out of \(branchStats.totalMainCommits) on main.</p>"
            }

            if !branchStats.staleBranches.isEmpty {
                let rows = branchStats.staleBranches.map { b -> String in
                    "<tr><td class='mono' style='font-size:12px'>\(esc(b.name))</td><td class='mono' style='color:var(--red)'>\(b.daysInactive)d</td></tr>"
                }.joined()
                h += "<div class='table-wrap'><table class='file-table'><thead><tr><th>Stale Branch</th><th>Inactive</th></tr></thead><tbody>\(rows)</tbody></table></div>"
            }
            return h
        }()

        // Git: Branching Model
        let branchingModelSubCardHTML: String = {
            let bm = branchStats.branchingModel
            guard bm.model != .unknown, !bm.modelScores.isEmpty else { return "" }
            let totalScore = bm.modelScores.reduce(0.0) { $0 + $1.score }
            guard totalScore > 0 else { return "" }

            // Confidence bars (reuse arch-conf-* classes, widen name column)
            let confBars = bm.modelScores.map { entry -> String in
                let pct = Int((entry.score / totalScore) * 100)
                let isTop = entry.model == bm.model
                let nameStyle = isTop
                    ? "font-weight:700;color:var(--text)"
                    : "color:var(--text2)"
                let barColor = isTop ? "var(--accent)" : "var(--text3)"
                let attrs = isTop
                    ? "<span class='arch-conf-attrs'>\(esc(entry.model.detail))</span>"
                    : ""
                return """
                <div class='arch-conf-row'>\
                <span class='arch-conf-name bmmodel-conf-name' style='\(nameStyle)'>\(entry.model.icon) \(esc(entry.model.rawValue))</span>\
                <div class='arch-conf-track'><div class='arch-conf-fill' style='width:\(pct)%;background:\(barColor)'></div></div>\
                <span class='arch-conf-pct' style='color:\(barColor)'>\(pct)%</span>\
                \(attrs)\
                </div>
                """
            }.joined(separator: "\n")

            // Evidence signals
            let signalsHTML: String = {
                guard !bm.signals.isEmpty else { return "" }
                let items = bm.signals.map { sig -> String in
                    "<div class='bmmodel-signal'><span>•</span><span>\(esc(sig))</span></div>"
                }.joined(separator: "\n")
                return "<div class='bmmodel-signals'>\(items)</div>"
            }()

            // Key metric badges (merge ratio, avg lifetime, merges/day)
            var metricsItems: [String] = []
            if bm.mergeCommitRatio > 0 {
                metricsItems.append("merge ratio \(Int(bm.mergeCommitRatio * 100))%")
            }
            if branchStats.avgLifetimeDays > 0 {
                metricsItems.append("avg branch \(String(format: "%.1f", branchStats.avgLifetimeDays))d")
            }
            if bm.mergesPerDay > 0 {
                metricsItems.append("\(String(format: "%.1f", bm.mergesPerDay)) merges/day")
            }
            let metricsHTML = metricsItems.isEmpty ? "" :
                "<p style='font-size:11px;color:var(--text3);margin:10px 0 0;font-family:\"SF Mono\",Menlo,monospace'>\(metricsItems.joined(separator: " · "))</p>"

            return """
            <div class='arch-conf-list'>\(confBars)</div>
            \(signalsHTML)
            \(metricsHTML)
            """
        }()

        // Git: Code Churn
        let churnSubCard: String = {
            guard !churnFiles.isEmpty else { return "<p style='color:var(--text3)'>No git history available.</p>" }
            let rows = churnFiles.prefix(15).map { stat -> String in
                let name = URL(fileURLWithPath: stat.path).lastPathComponent
                let parts = stat.path.components(separatedBy: "/")
                let folder = parts.count >= 2 ? parts.dropLast().suffix(2).joined(separator: "/") + "/" : ""
                let folderHtml = folder.isEmpty ? "" : "<span style='color:var(--text3);font-weight:400'>\(esc(folder))</span>"
                let absPath = repoPath.isEmpty ? stat.path : "\(repoPath)/\(stat.path)"
                let fileLink = vsLink(path: absPath, label: "<strong>\(esc(name))</strong>")
                return "<tr><td>\(folderHtml)\(fileLink)</td><td class='mono' style='white-space:nowrap'>\(stat.changeCount)</td></tr>"
            }.joined(separator: "\n")
            return "<div class='table-wrap'><table class='file-table'><thead><tr><th>File</th><th>Changes</th></tr></thead><tbody>\(rows)</tbody></table></div>"
        }()

        // Git: Semantic Standards (goscope progress-bar style)
        let semanticSubCard: String = {
            guard semanticStats.totalCommits > 0 else { return "<p style='color:var(--text3)'>No commit history available.</p>" }
            var h = ""
            // Semver Tags row
            let semverPct = semanticStats.totalTags > 0 ? semanticStats.semverTags * 100 / semanticStats.totalTags : 0
            var semTagLabel = "No tags found"
            if semanticStats.totalTags > 0 {
                semTagLabel = "\(semanticStats.semverTags) / \(semanticStats.totalTags) tags follow semver"
                if !semanticStats.latestSemver.isEmpty { semTagLabel += " · latest: <strong>\(esc(semanticStats.latestSemver))</strong>" }
            }
            h += "<div class='sem-row'><span class='sem-label'>🏷️ Semver Tags</span><span class='sem-bar-wrap'><span class='sem-bar' style='width:\(semverPct)%'></span></span><span class='sem-stat'>\(semTagLabel)</span></div>"
            // Conventional Commits row
            let convPct = semanticStats.conventionalCommits * 100 / semanticStats.totalCommits
            h += "<div class='sem-row'><span class='sem-label'>📝 Conv. Commits</span><span class='sem-bar-wrap'><span class='sem-bar' style='width:\(convPct)%'></span></span><span class='sem-stat'>\(semanticStats.conventionalCommits) / \(semanticStats.totalCommits) structured</span></div>"
            // Type breakdown
            if !semanticStats.topPrefixes.isEmpty {
                h += "<div class='sem-type-row'>"
                for p in semanticStats.topPrefixes {
                    h += "<span class='sem-type-badge'>\(esc(p.prefix)) <strong>\(p.count)</strong></span>"
                }
                h += "</div>"
            }
            // Non-conventional samples — one-liner joined by " / "
            if !semanticStats.samples.isEmpty {
                let joined = semanticStats.samples.map { esc($0) }.joined(separator: " /&nbsp;")
                h += "<div class='sem-samples'><span style='color:var(--text3);font-size:11px;font-weight:600'>Non-standard samples:</span><div class='sem-sample'>\(joined)</div></div>"
            }
            return h
        }()

        // Architecture: Local Packages sub-card content
        let localPackagesSubCardHTML: String = {
            let totalLinesAll = projectFiles.reduce(0) { $0 + $1.lineCount }
            var pkgLines: [String: Int] = [:]
            var pkgDecls: [String: Int] = [:]
            var pkgFileMap: [String: [ParsedFile]] = [:]
            for file in projectFiles {
                let key = file.packageName.isEmpty ? "App" : file.packageName
                pkgLines[key, default: 0] += file.lineCount
                pkgDecls[key, default: 0] += file.declarations.filter { $0.kind != .extension }.count
                pkgFileMap[key, default: []].append(file)
            }
            let lineThreshold = Double(totalLinesAll) * 0.015

            guard let localNames = classifiedImports[.local], !localNames.isEmpty else {
                var c = ""
                if !detectedPrivateFrameworks.isEmpty {
                    let t = detectedPrivateFrameworks.sorted().map { "<span class='tag tag-private'>\($0)</span>" }.joined(separator: " ")
                    c += "<div><p class='private-warn'>🔒 Possible Private Frameworks (\(detectedPrivateFrameworks.count)) — may cause App Store rejection:</p><div class='tag-cloud'>\(t)</div></div>"
                }
                return c
            }

            // Build tag HTML for one package
            func makeTag(_ name: String, isApp: Bool = false) -> String {
                let anchor = name.replacingOccurrences(of: " ", with: "-")
                if isApp {
                    let loc = pkgLines["App", default: 0]
                    return "<a href='#pkg-App' class='tag tag-local pkg-link pkg-major'><span class='pkg-name'>📱 App</span><span class='bs-badge-right'>\(loc.formatted()) loc</span></a>"
                }
                let lines = pkgLines[name, default: 0]
                let decls = pkgDecls[name, default: 0]
                let isMajor = Double(lines) >= lineThreshold && lines >= 10_000 && decls >= 80
                let majorClass = isMajor ? " pkg-major" : ""
                let bs = packageBuildSystem[name]
                let bsLabel = bs != nil && bs != .unknown ? "<span class='bs-badge-right'>\(bs!.rawValue)</span>" : ""
                let metalIcon = metalPackages.contains(name) ? "🔘 " : ""
                return "<a href='#pkg-\(anchor)' class='tag tag-local pkg-link\(majorClass)'><span class='pkg-name'>\(metalIcon)\(name)</span>\(bsLabel)</a>"
            }

            // ── Package categorisation via weighted scoring ──────────────────
            enum PkgCat { case ui, data, arch, dev }

            func scorePackage(_ name: String) -> PkgCat {
                let files  = pkgFileMap[name] ?? []
                let imps   = Set(files.flatMap(\.imports))
                let decls  = files.flatMap(\.declarations)
                let lower  = name.lowercased()
                var sc: [PkgCat: Int] = [.ui: 0, .data: 0, .arch: 0, .dev: 0]

                // ── DEV TOOLS ──────────────────────────────────────────────
                for imp in ["SwiftSyntax","SwiftLintFramework","ArgumentParser","PackageDescription"] where imps.contains(imp) {
                    sc[.dev, default: 0] += 5
                }
                for d in decls where ["BuildToolPlugin","CommandPlugin","Macro","ExpressionMacro","PeerMacro","MemberMacro"].contains(d.name) {
                    sc[.dev, default: 0] += 5
                }
                if files.contains(where: { let p = $0.filePath.lowercased()
                    return p.contains("/plugin") || p.contains("/macro") || p.contains("/tools/") || p.contains("/linter/") || p.contains("/generator/")
                }) { sc[.dev, default: 0] += 5 }
                for w in ["plugin","macro","tool","dev","lint","mock","testsupport","snapshot"] where lower.contains(w) {
                    sc[.dev, default: 0] += 2
                }
                if imps.contains("XCTest") { sc[.dev, default: 0] += 1 }

                // ── UI / MEDIA ─────────────────────────────────────────────
                let uiHeavy: Set<String> = ["UIKit","SwiftUI","AppKit","WatchKit","TVUIKit",
                    "CoreGraphics","QuartzCore","AVFoundation","AVKit","Metal","MetalKit",
                    "SceneKit","SpriteKit","ARKit","RealityKit","CoreImage","CoreAnimation",
                    "MediaPlayer","PhotosUI","WidgetKit","VisionKit","PencilKit","GameKit"]
                for imp in uiHeavy where imps.contains(imp) { sc[.ui, default: 0] += 4 }
                let uiSuffixes = ["View","ViewController","Cell","Button","Label","Screen","Animation","Renderer","Shape","Drawing","Layer"]
                for d in decls where uiSuffixes.contains(where: { d.name.hasSuffix($0) }) { sc[.ui, default: 0] += 3 }
                if files.contains(where: { let p = $0.filePath.lowercased()
                    return p.contains("/views/") || p.contains("/screens/") || p.contains("/components/") || p.contains("/animations/") || p.contains("/ui/")
                }) { sc[.ui, default: 0] += 4 }
                for imp in ["CoreText","CoreVideo","ImageIO","PDFKit","QuickLook"] where imps.contains(imp) { sc[.ui, default: 0] += 2 }
                for file in files {
                    let fn = file.fileNameWithoutExtension.lowercased()
                    if ["view","button","slider","label","image","animation","drawing","renderer","shape","color","screen"].contains(where: { fn.contains($0) }) {
                        sc[.ui, default: 0] += 2
                    }
                }
                for w in ["ui","media","video","audio","player","animation","lottie","rendering","graphics","design","theme"] where lower.contains(w) {
                    sc[.ui, default: 0] += 1
                }

                // ── DATA / NETWORKING ──────────────────────────────────────
                let dataHeavy: Set<String> = ["CoreData","CloudKit","RealmSwift","GRDB","SwiftData",
                    "UserNotifications","CoreSpotlight","KeychainAccess","FMDB"]
                for imp in dataHeavy where imps.contains(imp) { sc[.data, default: 0] += 4 }
                let dataKw = ["Model","DTO","Entity","Response","Request","Repository","Cache","Database","Realm","Keychain"]
                for d in decls where dataKw.contains(where: { d.name.hasSuffix($0) || d.name.hasPrefix($0) }) {
                    sc[.data, default: 0] += 3
                }
                if files.contains(where: { let p = $0.filePath.lowercased()
                    return p.contains("/models/") || p.contains("/dto/") || p.contains("/entities/") ||
                           p.contains("/database/") || p.contains("/persistence/") ||
                           p.contains("/api/") || p.contains("/network/") || p.contains("/requests/")
                }) { sc[.data, default: 0] += 4 }
                if imps.contains("Network")   { sc[.data, default: 0] += 2 }
                if imps.contains("CryptoKit") { sc[.data, default: 0] += 2 }
                for file in files {
                    let fn = file.fileNameWithoutExtension.lowercased()
                    if ["repository","apiclient","cache","keychain","database","networking","endpoint","mapper"].contains(where: { fn.contains($0) }) {
                        sc[.data, default: 0] += 2
                    }
                }
                for w in ["data","storage","persistence","network","api","cache","database","keychain","repository","model"] where lower.contains(w) {
                    sc[.data, default: 0] += 1
                }

                // ── ARCHITECTURE / SYSTEM ──────────────────────────────────
                let archHeavy: Set<String> = ["Combine","Darwin","os","Dispatch","Observation","SystemConfiguration","OSLog"]
                for imp in archHeavy where imps.contains(imp) { sc[.arch, default: 0] += 3 }
                let archSfx = ["Coordinator","Router","Container","Middleware","Reducer","Manager",
                               "Provider","Interactor","Presenter","UseCase","State","Action","Environment"]
                for d in decls where archSfx.contains(where: { d.name.hasSuffix($0) }) { sc[.arch, default: 0] += 3 }
                if files.contains(where: { let p = $0.filePath.lowercased()
                    return p.contains("/utilities/") || p.contains("/helpers/") || p.contains("/extensions/") ||
                           p.contains("/core/") || p.contains("/navigation/") || p.contains("/coordinator")
                }) { sc[.arch, default: 0] += 3 }
                if imps.contains("Combine") && !imps.contains("SwiftUI") && !imps.contains("UIKit") {
                    sc[.arch, default: 0] += 2
                }
                for file in files {
                    let fn = file.fileNameWithoutExtension.lowercased()
                    if ["manager","coordinator","router","dependency","container","middleware","reducer","factory","builder"].contains(where: { fn.contains($0) }) {
                        sc[.arch, default: 0] += 2
                    }
                }
                for w in ["core","foundation","architecture","system","utility","helpers","extensions","common","base","shared","infrastructure","platform"] where lower.contains(w) {
                    sc[.arch, default: 0] += 1
                }

                // ── Resolution ────────────────────────────────────────────
                let devS  = sc[.dev,  default: 0]
                let uiS   = sc[.ui,   default: 0]
                let dataS = sc[.data, default: 0]
                let archS = sc[.arch, default: 0]
                if devS  >= 5                  { return .dev  }
                if uiS   >= 4 && uiS > dataS  { return .ui   }
                if dataS >= 4 && dataS > uiS  { return .data }
                return [(PkgCat.ui, uiS), (.data, dataS), (.arch, archS), (.dev, devS)]
                    .max(by: { $0.1 < $1.1 })?.0 ?? .arch
            }

            // ── Group into four columns ──────────────────────────────────
            let hasApp = pkgLines["App", default: 0] > 0
            var groups: [PkgCat: [String]] = [.ui: [], .data: [], .arch: [], .dev: []]
            if hasApp { groups[.ui]!.insert(makeTag("App", isApp: true), at: 0) }
            for name in localNames.sorted() { groups[scorePackage(name)]!.append(makeTag(name)) }

            let totalWithApp = localNames.count + (hasApp ? 1 : 0)
            let colDefs: [(PkgCat, String, String)] = [
                (.dev,  "🔧", "DEV TOOLS"),
                (.arch, "⚙️", "ARCHITECTURE / SYSTEM"),
                (.data, "🗄️", "DATA / NETWORKING"),
                (.ui,   "📱", "UI / MEDIA"),
            ]
            var content = "<div style='color:var(--text3);font-size:12px;margin-bottom:12px'>🏠 \(totalWithApp) packages</div>"
            content += "<div class='pkg-cat-grid'>"
            for (cat, icon, label) in colDefs {
                let tags = groups[cat] ?? []
                let countStr = tags.isEmpty ? "" : " <span class='count'>(\(tags.count))</span>"
                let inner = tags.isEmpty
                    ? "<div style='color:var(--text3);font-size:12px;font-style:italic'>—</div>"
                    : "<div class='pkg-grid'>\(tags.joined(separator: "\n"))</div>"
                content += "<div class='pkg-cat-col'><div class='pkg-cat-head'>\(icon) \(label)\(countStr)</div>\(inner)</div>"
            }
            content += "</div>"

            if !detectedPrivateFrameworks.isEmpty {
                let tags = detectedPrivateFrameworks.sorted().map { "<span class='tag tag-private'>\($0)</span>" }.joined(separator: " ")
                content += "<div style='margin-top:12px'><p class='private-warn'>🔒 Possible Private Frameworks (\(detectedPrivateFrameworks.count)) — may cause App Store rejection:</p><div class='tag-cloud'>\(tags)</div></div>"
            }
            return content
        }()

        // ── Architecture-level inter-package graph ──────────────────────────
        let fileToPackage: [String: String] = Dictionary(
            projectFiles.map { ($0.filePath, $0.packageName.isEmpty ? "App" : $0.packageName) },
            uniquingKeysWith: { $1 }
        )
        struct ArchNode: Encodable { let id: String; let label: String; let val: Int }
        struct ArchLink: Encodable { let source: String; let target: String }
        struct ArchGraphData: Encodable { let nodes: [ArchNode]; let links: [ArchLink] }

        var archFileCount: [String: Int] = [:]
        for file in projectFiles {
            let pkg = file.packageName.isEmpty ? "App" : file.packageName
            archFileCount[pkg, default: 0] += 1
        }
        var archEdgeSeen = Set<String>()
        var archRawConnections = 0
        var archLinks: [ArchLink] = []
        for edge in graph.edges {
            let src = fileToPackage[edge.source] ?? "App"
            let tgt = fileToPackage[edge.target] ?? "App"
            guard src != tgt else { continue }
            archRawConnections += 1
            // Collapse A→B and B→A into a single edge using a sorted canonical key
            let key = [src, tgt].sorted().joined(separator: "↔")
            if archEdgeSeen.insert(key).inserted {
                archLinks.append(ArchLink(source: src, target: tgt))
            }
        }
        let archConnectedIds: Set<String> = Set(archLinks.flatMap { [$0.source, $0.target] })
        let archNodes = archFileCount
            .filter { archConnectedIds.contains($0.key) }
            .map { ArchNode(id: $0.key, label: $0.key, val: $0.value) }
            .sorted { $0.val > $1.val }
        let archGraphJSON = (try? String(data: JSONEncoder().encode(
            ArchGraphData(nodes: archNodes, links: archLinks)
        ), encoding: .utf8)) ?? "{\"nodes\":[],\"links\":[]}"
        let showArchGraph = archNodes.count >= 2 && !archLinks.isEmpty
        let archNodeCount = archNodes.count
        let archLinkDist = archNodeCount > 100 ? 330 : 180
        let archChargeStr = archNodeCount > 100 ? -900 : -450

        // Architecture card
        let architectureCardHTML: String = {
            var h = "<h2>🏛️ Architecture</h2>"
            if !archPatternSubCardHTML.isEmpty {
                h += "<div class='sub-card'>\(archPatternSubCardHTML)</div>"
            }
            if !layersHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>📐 Layers</h3>\(layersHTML)</div>"
            }
            if !componentsHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🧩 Components <span class='count'>(\(detectedComponents.count))</span></h3>\(componentsHTML)</div>"
            }
            if !appleFrameworksHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🍎 Apple Frameworks <span class='count'>(\(appleFrameworksCount))</span></h3>\(appleFrameworksHTML)</div>"
            }
            if !externalLibsHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>📦 External Libraries <span class='count'>(\(externalLibsCount))</span></h3>\(externalLibsHTML)</div>"
            }
            if !monkeyPatchedLibs.isEmpty {
                let vendoredTags = monkeyPatchedLibs.map { lib in
                    "<span class='tag tag-external'>\(esc(lib.name)) <span style='font-size:10px;color:var(--text3)'>\(lib.fileCount) files</span></span>"
                }.joined(separator: " ")
                h += "<div class='sub-card'><h3 class='sub-card-title' style='color:var(--text3)'>🐒 Vendored C/C++ Libraries <span class='count'>(\(monkeyPatchedLibs.count))</span></h3><p style='font-size:12px;color:var(--text3);margin:0 0 10px'>Excluded from analysis.</p><div class='tag-cloud'>\(vendoredTags)</div></div>"
            }
            if showArchGraph {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🗺️ Architecture Graph <span class='count'>(\(archRawConnections) connections)</span></h3><div id='arch-graph' class='arch-graph-container'></div></div>"
            }
            if !localPackagesSubCardHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🏠 Local Packages</h3>\(localPackagesSubCardHTML)</div>"
            }
            return h
        }()

        // Programming Methods card — design patterns, data structures, and
        // algorithms detected in the codebase. Split out of Architecture so those
        // three code-construct sub-cards live under one dedicated heading, placed
        // right after OOP vs POP in the final layout.
        let programmingMethodsCardHTML: String = {
            var h = "<h2>🧠 Programming Methods</h2>"
            if !designPatternsSubCardHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🎨 Design Patterns <span class='count'>(\(totalPatternCount))</span></h3>\(designPatternsSubCardHTML)</div>"
            }
            if !dsSubCardHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🌳 Data Structures <span class='count'>(\(dsMatches.count))</span></h3>\(dsSubCardHTML)</div>"
            }
            if !algoSubCardHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🔀 Algorithms <span class='count'>(\(algoMatches.count))</span></h3>\(algoSubCardHTML)</div>"
            }
            let bigO = buildComplexityHTML(constructs.complexity)
            if !bigO.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🅾️ Big O Complexity Health</h3>\(bigO)</div>"
            }
            if !constantsSubCardHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🔢 Magic Constants <span class='count'>(\(constantMatches.count))</span></h3>\(constantsSubCardHTML)</div>"
            }
            return h
        }()
        let hasProgrammingMethods = !designPatternsSubCardHTML.isEmpty
            || !dsSubCardHTML.isEmpty || !algoSubCardHTML.isEmpty
            || !constantsSubCardHTML.isEmpty || constructs.complexity.hasData

        // ─── 3. Packages ───
        let appTargetName = "App"
        var packageFiles: [String: [ParsedFile]] = [:]
        for file in projectFiles {
            let key = file.packageName.isEmpty ? appTargetName : file.packageName
            packageFiles[key, default: []].append(file)
        }
        let packages = packageFiles.map { PackageSummary(name: $0.key, files: $0.value) }
            .sorted { $0.totalLines > $1.totalLines }

        var packageSections = ""
        var packageGraphScripts = ""

        if !renderModules {
            print("\(ts())  Skipping Packages & Modules (enable with --render-modules)")
        } else {
        print("\(ts())  Building \(packages.count) package sections (parallel)...")

        // Pre-capture self properties used inside the concurrent closure
        let capturedGraph = graph
        let capturedAppTarget = appTargetName
        let capturedKindIcon = kindIcon
        let capturedEsc = esc
        let capturedVsLink = vsLink

        // Parallel HTML generation — each slot is written exactly once, no lock needed
        var pkgSectionArr: [String] = Array(repeating: "", count: packages.count)
        var pkgScriptArr:  [String] = Array(repeating: "", count: packages.count)

        DispatchQueue.concurrentPerform(iterations: packages.count) { pkgIdx in
            let pkg = packages[pkgIdx]

            let allSorted = pkg.files.sorted { $0.lineCount > $1.lineCount }
            let hasDecl: (ParsedFile) -> Bool = {
                !$0.declarations.filter { $0.kind != .extension && !Declaration.invalidNames.contains($0.name) }.isEmpty
            }
            let swiftFiles = allSorted.filter { $0.filePath.hasSuffix(".swift") && $0.lineCount >= 20 && hasDecl($0) }
            let objcFiles  = allSorted.filter { !$0.filePath.hasSuffix(".swift") && $0.lineCount >= 20 && hasDecl($0) }
            let isApp = pkg.name == capturedAppTarget
            let icon = isApp ? "📱" : "📦"
            let bsTag: String = {
                guard !isApp else { return "" }
                let bs = pkg.files.first(where: { $0.buildSystem != .unknown })?.buildSystem
                guard let bs = bs else { return "" }
                return " <span class='bs-badge'>\(bs.rawValue)</span>"
            }()

            let makeFileRows: ([ParsedFile]) -> String = { files in
                files.map { file -> String in
                    let decls = file.declarations.filter { $0.kind != .extension && !Declaration.invalidNames.contains($0.name) }
                    let exts  = file.declarations.filter { $0.kind == .extension && !Declaration.invalidNames.contains($0.name) }
                    var parts: [String] = decls.map { "\(capturedKindIcon($0.kind))&thinsp;\(capturedEsc($0.name))" }
                    parts += exts.map { "🔹&thinsp;\(capturedEsc($0.name))" }
                    let declStr = parts.isEmpty ? "—" : parts.joined(separator: "&ensp;")
                    let desc = file.description.isEmpty ? "" : "<div class='file-desc'>💡 \(capturedEsc(String(file.description.prefix(120))))</div>"
                    let pathComps = file.filePath.components(separatedBy: "/")
                    let folderIdx = max(0, pathComps.count - 2)
                    let folder = pathComps.count >= 2 ? pathComps[folderIdx] + "/" : ""
                    let folderHtml = folder.isEmpty ? "" : "<span style='color:var(--text3);font-weight:400'>\(capturedEsc(folder))</span>"
                    let fileLink = capturedVsLink(file.filePath, "<strong>\(capturedEsc(file.fileName))</strong>", nil)
                    return "<tr><td>\(folderHtml)\(fileLink)\(desc)</td><td class='mono'>\(file.lineCount)</td><td>\(decls.count)</td><td class='decl-tags'>\(declStr)</td></tr>"
                }.joined(separator: "\n")
            }

            let swiftRows = makeFileRows(swiftFiles)
            let objcRows  = makeFileRows(objcFiles)
            let fileRows: String
            if !objcFiles.isEmpty && !swiftFiles.isEmpty {
                fileRows = swiftRows + "\n<tr><td colspan='4' style='background:var(--bg2);padding:4px 10px;font-size:11px;color:var(--text3);font-weight:600;text-transform:uppercase;letter-spacing:0.05em'>Objective-C</td></tr>\n" + objcRows
            } else {
                fileRows = swiftRows + objcRows
            }

            // Declaration graph — use pkgIdx as stable unique ID
            let graphId = "pkg-graph-\(pkgIdx)"
            let declGraphData = buildDeclarationGraph(for: pkg, pageRankScores: capturedGraph.pageRankScores)
            let pkgGraphJSON = (try? String(data: JSONEncoder().encode(declGraphData), encoding: .utf8)) ?? "{\"nodes\":[],\"links\":[]}"
            let showGraph = declGraphData.nodes.count >= 2

            var statsParts: [String] = []
            if pkg.structCount   > 0 { statsParts.append("🟢 \(pkg.structCount) structs") }
            if pkg.classCount    > 0 { statsParts.append("🔵 \(pkg.classCount) classes") }
            if pkg.enumCount     > 0 { statsParts.append("🟡 \(pkg.enumCount) enums") }
            if pkg.protocolCount > 0 { statsParts.append("🟣 \(pkg.protocolCount) protocols") }
            if pkg.actorCount    > 0 { statsParts.append("🔴 \(pkg.actorCount) actors") }
            if pkg.extensionCount > 0 { statsParts.append("🔹 \(pkg.extensionCount) extensions") }

            let pkgAnchor = pkg.name.replacingOccurrences(of: " ", with: "-")

            pkgSectionArr[pkgIdx] = """
            <div class="package-section" id="pkg-\(pkgAnchor)">
                <h3>\(icon) \(capturedEsc(pkg.name))\(bsTag)
                    <span class="pkg-stats">\(allSorted.count) files · \(pkg.totalLines.formatted()) lines · \(pkg.realDeclarations.count) declarations</span>
                </h3>
                <p class="stats-detail">\(statsParts.joined(separator: " · "))</p>
                \(showGraph ? "<div id='\(graphId)' class='pkg-graph-container'></div>" : "")
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>File</th><th>Lines</th><th>Decl</th><th>Declarations</th></tr></thead>
                    <tbody>\(fileRows)</tbody>
                </table></div>
            </div>
            """

            if showGraph {
                pkgScriptArr[pkgIdx] = """
                {
                    const d = \(pkgGraphJSON);
                    const el = document.getElementById('\(graphId)');
                    if (d.nodes.length > 0 && el) {
                        const dark = () => document.documentElement.getAttribute('data-theme') === 'dark';
                        const kc = {'class':'#007aff','struct':'#34c759','enum':'#ff9500','actor':'#ff3b30'};
                        const g = ForceGraph()(el)
                            .graphData(d)
                            .nodeLabel(n => n.label + ' (' + n.sublabel + ')\\n' + n.kind)
                            .nodeVal(n => Math.max(Math.pow(n.score, 0.6) * 9000, 5))
                            .nodeColor(n => kc[n.kind] || '#999')
                            .nodeCanvasObject((node, ctx, gs) => {
                                const r = Math.max(Math.sqrt(Math.max(Math.pow(node.score, 0.6) * 9000, 5)) * 0.9, 3);
                                ctx.beginPath();
                                ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
                                ctx.fillStyle = kc[node.kind] || '#999';
                                ctx.fill();
                                if (gs > 0.5) {
                                    ctx.font = `${Math.max(10/gs, 3)}px -apple-system, sans-serif`;
                                    ctx.textAlign = 'center';
                                    ctx.fillStyle = dark() ? '#e0e0e0' : '#333';
                                    ctx.fillText(node.label, node.x, node.y + r + 10/gs);
                                }
                            })
                            .linkDirectionalArrowLength(8)
                            .linkDirectionalArrowRelPos(1)
                            .linkColor(() => dark() ? 'rgba(255,255,255,0.22)' : 'rgba(0,0,0,0.12)')
                            .width(el.offsetWidth)
                            .height(420);
                        g.d3Force('charge').strength(-380);
                        g.d3Force('link').distance(120);
                        __graphs.push(g);
                    }
                }

                """
            }
        }

        packageSections = pkgSectionArr.joined()
        packageGraphScripts = pkgScriptArr.joined()
        } // end if renderModules

        // Arch-level graph script — always emitted regardless of --render-modules,
        // because the architecture graph is a cross-module view, not a per-module detail.
        if showArchGraph {
            packageGraphScripts += """
            {
                const d = \(archGraphJSON);
                const el = document.getElementById('arch-graph');
                if (d.nodes.length > 0 && el) {
                    const dark = () => document.documentElement.getAttribute('data-theme') === 'dark';
                    const g = ForceGraph()(el)
                        .graphData(d)
                        .nodeLabel(n => n.label + ' (' + n.val + ' files)')
                        .nodeVal(n => Math.max(Math.pow(n.val, 0.7) * 6, 4))
                        .nodeColor(() => dark() ? '#0a84ff' : '#007aff')
                        .nodeCanvasObject((node, ctx, gs) => {
                            const r = Math.max(Math.sqrt(Math.max(Math.pow(node.val, 0.7) * 6, 4)) * 1.4, 4);
                            ctx.beginPath();
                            ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
                            ctx.fillStyle = dark() ? '#0a84ff' : '#007aff';
                            ctx.fill();
                            if (gs > 0.4) {
                                ctx.font = `${Math.max(11/gs, 3)}px -apple-system, sans-serif`;
                                ctx.textAlign = 'center';
                                ctx.fillStyle = dark() ? '#e0e0e0' : '#333';
                                ctx.fillText(node.label, node.x, node.y + r + 12/gs);
                            }
                        })
                        .linkDirectionalArrowLength(0)
                        .linkColor(() => dark() ? 'rgba(255,255,255,0.28)' : 'rgba(0,0,0,0.2)')
                        .width(el.offsetWidth)
                        .height(500);
                    g.d3Force('charge').strength(\(archChargeStr));
                    g.d3Force('link').distance(\(archLinkDist));
                    __graphs.push(g);
                }
            }

            """
        }

        // ─── 4. Hotspots ───
        // In-degree = number of other files that import / reference this file
        var inDegree: [String: Int] = [:]
        for edge in graph.edges { inDegree[edge.target, default: 0] += 1 }

        let hotspotRows = hotspots.map { item -> String in
            let file = fileMap[item.path]
            let fileName = URL(fileURLWithPath: item.path).lastPathComponent
            let pkg = file?.packageName.isEmpty == false ? file!.packageName : "App"
            let pkgAnchor = pkg.replacingOccurrences(of: " ", with: "-")
            let lineCount = file?.lineCount ?? 0
            let declCount = file?.declarations.filter { $0.kind != .extension && !Declaration.invalidNames.contains($0.name) }.count ?? 0
            let pathComps = item.path.components(separatedBy: "/")
            let folderPath = pathComps.count >= 2 ? pathComps.dropLast().suffix(3).joined(separator: "/") + "/" : ""
            let uses = inDegree[item.path] ?? 0
            let fileLabel = "<span style='color:var(--text3)'>\(esc(folderPath))</span><strong>\(esc(fileName))</strong>"
            return "<tr><td>\(vsLink(path: item.path, label: fileLabel))</td><td class='mono'>\(uses)</td><td class='mono'>\(lineCount)</td><td class='mono'>\(declCount)</td><td><a href='#pkg-\(pkgAnchor)' class='tag tag-local pkg-link-inline' style='font-size:11px'>\(esc(pkg))</a></td></tr>"
        }.joined(separator: "\n")

        // ─── 5. Summary ───
        let totalLines = projectFiles.reduce(0) { $0 + $1.lineCount }
        let allDecls = projectFiles.flatMap(\.declarations).filter { !Declaration.invalidNames.contains($0.name) }
        let totalDecls = allDecls.filter { $0.kind != .extension }.count
        let totalExts = allDecls.filter { $0.kind == .extension }.count
        let totalStructs = allDecls.filter { $0.kind == .struct }.count
        let totalClasses = allDecls.filter { $0.kind == .class }.count
        let totalEnums = allDecls.filter { $0.kind == .enum }.count
        let totalProtocols = allDecls.filter { $0.kind == .protocol }.count
        let totalActors = allDecls.filter { $0.kind == .actor }.count

        // Module TODO/FIXME stats
        var moduleTodos: [String: Int] = [:]
        var moduleFixmes: [String: Int] = [:]
        for file in projectFiles {
            let key = file.packageName.isEmpty ? "App" : file.packageName
            moduleTodos[key, default: 0] += file.todoCount
            moduleFixmes[key, default: 0] += file.fixmeCount
        }
        let topTodoModules = moduleTodos
            .filter { $0.value + (moduleFixmes[$0.key] ?? 0) > 0 }
            .sorted { $0.value + (moduleFixmes[$0.key] ?? 0) > $1.value + (moduleFixmes[$1.key] ?? 0) }
            .prefix(50)

        // Package penetration: how many other packages import each package
        var pkgImportedBy: [String: Set<String>] = [:]
        let localPkgSet = Set(projectFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })
        for file in projectFiles {
            let srcPkg = file.packageName.isEmpty ? "App" : file.packageName
            for imp in file.imports {
                if localPkgSet.contains(imp) && imp != srcPkg {
                    pkgImportedBy[imp, default: []].insert(srcPkg)
                }
            }
        }
        let topPenetration = pkgImportedBy.sorted { $0.value.count > $1.value.count }.prefix(20)

        // Longest functions across all files (project only)
        let allFunctions = projectFiles.compactMap(\.longestFunction)
        let topLongestFuncs = allFunctions.sorted { $0.lineCount > $1.lineCount }.prefix(20)

        // Biggest named types (class/struct/enum/protocol/actor) across all files
        let allBigTypes = archFiles.compactMap(\.biggestType)
        let topBigTypes = allBigTypes.sorted { $0.lineCount > $1.lineCount }.prefix(20)

        print("\(ts())  Writing HTML...")

        // ─── Markdown Report (embedded in HTML for MD toggle) ───
        let mdContent: String = {
            var md = ""
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            md += "# 🔬 ArchSwiftScope — \(projectName.isEmpty ? "Project" : projectName)\n\n"
            md += "> Generated \(df.string(from: Date())) · branch `\(branchName)`\n\n"

            // Summary
            md += "## 📊 Summary\n\n"
            md += "| Metric | Value |\n|--------|-------|\n"
            if !metadata.swiftVersion.isEmpty { md += "| Swift | \(metadata.swiftVersion) |\n" }
            if !metadata.appVersion.isEmpty   { md += "| App Version | \(metadata.appVersion) |\n" }
            if !metadata.deploymentTargets.isEmpty { md += "| Deployment | \(metadata.deploymentTargets.joined(separator: ", ")) |\n" }
            md += "| Swift Files | \(projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count) |\n"
            md += "| Total Files | \(projectFiles.count) |\n"
            md += "| Lines of Code | \(totalLines.formatted()) |\n"
            md += "| Declarations | \(totalDecls) |\n"
            md += "| Extensions | \(totalExts) |\n"
            md += "| Packages | \(packages.count) |\n"
            md += "| Structs | \(totalStructs) |\n"
            md += "| Classes | \(totalClasses) |\n"
            md += "| Enums | \(totalEnums) |\n"
            md += "| Protocols | \(totalProtocols) |\n"
            md += "| Actors | \(totalActors) |\n"
            md += "\n"

            // Architecture
            md += "## 🏛️ Architecture\n\n"
            if let top = archDetection.top, top.confidence >= 0.15 {
                md += "**Pattern:** \(top.name) (\(Int(top.confidence * 100))%)\n\n"
                if !top.letters.isEmpty {
                    md += "| Letter | Role | Files |\n|--------|------|-------|\n"
                    for l in top.letters {
                        md += "| **\(l.letter)** | \(l.fullName) | \(l.fileCount) |\n"
                    }
                    md += "\n"
                }
            }
            let layersSorted = layerOrder.compactMap { name -> (String, Int, Int)? in
                guard let e = layerCounts[name] else { return nil }
                return (name, e.files, e.lines)
            } + layerCounts.keys.filter { !layerOrder.contains($0) }.sorted().compactMap { name -> (String, Int, Int)? in
                guard let e = layerCounts[name] else { return nil }
                return (name, e.files, e.lines)
            }
            if !layersSorted.isEmpty {
                md += "### 📐 Layers\n\n| Layer | Files | LOC |\n|-------|-------|-----|\n"
                for (name, files, lines) in layersSorted {
                    md += "| \(layerEmoji[name] ?? "•") \(name) | \(files) | \(lines.formatted()) |\n"
                }
                md += "\n"
            }
            if !detectedComponents.isEmpty {
                md += "### 🧩 Components (\(detectedComponents.count))\n\n"
                md += detectedComponents.map { "\($0.icon) **\($0.name)** — \($0.detail)" }.joined(separator: "\n") + "\n\n"
            }
            if let appleNames = classifiedImports[.apple], !appleNames.isEmpty {
                md += "### 🍎 Apple Frameworks (\(appleNames.count))\n\n"
                md += appleNames.sorted().map { "`\($0)`" }.joined(separator: " · ") + "\n\n"
            }
            if let extNames = classifiedImports[.external], !extNames.isEmpty {
                let cleaned = Set(extNames.map { $0.components(separatedBy: ":").first ?? $0 }).sorted()
                md += "### 📦 External Libraries (\(cleaned.count))\n\n"
                md += cleaned.map { "`\($0)`" }.joined(separator: " · ") + "\n\n"
            }
            if !monkeyPatchedLibs.isEmpty {
                md += "### 🐒 Vendored C/C++ (\(monkeyPatchedLibs.count))\n\n"
                md += monkeyPatchedLibs.map { "`\($0.name)` (\($0.fileCount) files)" }.joined(separator: " · ") + "\n\n"
            }
            let allLocalPkgNames = Set(projectFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })
            if !allLocalPkgNames.isEmpty {
                md += "### 🏠 Local Packages (\(allLocalPkgNames.count))\n\n"
                md += allLocalPkgNames.sorted().map { "`\($0)`" }.joined(separator: " · ") + "\n\n"
            }

            // Traffic
            if trafficResult.hasData {
                md += "## 🛜 Traffic\n\n"
                if !trafficResult.outbound.isEmpty {
                    md += "### 📤 Outbound (\(trafficResult.outbound.count))\n\n"
                    md += "| Protocol | URI | Format | File |\n|----------|-----|--------|------|\n"
                    for e in trafficResult.outbound.prefix(50) {
                        let fname = URL(fileURLWithPath: e.filePath).lastPathComponent
                        let fmt = e.dataFmt.isEmpty ? "—" : e.dataFmt
                        let uri = e.uri.count > 60 ? String(e.uri.prefix(57)) + "…" : e.uri
                        md += "| \(e.proto) | \(uri) | \(fmt) | \(fname):\(e.line) |\n"
                    }
                    md += "\n"
                }
                if !trafficResult.inbound.isEmpty {
                    md += "### 📥 Inbound (\(trafficResult.inbound.count))\n\n"
                    md += "| Protocol | Route | Format | File |\n|----------|-------|--------|------|\n"
                    for e in trafficResult.inbound.prefix(30) {
                        let fname = URL(fileURLWithPath: e.filePath).lastPathComponent
                        let fmt = e.dataFmt.isEmpty ? "—" : e.dataFmt
                        md += "| \(e.proto) | \(e.uri) | \(fmt) | \(fname):\(e.line) |\n"
                    }
                    md += "\n"
                }
            }

            // OOP vs POP
            md += "## 🧬 OOP vs POP\n\n"
            let ps = resolvedOOPStats
            let popLabel = ps.popScore >= 60 ? "POP" : ps.popScore < 40 ? "OOP" : "Mixed"
            md += "**POP Score:** \(ps.popScore)% — **\(popLabel)**\n\n"
            md += "| Category | Weight | Score |\n|----------|--------|-------|\n"
            md += "| Protocol Design | 55% | \(ps.protoDesignScore)% |\n"
            md += "| Value Semantics | 30% | \(ps.valueSemanticsScore)% |\n"
            md += "| Anti-inheritance | 15% | \(ps.antiInheritScore)% |\n"
            md += "\n"
            md += "| Metric | Count |\n|--------|-------|\n"
            md += "| Classes | \(ps.totalClasses) |\n"
            md += "| Structs | \(ps.totalStructs) |\n"
            md += "| Protocols | \(ps.totalProtocols) |\n"
            md += "| Final Classes | \(ps.finalClasses) |\n"
            md += "| Singletons | \(ps.singletonCount) |\n"
            md += "| Generic Functions | \(ps.genericFuncCount) |\n"
            md += "| Protocol Extensions w/ Code | \(ps.protocolExtWithCode) |\n"
            md += "| Multi-conformer Protocols | \(ps.multiConformerProtocols) |\n"
            md += "\n"

            // Security
            md += "## 🚨 Security — Index \(resolvedSecurityScore.total) / 1000\n\n"
            let band = resolvedSecurityScore.total < 200 ? "Hardened" : resolvedSecurityScore.total < 500 ? "Minor exposure" : resolvedSecurityScore.total < 800 ? "Elevated risk" : "Critical exposure"
            md += "**Risk Band:** \(band)\n\n"
            let failedChecks = resolvedAPResults.filter { !$0.passed }
            md += "**Checks Failed:** \(failedChecks.count) / \(resolvedAPResults.count)\n\n"
            if !failedChecks.isEmpty {
                md += "| Check | Violations |\n|-------|------------|\n"
                for r in failedChecks.prefix(20) {
                    md += "| \(r.check.name) | \(r.totalCount) |\n"
                }
                md += "\n"
            }

            // Git
            md += "## 🐙 Git Analysis\n\n"
            if !topTeam.isEmpty {
                md += "### 👥 Team (\(topTeam.count))\n\n"
                md += "| Developer | Files | Commits | LOC Added |\n|-----------|-------|---------|----------|\n"
                for entry in topTeam {
                    let name = entry.value.displayName.isEmpty ? entry.key : entry.value.displayName
                    let loc = entry.value.totalLOCAdded > 0 ? entry.value.totalLOCAdded.formatted() : "—"
                    md += "| \(name) | \(entry.value.filesModified) | \(entry.value.totalCommits) | \(loc) |\n"
                }
                md += "\n"
            }
            if branchStats.total > 0 {
                md += "### 🌿 Branches\n\n"
                md += "| Metric | Value |\n|--------|-------|\n"
                md += "| Total | \(branchStats.total) |\n"
                if branchStats.local  > 0 { md += "| Local | \(branchStats.local) |\n" }
                if branchStats.remote > 0 { md += "| Remote | \(branchStats.remote) |\n" }
                if branchStats.stale  > 0 { md += "| Stale (>90d) | \(branchStats.stale) |\n" }
                if branchStats.merged > 0 { md += "| Merged | \(branchStats.merged) |\n" }
                let bm = branchStats.branchingModel
                if bm.model != .unknown { md += "| Branching Model | \(bm.model.rawValue) (\(Int(bm.confidence * 100))%) |\n" }
                md += "\n"
            }
            if !churnFiles.isEmpty {
                md += "### 🔥 Code Churn (top \(min(churnFiles.count, 15)))\n\n"
                md += "| File | Changes |\n|------|--------|\n"
                for stat in churnFiles.prefix(15) {
                    md += "| \(URL(fileURLWithPath: stat.path).lastPathComponent) | \(stat.changeCount) |\n"
                }
                md += "\n"
            }
            if semanticStats.totalCommits > 0 {
                md += "### 📐 Semantic Standards\n\n"
                md += "| Metric | Value |\n|--------|-------|\n"
                md += "| Total Commits | \(semanticStats.totalCommits) |\n"
                let convRate = Int(Double(semanticStats.conventionalCommits) / Double(semanticStats.totalCommits) * 100)
                md += "| Conventional Commits | \(semanticStats.conventionalCommits) (\(convRate)%) |\n"
                md += "| Semver Tags | \(semanticStats.semverTags) / \(semanticStats.totalTags) |\n"
                if !semanticStats.latestSemver.isEmpty { md += "| Latest Tag | \(semanticStats.latestSemver) |\n" }
                if !semanticStats.topPrefixes.isEmpty {
                    md += "\n**Commit Prefixes:**\n\n| Prefix | Count |\n|--------|-------|\n"
                    for p in semanticStats.topPrefixes.prefix(10) { md += "| `\(p.prefix)` | \(p.count) |\n" }
                }
                md += "\n"
            }

            // Hot Zones
            if !hotspots.isEmpty {
                md += "## 🔥 Hot Zones\n\n"
                md += "| File | Used By | Lines | Package |\n|------|---------|-------|--------|\n"
                for item in hotspots {
                    let file = fileMap[item.path]
                    let fname = URL(fileURLWithPath: item.path).lastPathComponent
                    let pkg = file?.packageName.isEmpty == false ? file!.packageName : "App"
                    md += "| \(fname) | \(inDegree[item.path] ?? 0) | \(file?.lineCount ?? 0) | \(pkg) |\n"
                }
                md += "\n"
            }

            // Longest Functions
            if !topLongestFuncs.isEmpty {
                md += "## 📏 Longest Functions\n\n"
                md += "| Function | Lines | File |\n|----------|-------|------|\n"
                for fn in topLongestFuncs {
                    md += "| `\(fn.name)` | \(fn.lineCount) | \(URL(fileURLWithPath: fn.filePath).lastPathComponent):\(fn.startLine) |\n"
                }
                md += "\n"
            }

            // Module Insights
            if !topPenetration.isEmpty {
                md += "## 📋 Module Insights\n\n"
                md += "### 📊 Package Penetration\n\n"
                md += "| Package | Used By |\n|---------|--------|\n"
                for entry in topPenetration { md += "| \(entry.key) | \(entry.value.count) |\n" }
                md += "\n"
            }
            if !topTodoModules.isEmpty {
                if topPenetration.isEmpty { md += "## 📋 Module Insights\n\n" }
                md += "### 📝 TODO / FIXME\n\n"
                md += "| Module | TODOs | FIXMEs | Total |\n|--------|-------|--------|-------|\n"
                for (key, todos) in topTodoModules {
                    let fixmes = moduleFixmes[key] ?? 0
                    md += "| \(key) | \(todos) | \(fixmes) | \(todos + fixmes) |\n"
                }
                md += "\n"
            }

            md += "---\n\n*Generated by [ArchSwiftScope](https://github.com/Exey/ArchSwiftScope)*\n"
            return md
        }()

        // ─── HTML ───
        let html = """
        <!DOCTYPE html>
        <html lang="en" data-theme="light">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📊</text></svg>">
            <title>🔬 ArchSwiftScope — \(esc(projectName))</title>
            <style>
                :root,[data-theme="light"] { --bg:#f5f5f7;--bg2:#fafafa;--card:#fff;--border:#e5e5ea;--text:#1d1d1f;--text2:#424245;--text3:#86868b;--accent:#0071e3;--red:#ff3b30;--green:#34c759;--orange:#ff9500;--teal:#00a3a3;--pink:#ff2d92;--magenta:#c026d3;--yellow:#b8860b;--graph-bg:#fafafa; }
                [data-theme="dark"] { --bg:#1c1c1e;--bg2:#2c2c2e;--card:#2c2c2e;--border:#3a3a3c;--text:#f5f5f7;--text2:#ebebf5;--text3:#8e8e93;--accent:#0a84ff;--red:#ff453a;--green:#30d158;--orange:#ff9f0a;--teal:#5ee6e6;--pink:#ff6bb3;--magenta:#e879f9;--yellow:#f5d442;--graph-bg:#1e1e20; }
                [data-theme="dark"] body { color-scheme: dark; }
                [data-theme="dark"] .ap-fail-badge { background:#3a1c1c; }
                [data-theme="dark"] .card { box-shadow:0 1px 12px rgba(0,0,0,0.35); }
                [data-theme="dark"] .tag-apple   { background:#162018; color:#b8e47a; }
                [data-theme="dark"] .tag-external { background:#241a06; color:#ffb870; }
                [data-theme="dark"] .tag-local   { background:#191e3a; color:#9dbbff; }
                [data-theme="dark"] .tag-pop     { background:#162018; color:#b8e47a; }
                [data-theme="dark"] .tag-oop     { background:#241a06; color:#ffb870; }
                [data-theme="dark"] .tag-mixed   { background:#1c1c28; color:#b4b2d0; }
                [data-theme="dark"] .tag-private { background:#201018; color:#ff90a4; }
                [data-theme="dark"] .branch-badge { background:#191e3a; color:#9dbbff; }
                [data-theme="dark"] .pkg-link:hover { background:#1a2c3e; }
                [data-theme="dark"] .bs-badge-right { background:rgba(255,255,255,0.07); }
                [data-theme="dark"] .bs-badge { background:rgba(255,255,255,0.08); }
                .top-actions { display:flex;align-items:center;justify-content:flex-end;gap:8px;user-select:none;margin-bottom:8px; }
                .pill-seg { display:flex;border:1px solid var(--border);border-radius:999px;overflow:hidden;background:var(--bg); }
                .seg-btn { border:none;background:transparent;color:var(--text3);padding:6px 13px;cursor:pointer;font-size:13px;line-height:1;transition:background .15s,color .15s;white-space:nowrap; }
                .seg-btn:hover { color:var(--text); }
                .seg-btn.active { background:var(--bg2);color:var(--text);font-weight:600; }
                .md-toolbar { display:flex;justify-content:flex-end;margin-bottom:8px; }
                .md-copy-btn { padding:5px 14px;background:var(--bg2);border:1px solid var(--border);border-radius:6px;color:var(--text2);font-size:12px;font-weight:600;cursor:pointer;transition:background .15s; }
                .md-copy-btn:hover { background:var(--border); }
                .md-pre { font-family:'SF Mono',Menlo,monospace;font-size:12px;line-height:1.7;white-space:pre-wrap;word-break:break-word;color:var(--text);background:var(--bg2);padding:20px;border-radius:10px;margin:0;overflow-x:auto;max-height:85vh;overflow-y:auto; }
                * { box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif; margin: 0; padding: 20px; background: var(--bg); color: var(--text); line-height: 1.5; }
                .container { max-width: 1280px; margin: 0 auto; }
                .card { background: var(--card); padding: 28px; border-radius: 16px; box-shadow: 0 1px 12px rgba(0,0,0,0.06); margin-bottom: 20px; }
                h1 { font-size: 28px; font-weight: 700; margin: 0 0 4px 0; }
                h2 { color: var(--text2); font-size: 20px; border-bottom: 2px solid var(--border); padding-bottom: 10px; margin: 0 0 16px 0; }
                h3 { color: var(--text2); font-size: 16px; margin: 20px 0 8px 0; }
                .subtitle { color: var(--text3); font-size: 14px; margin-bottom: 20px; }
                .branch-badge { display: inline-block; background: #e3f2fd; color: #1565c0; padding: 2px 10px; border-radius: 8px; font-size: 13px; font-weight: 500; font-family: 'SF Mono', Menlo, monospace; }
                .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 10px; margin-bottom: 24px; }
                .summary-card { background: var(--bg); border-radius: 12px; padding: 14px 8px; text-align: center; }
                .summary-card .num { font-size: 26px; font-weight: 700; color: var(--accent); }
                .summary-card .label { font-size: 11px; color: var(--text3); text-transform: uppercase; letter-spacing: 0.04em; margin-top: 2px; }
                .team-table, .file-table { width: 100%; border-collapse: collapse; font-size: 14px; }
                .team-table th, .file-table th { color: var(--text3); font-weight: 500; text-transform: uppercase; font-size: 11px; letter-spacing: 0.05em; text-align: left; padding: 8px 10px; border-bottom: 2px solid var(--border); }
                .team-table td, .file-table td { padding: 8px 10px; border-bottom: 1px solid var(--border); vertical-align: top; }
                .mono { font-family: 'SF Mono', Menlo, monospace; font-size: 13px; }
                .tag { display: inline-block; padding: 2px 8px; border-radius: 6px; font-size: 12px; font-weight: 500; margin: 2px; }
                .tag-apple { background: #e8f5e9; color: #2e7d32; }
                .tag-external { background: #fff3e0; color: #e65100; }
                .tag-local { background: #e3f2fd; color: #1565c0; }
                .tag-cloud { line-height: 2.2; }
                .pkg-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 4px 8px; }
                .pkg-cat-grid { display: flex; flex-direction: column; gap: 20px; }
                .pkg-cat-col { }
                .pkg-cat-head { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text3); margin-bottom: 8px; }
                .pkg-link { display: flex; align-items: center; justify-content: space-between; text-decoration: none; cursor: pointer; transition: background 0.15s; }
                .pkg-link:hover { background: #bbdefb; }
                .pkg-major { border: 2px solid var(--accent); font-weight: 600; }
                .pkg-link-inline { text-decoration: none; cursor: pointer; }
                .vs-link { text-decoration: none; color: inherit; }
                .vs-link:hover { text-decoration: underline; color: var(--accent); }
                .pkg-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
                .bs-badge-right { background: rgba(0,0,0,0.07); color: var(--text3); font-size: 9px; padding: 1px 5px; border-radius: 4px; margin-left: auto; padding-left: 6px; flex-shrink: 0; font-weight: 400; letter-spacing: 0.02em; }
                .bs-badge { background: rgba(0,0,0,0.08); color: var(--text3); font-size: 10px; padding: 1px 5px; border-radius: 4px; margin-left: 2px; font-weight: 400; }
                .tag-private { background: #fce4ec; color: #c62828; }
                .tag-pop { background: #e8f5e9; color: #2e7d32; }
                .tag-oop { background: #fff3e0; color: #e65100; }
                .tag-mixed { background: #f5f5f5; color: #757575; }
                .private-warn { color: #c62828; font-size: 12px; margin: 4px 0 8px 0; }
                .count { font-weight: 400; color: var(--text3); }
                .import-group { margin-bottom: 16px; }
                .import-group h3 { margin-bottom: 8px; }
                .traffic-multi { display:flex;flex-direction:column;gap:3px; }
                .traffic-file-item { white-space:nowrap; }
                .traffic-count { display:inline-block;background:var(--bg);border:1px solid var(--border);border-radius:10px;padding:1px 7px;font-size:11px;color:var(--text3);margin-left:5px;vertical-align:middle; }
                .hotspot-list { list-style: none; padding: 0; margin: 0; }
                .hotspot-item { padding: 10px 0; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: flex-start; }
                .hotspot-score { font-weight: 600; color: var(--red); font-family: 'SF Mono', monospace; font-size: 13px; white-space: nowrap; }
                .description { color: var(--text3); font-style: italic; display: block; margin-top: 2px; font-size: 13px; }
                .package-section { margin-bottom: 32px; padding-bottom: 24px; border-bottom: 1px solid var(--border); }
                .package-section:last-child { border-bottom: none; }
                .pkg-stats { font-weight: 400; color: var(--text3); font-size: 13px; margin-left: 8px; }
                .stats-detail { color: var(--text3); font-size: 13px; margin: 4px 0 12px 0; }
                .file-desc { color: var(--text3); font-size: 12px; font-style: italic; margin-top: 2px; }
                .decl-tags { font-size: 12px; line-height: 1.8; }
                .pkg-graph-container { width: 100%; height: 420px; border: 1px solid var(--border); border-radius: 10px; margin-bottom: 16px; overflow: hidden; background: var(--graph-bg); }
                .arch-graph-container { width: 100%; height: 500px; border-radius: 8px; overflow: hidden; background: var(--graph-bg); }
                .table-wrap { width: 100%; overflow-x: auto; -webkit-overflow-scrolling: touch; }
                .sub-card { border: 1px solid var(--border); border-radius: 10px; padding: 16px; margin-bottom: 16px; }
                .sub-card:last-child { margin-bottom: 0; }
                .sub-card-title { font-size: 15px; font-weight: 600; margin: 0 0 12px 0; color: var(--text); }
                .ap-summary { margin-bottom: 16px; display: flex; gap: 12px; align-items: center; }
                .ap-fail-badge { background: #fff0f0; color: var(--red); padding: 4px 12px; border-radius: 8px; font-weight: 600; font-size: 14px; }
                .ap-pass-badge { background: #f0fff4; color: #34c759; padding: 4px 12px; border-radius: 8px; font-weight: 600; font-size: 14px; }
                .ap-passed-list { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px; margin-bottom: 24px; }
                .ap-passed-item { display: flex; align-items: center; gap: 4px; font-size: 13px; color: var(--text3); }
                .ap-priority { padding: 1px 6px; border-radius: 4px; font-size: 10px; font-weight: 700; text-transform: uppercase; }
                .ap-pri-high { background: #ffeaea; color: #c62828; }
                .ap-pri-med { background: #fff3e0; color: #e65100; }
                .ap-pri-low { background: #fffde7; color: #f57f17; }
                .ap-lang-badge { padding: 1px 6px; border-radius: 4px; font-size: 10px; font-weight: 700; text-transform: uppercase; background: #e3f2fd; color: #1565c0; }
                .ap-check { margin-bottom: 16px; border: 1px solid #ffeaea; border-radius: 10px; overflow: hidden; }
                .ap-check-header { background: #fff8f8; padding: 10px 14px; display: flex; align-items: center; gap: 8px; }
                .ap-check-title { font-weight: 600; font-size: 14px; flex: 1; }
                .ap-check-count { color: var(--red); font-size: 12px; font-weight: 500; }
                .ap-violations { padding: 10px 14px; }
                .ap-check-desc { font-size: 12px; color: var(--text3); margin-bottom: 8px; line-height: 1.6; }
                .ap-violation { display: flex; gap: 6px; margin-bottom: 4px; font-size: 12px; overflow: hidden; align-items: center; }
                .ap-file { font-family: 'SF Mono', Menlo, monospace; color: var(--accent); flex-shrink: 0; }
                .ap-snippet { font-family: 'SF Mono', Menlo, monospace; color: var(--text2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: 1; }
                .ap-author-badge { margin-left: auto; flex-shrink: 0; background: #e3f2fd; color: #1565c0; font-size: 10px; padding: 1px 5px; border-radius: 4px; white-space: nowrap; }
                /* ── Security Risks ── */
                .sec-toprow { display: flex; gap: 24px; align-items: stretch; margin: 8px 0 22px; flex-wrap: wrap; }
                .sec-gauge-wrap { display: flex; flex-direction: column; align-items: center; padding: 14px 18px; background: var(--bg); border-radius: 12px; flex: 0 0 240px; }
                .sec-gauge-svg { width: 200px; height: 124px; }
                .sec-gauge-label { font-family: 'SF Mono', Menlo, monospace; font-size: 11px; color: var(--text3); letter-spacing: 0.08em; margin-top: 6px; }
                .sec-gauge-val { font-size: 30px; font-weight: 700; margin-top: 2px; line-height: 1.1; }
                .sec-gauge-desc { font-family: 'SF Mono', Menlo, monospace; font-size: 11px; color: var(--text3); margin-top: 12px; line-height: 1.9; text-align: left; align-self: stretch; }
                .sec-gauge-desc .rng { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 5px; vertical-align: middle; }
                .sec-gauge-desc .cur { font-weight: 700; color: var(--text); }
                .sec-weight-bars { flex: 1 1 360px; min-width: 320px; }
                .sec-weight-title { font-size: 11px; font-weight: 600; color: var(--text3); letter-spacing: 0.06em; text-transform: uppercase; margin-bottom: 10px; }
                .sec-wb-row { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
                .sec-wb-name { font-size: 12px; color: var(--text2); min-width: 230px; display: flex; align-items: center; gap: 5px; }
                .sec-wb-num { display: inline-flex; align-items: center; justify-content: center; width: 16px; height: 16px; border-radius: 4px; background: var(--border); color: var(--text3); font-size: 9px; font-weight: 700; flex-shrink: 0; }
                .sec-wb-track { flex: 1; height: 7px; background: var(--border); border-radius: 4px; overflow: hidden; min-width: 60px; }
                .sec-wb-fill { height: 100%; border-radius: 4px; transition: width 0.3s; }
                .sec-wb-na-fill { background: repeating-linear-gradient(45deg, var(--border), var(--border) 4px, transparent 4px, transparent 8px); }
                .sec-wb-pts { font-family: 'SF Mono', Menlo, monospace; font-size: 11px; font-weight: 600; min-width: 56px; text-align: right; }
                .sec-wb-na { font-size: 10px; color: var(--text3); font-style: italic; min-width: 56px; text-align: right; }
                .sec-wb-weight { font-family: 'SF Mono', Menlo, monospace; font-size: 10px; color: var(--text3); min-width: 42px; text-align: right; }
                .sec-detail { margin-top: 8px; }
                .sec-sec { border: 1px solid var(--border); border-radius: 10px; padding: 0; margin-bottom: 12px; overflow: hidden; }
                .sec-sec-head { display: flex; align-items: center; gap: 8px; padding: 10px 14px; background: var(--bg); border-bottom: 1px solid var(--border); flex-wrap: wrap; }
                .sec-sec-num { display: inline-flex; align-items: center; justify-content: center; width: 20px; height: 20px; border-radius: 5px; background: var(--text2); color: #fff; font-size: 11px; font-weight: 700; flex-shrink: 0; }
                .sec-sec-icon { font-size: 16px; }
                .sec-sec-title { font-weight: 600; font-size: 14px; }
                .sec-sec-weight { font-family: 'SF Mono', Menlo, monospace; font-size: 11px; color: var(--text3); margin-left: 6px; }
                .sec-sec-risk { font-family: 'SF Mono', Menlo, monospace; font-size: 12px; font-weight: 600; margin-left: auto; }
                .sec-sec-na { color: var(--text3); font-weight: 400; font-style: italic; }
                .sec-sec-blurb { font-size: 12px; color: var(--text3); padding: 8px 14px 4px; line-height: 1.6; }
                .sec-sec-empty { font-size: 12px; color: var(--text3); padding: 4px 14px 14px; font-style: italic; }
                .sec-check { padding: 6px 14px 4px; }
                .sec-check-row { display: flex; align-items: center; gap: 8px; }
                .sec-check-status { font-weight: 700; width: 14px; text-align: center; flex-shrink: 0; }
                .sec-check-name { font-size: 13px; font-weight: 500; min-width: 230px; flex-shrink: 0; }
                .sec-check-track { flex: 1; height: 6px; background: var(--border); border-radius: 3px; overflow: hidden; min-width: 50px; }
                .sec-check-fill { height: 100%; border-radius: 3px; transition: width 0.3s; }
                .sec-check-count { font-family: 'SF Mono', Menlo, monospace; font-size: 12px; font-weight: 600; min-width: 90px; text-align: right; }
                .sec-check-desc { font-size: 12px; color: var(--text3); margin: 6px 0 8px 22px; line-height: 1.6; }
                .sec-violations { margin: 0 0 8px 22px; }
                .arch-layers { display: flex; flex-direction: column; gap: 8px; }
                .arch-layer {}
                .layer-bar-row { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
                .layer-icon { font-size: 15px; width: 20px; text-align: center; flex-shrink: 0; }
                .layer-name { font-weight: 600; font-size: 13px; flex: 1; color: var(--text); }
                .layer-count { font-size: 11px; color: var(--text3); white-space: nowrap; font-family: 'SF Mono', Menlo, monospace; }
                .layer-bar-track { height: 6px; background: var(--border); border-radius: 3px; overflow: hidden; }
                .layer-bar-fill { height: 100%; background: var(--accent); border-radius: 3px; transition: width 0.3s; }
                .component-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
                .component-item { display: flex; align-items: center; gap: 10px; background: var(--bg); border-radius: 10px; padding: 10px 12px; }
                .component-icon { font-size: 22px; flex-shrink: 0; }
                .component-name { font-weight: 600; font-size: 13px; }
                .component-detail { font-size: 11px; color: var(--text3); margin-top: 1px; }
                .arch-pattern-wrap { }
                .arch-conf-list { display: flex; flex-direction: column; gap: 5px; margin-bottom: 16px; }
                .arch-conf-row { display: flex; align-items: center; gap: 10px; }
                .arch-conf-name { font-size: 13px; min-width: 72px; font-family: 'SF Mono', Menlo, monospace; }
                .arch-conf-track { flex: 1; height: 5px; background: var(--border); border-radius: 3px; overflow: hidden; max-width: 240px; }
                .arch-conf-fill { height: 100%; border-radius: 3px; transition: width 0.3s; }
                .arch-conf-pct { font-size: 11px; font-family: 'SF Mono', Menlo, monospace; min-width: 32px; }
                .arch-conf-attrs { font-size: 11px; color: var(--text3); white-space: nowrap; }
                .arch-letter-row { display: flex; gap: 10px; flex-wrap: wrap; }
                .arch-letter-card { flex: 1; min-width: 72px; max-width: 130px; background: var(--bg); border-radius: 12px; padding: 14px 10px 12px; text-align: center; }
                .arch-letter-big { font-size: 34px; font-weight: 800; color: var(--accent); letter-spacing: -1px; line-height: 1; font-family: 'SF Pro Display', -apple-system, sans-serif; }
                .arch-letter-name { font-size: 11px; font-weight: 600; color: var(--text2); margin-top: 6px; text-transform: uppercase; letter-spacing: 0.04em; }
                .arch-letter-count { font-size: 22px; font-weight: 700; color: var(--text); margin-top: 8px; line-height: 1; }
                .arch-letter-detail { font-size: 10px; color: var(--text3); margin-top: 4px; line-height: 1.4; }
                .arch-letter-link { font-size: 10px; margin-top: 4px; overflow: hidden; }
                .arch-letter-link a { display: block; margin-top: 4px; color: var(--accent); text-decoration: none; font-family: 'SF Mono', Menlo, monospace; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; line-height: 1.3; }
                .fw-cat-col-head { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text3); margin-bottom: 4px; }
                .arch-letter-card.health-weak { border: 1px solid #ff9500; }
                .arch-letter-card.health-missing { opacity: 0.45; border: 1px dashed var(--border); }
                .arch-letter-card.health-weak .arch-letter-big { color: #ff9500; }
                .arch-letter-card.health-missing .arch-letter-big { color: var(--text3); }
                .arch-letter-card.orthogonal { opacity: 0.5; }
                .arch-letter-sep { width: 1px; background: var(--border); margin: 0 4px; flex-shrink: 0; align-self: stretch; min-height: 60px; }
                .ds-sections { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; align-items: start; }
                .ds-group-full { grid-column: 1 / -1; }
                .ds-group-head { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text3); margin-bottom: 6px; }
                .ds-items { display: flex; flex-direction: column; gap: 8px; }
                .ds-items-2col { display: grid; grid-template-columns: 1fr 1fr; align-items: start; }
                .ds-item { background: var(--bg); border-radius: 8px; padding: 9px 12px; width: 100%; box-sizing: border-box; }
                .ds-item-top { display: flex; justify-content: space-between; align-items: baseline; gap: 6px; margin-bottom: 4px; }
                .ds-item-name { font-size: 13px; font-weight: 600; color: var(--text); }
                .ds-item-detail { font-size: 11px; color: var(--text3); margin: -2px 0 6px; line-height: 1.4; }
                a.ds-wiki-link { text-decoration: none; border-bottom: 1px dotted var(--text3); }
                a.ds-wiki-link:hover { border-bottom-style: solid; border-bottom-color: var(--accent); }
                .ds-item-count { font-size: 16px; font-weight: 700; color: var(--accent); font-family: 'SF Mono', Menlo, monospace; flex-shrink: 0; }
                .ds-item-occ { font-size: 11px; color: var(--text3); font-family: 'SF Mono', Menlo, monospace; column-count: 3; column-gap: 16px; }
                .ds-occ { display: block; line-height: 1.9; padding: 1px 0; word-break: break-word; break-inside: avoid; }
                .ds-more { color: var(--text3); opacity: 0.7; font-style: italic; }
                .ds-item-occ a.vs-link { color: var(--accent); text-decoration: none; }
                .ds-item-occ a.vs-link:hover { text-decoration: underline; }
                .ds-module { font-size: 10px; color: var(--text3); background: var(--bg2); border: 1px solid var(--border); border-radius: 3px; padding: 1px 4px; margin-right: 4px; vertical-align: middle; opacity: 0.85; }
                .bigo-usage { font-size: 13px; color: var(--text2); margin: 0 0 14px; }
                .bigo-usage b { color: var(--text); font-family: 'SF Mono', Menlo, monospace; }
                .bigo-bars { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 18px; }
                @media (max-width: 640px) { .bigo-bars { grid-template-columns: 1fr; } }
                .bigo-bar-head { display: flex; justify-content: space-between; align-items: baseline; font-size: 13px; font-weight: 600; color: var(--text); margin-bottom: 6px; }
                .bigo-score { font-family: 'SF Mono', Menlo, monospace; font-size: 20px; font-weight: 700; }
                .bigo-score-max { font-size: 12px; font-weight: 400; color: var(--text3); }
                .bigo-track { height: 8px; border-radius: 5px; background: var(--bg2); overflow: hidden; }
                .bigo-fill { height: 100%; border-radius: 5px; transition: width .3s; }
                .bigo-bar-sub { font-size: 11px; color: var(--text3); margin-top: 5px; }
                .bigo-viol-group { margin-top: 14px; }
                .bigo-viol-head { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text3); margin-bottom: 8px; }
                .bigo-viol { display: flex; align-items: baseline; gap: 10px; padding: 6px 0; border-top: 1px solid var(--border); font-size: 12px; flex-wrap: wrap; }
                .bigo-order { font-family: 'SF Mono', Menlo, monospace; font-weight: 700; font-size: 13px; color: var(--red); flex-shrink: 0; min-width: 46px; }
                .bigo-exp { font-size: 15px; font-weight: 800; }
                .bigo-exp-2 { color: var(--teal); }
                .bigo-exp-3 { color: var(--pink); }
                .bigo-exp-4 { color: var(--magenta); }
                .bigo-exp-n { color: var(--yellow); }
                .bigo-sym { font-family: 'SF Mono', Menlo, monospace; color: var(--text); font-weight: 600; }
                .bigo-reason { color: var(--text3); flex: 1 1 auto; }
                .bigo-link { font-family: 'SF Mono', Menlo, monospace; font-size: 11px; white-space: nowrap; }
                .bigo-more { color: var(--text3); font-style: italic; }
                .bigo-clean { font-size: 13px; color: var(--green); margin: 6px 0 0; }
                .dp-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }
                @media (max-width: 1100px) { .dp-grid { grid-template-columns: 1fr 1fr; } }
                .dp-col-head { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text3); margin-bottom: 8px; }
                .dp-item { background: var(--bg); border-radius: 8px; padding: 10px 12px; margin-bottom: 6px; }
                .dp-item-top { display: flex; justify-content: space-between; align-items: baseline; gap: 6px; }
                .dp-item-letter { font-size: 22px; font-weight: 800; color: var(--accent); margin-right: 5px; font-family: 'SF Pro Display', -apple-system, sans-serif; line-height: 1; flex-shrink: 0; }
                .dp-item-name { font-size: 13px; font-weight: 600; color: var(--text); }
                .dp-item-count { font-size: 18px; font-weight: 700; color: var(--accent); font-family: 'SF Mono', Menlo, monospace; flex-shrink: 0; }
                .dp-item-detail { font-size: 11px; color: var(--text3); margin-top: 3px; }
                .dp-item-idiom { opacity: 0.7; }
                .dp-idiom-badge { font-size: 9px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text3); background: var(--bg2); border: 1px solid var(--border); border-radius: 3px; padding: 1px 5px; white-space: nowrap; }
                .dp-item-link { font-size: 11px; margin-top: 5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-family: 'SF Mono', Menlo, monospace; }
                @media (max-width: 768px) { .dp-grid, .ds-sections, .ds-items-2col { grid-template-columns: 1fr; } .ds-item-occ { column-count: 1; } }
                .bm-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 10px; margin-bottom: 16px; }
                .bm-card { background: var(--bg); border-radius: 10px; padding: 12px; text-align: center; }
                .bm-value { font-size: 22px; font-weight: 700; color: var(--accent); }
                .bm-label { font-size: 11px; color: var(--text3); text-transform: uppercase; letter-spacing: 0.04em; margin-top: 2px; }
                .sem-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; font-size: 13px; }
                .sem-label { width: 160px; flex-shrink: 0; color: var(--text2); font-weight: 500; }
                .sem-bar-wrap { flex: 1; height: 6px; background: var(--border); border-radius: 3px; overflow: hidden; }
                .sem-bar { display: block; height: 100%; background: var(--accent); border-radius: 3px; }
                .sem-stat { color: var(--text3); font-size: 12px; white-space: nowrap; min-width: 160px; }
                .sem-type-row { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
                .sem-type-badge { background: #f0f4ff; color: #1565c0; border-radius: 6px; padding: 3px 8px; font-size: 12px; }
                .sem-samples { margin-top: 8px; border-top: 1px solid var(--border); padding-top: 8px; }
                .sem-sample { font-family: 'SF Mono', Menlo, monospace; font-size: 11px; color: var(--text3); margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
                .bmmodel-conf-name { min-width: 200px; }
                .bmmodel-signals { margin-top: 14px; border-top: 1px solid var(--border); padding-top: 10px; display: flex; flex-direction: column; gap: 4px; }
                .bmmodel-signal { font-size: 12px; color: var(--text2); display: flex; align-items: flex-start; gap: 6px; }
                @media (max-width: 768px) {
                    body { padding: 8px; }
                    .card { padding: 14px; border-radius: 12px; }
                    .summary-grid { grid-template-columns: repeat(3, 1fr); gap: 6px; }
                    .summary-card { padding: 10px 4px; }
                    .summary-card .num { font-size: 18px; }
                    .summary-card .label { font-size: 9px; }
                    h1 { font-size: 20px; }
                    h2 { font-size: 17px; }
                    .team-table, .file-table { font-size: 12px; min-width: 500px; }
                    .team-table th, .file-table th { padding: 6px; font-size: 10px; }
                    .team-table td, .file-table td { padding: 6px; }
                    .pkg-grid { grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); }
                    .tag { font-size: 11px; padding: 2px 6px; }
                    .hotspot-item { flex-direction: column; gap: 4px; }
                    .pkg-graph-container { height: 300px; }
                    .sec-toprow { flex-direction: column; gap: 14px; }
                    .sec-gauge-wrap { flex: 1 1 auto; }
                    .sec-weight-bars { min-width: 0; }
                    .sec-wb-name { min-width: 150px; font-size: 11px; }
                    .sec-check-name { min-width: 130px; font-size: 12px; }
                    .sec-sec-head { gap: 6px; }
                }
            </style>
            <script src="https://unpkg.com/force-graph"></script>
        </head>
        <body>
        <div class="container">
            <div class="top-actions">
                <div class="pill-seg">
                    <button class="seg-btn" id="theme-dark">🌙 Dark</button>
                    <button class="seg-btn" id="theme-light">☀ Light</button>
                </div>
                <div class="pill-seg">
                    <button class="seg-btn active" id="btn-html" onclick="switchView('html')">HTML</button>
                    <button class="seg-btn" id="btn-md" onclick="switchView('md')">MD</button>
                </div>
            </div>
            <div id="html-view">
            <div class="card">
                <h1>🔬 ArchSwiftScope 📋 \(esc(projectName.isEmpty ? "Project" : projectName))</h1>
                <p class="subtitle">Generated \(Date().formatted()) · <span class="branch-badge">\(esc(branchName))</span> branch</p>
                \({
                    let swiftCount = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count
                    let objcCount  = projectFiles.count - swiftCount
                    let swiftLines = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.reduce(0) { $0 + $1.lineCount }
                    let pct = totalLines > 0 ? Int(round(Double(swiftLines) / Double(totalLines) * 100)) : 100
                    let assetsMB = String(format: "%.1f", Double(metadata.assets.totalSizeBytes) / 1_048_576.0)
                    func sc(_ num: String, _ label: String, _ fs: String = "") -> String {
                        let style = fs.isEmpty ? "" : " style=\"font-size:\(fs)\""
                        return "<div class=\"summary-card\"><div class=\"num\"\(style)>\(num)</div><div class=\"label\">\(label)</div></div>"
                    }
                    var cards = ""
                    // 1. Language
                    if !metadata.swiftVersion.isEmpty { cards += sc("Swift \(esc(metadata.swiftVersion))", "Language", "20px") }
                    // 2. Lines of Code
                    cards += sc(totalLines.formatted(), "Lines of Code")
                    // 3. Swift Code % (mixed) or Swift Files count (pure Swift)
                    if objcCount > 0 {
                        cards += sc("\(pct)%", "Swift Code", "20px")
                    } else {
                        cards += sc("\(swiftCount)", "Swift Files")
                    }
                    // 4–5. Deployment / version
                    if !metadata.deploymentTargets.isEmpty { cards += sc(esc(metadata.deploymentTargets.joined(separator: ", ")), "Min Deployment", "16px") }
                    if !metadata.appVersion.isEmpty { cards += sc(esc(metadata.appVersion), "App Version", "20px") }
                    // 6–7. File counts (only in mixed Swift/ObjC projects)
                    if objcCount > 0 {
                        cards += sc("\(swiftCount)", "Swift Files")
                        cards += sc("\(objcCount)", "ObjC Files")
                    }
                    // 8–10. Structure counts
                    cards += sc("\(totalDecls)", "Declarations")
                    cards += sc("\(totalExts)", "Extensions")
                    cards += sc("\(packages.count)", "Packages")
                    // 11. Vendored libs
                    if !monkeyPatchedLibs.isEmpty { cards += sc("\(monkeyPatchedLibs.count)", "🐒 Vendored Libs") }
                    // 12. Assets (after Vendored Libs)
                    if metadata.assets.totalSizeBytes > 0 {
                        cards += sc("\(metadata.assets.allFiles.count) <span style=\"font-size:14px;font-weight:400;color:var(--text3)\">(\(assetsMB) MB)</span>", "Assets", "18px")
                    }
                    // 13–18. Type breakdown
                    cards += sc("\(totalStructs)", "🟢 Structs")
                    cards += sc("\(totalClasses)", "🔵 Classes")
                    cards += sc("\(totalEnums)", "🟡 Enums")
                    cards += sc("\(totalProtocols)", "🟣 Protocols")
                    cards += sc("\(totalActors)", "🔴 Actors")
                    if metadata.metalFiles.count > 0 { cards += sc("\(metadata.metalFiles.count)", "🔘 Metal") }
                    return "<div class=\"summary-grid\">\(cards)</div>"
                }())
            </div>
            \(buildVSCodeLinksCard(repoPath: repoPath, githubURL: githubURL, branchName: branchName, headCommit: headCommit))
            <div class="card">
                \(architectureCardHTML)
            </div>
            <div class="card">
                \(oopCardHTML)
            </div>
            \(hasProgrammingMethods ? "<div class=\"card\">\(programmingMethodsCardHTML)</div>" : "")
            \(trafficResult.hasData ? "<div class=\"card\">\(buildTrafficHTML(trafficResult))</div>" : "")
            <div class="card">
                \(apCardHTML)
            </div>
            <div class="card">
                <h2>🐙 Git Analysis</h2>
                \(!teamRows.isEmpty ? """
                <div class="sub-card">
                    <h3 class="sub-card-title">👥 Team Contribution Map</h3>
                    <div class="table-wrap"><table class="team-table">
                        <thead><tr><th>Developer</th><th>Files</th><th>Commits</th><th>LOC</th><th>LOC/Commit</th><th>First Change</th><th>Last Change</th><th>Top-3 Modules</th></tr></thead>
                        <tbody>\(teamRows)</tbody>
                    </table></div>
                </div>
                """ : "")
                \(!branchSubCard.isEmpty ? "<div class=\"sub-card\"><h3 class=\"sub-card-title\">🌿 Branch Management</h3>\(branchSubCard)</div>" : "")
                \(!branchingModelSubCardHTML.isEmpty ? "<div class=\"sub-card\"><h3 class=\"sub-card-title\">🔀 Branching Model</h3>\(branchingModelSubCardHTML)</div>" : "")
                <div class="sub-card">
                    <h3 class="sub-card-title">📐 Semantic Standards</h3>
                    \(semanticSubCard)
                </div>
                <div class="sub-card">
                    <h3 class="sub-card-title">🔥 Code Churn</h3>
                    \(churnSubCard)
                </div>
            </div>
            <div class="card">
                <h2>🔥 Hot Zones</h2>
                <p class="subtitle">Files imported or referenced by the most other files — the highest-leverage nodes in the codebase.</p>
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>File</th><th>Uses</th><th>Lines</th><th>Decl</th><th>Package</th></tr></thead>
                    <tbody>\(hotspotRows)</tbody>
                </table></div>
            </div>
            \(!topLongestFuncs.isEmpty ? """
            <div class="card">
                <h2>📏 Longest Functions</h2>
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>Function</th><th>Lines</th><th>File</th><th>Module</th></tr></thead>
                    <tbody>\(topLongestFuncs.map { fn -> String in
                        let fileName = URL(fileURLWithPath: fn.filePath).lastPathComponent
                        let pkg = fileMap[fn.filePath]?.packageName.isEmpty == false ? fileMap[fn.filePath]!.packageName : "App"
                        let anchor = pkg.replacingOccurrences(of: " ", with: "-")
                        return "<tr><td><code>\(vsLink(path: fn.filePath, label: esc(fn.name) + "()", line: fn.startLine))</code></td><td class='mono'>\(fn.lineCount)</td><td>\(vsLink(path: fn.filePath, label: esc(fileName), line: fn.startLine))</td><td><a href='#pkg-\(anchor)' class='pkg-link-inline'>\(esc(pkg))</a></td></tr>"
                    }.joined(separator: "\n"))</tbody>
                </table></div>
            </div>
            """ : "")
            \(!topBigTypes.isEmpty ? """
            <div class="card">
                <h2>📐 Biggest Named Types</h2>
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>Type</th><th>Kind</th><th>Lines</th><th>File</th><th>Module</th></tr></thead>
                    <tbody>\(topBigTypes.map { t -> String in
                        let fileName = URL(fileURLWithPath: t.filePath).lastPathComponent
                        let pkg = fileMap[t.filePath]?.packageName.isEmpty == false ? fileMap[t.filePath]!.packageName : "App"
                        let anchor = pkg.replacingOccurrences(of: " ", with: "-")
                        let kindLabel: String
                        switch t.kind {
                        case .class:    kindLabel = "<span class='tag tag-oop' style='font-size:11px;padding:2px 6px'>class</span>"
                        case .struct:   kindLabel = "<span class='tag tag-pop' style='font-size:11px;padding:2px 6px'>struct</span>"
                        case .enum:     kindLabel = "<span class='tag tag-mixed' style='font-size:11px;padding:2px 6px'>enum</span>"
                        case .protocol: kindLabel = "<span class='tag tag-local' style='font-size:11px;padding:2px 6px'>protocol</span>"
                        case .actor:    kindLabel = "<span class='tag tag-private' style='font-size:11px;padding:2px 6px'>actor</span>"
                        case .extension: kindLabel = ""
                        }
                        return "<tr><td><code>\(vsLink(path: t.filePath, label: esc(t.name), line: t.startLine))</code></td><td>\(kindLabel)</td><td class='mono'>\(t.lineCount)</td><td>\(vsLink(path: t.filePath, label: esc(fileName), line: t.startLine))</td><td><a href='#pkg-\(anchor)' class='pkg-link-inline'>\(esc(pkg))</a></td></tr>"
                    }.joined(separator: "\n"))</tbody>
                </table></div>
            </div>
            """ : "")
            <div class="card">
                <h2>📋 Module Insights</h2>
                \(!topPenetration.isEmpty ? """
                <h3>🔗 Package Penetration</h3>
                <p class="subtitle">Modules imported by the most other packages — high-penetration modules are foundational dependencies.</p>
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>Module</th><th>Imported by</th><th>Dependent Packages</th></tr></thead>
                    <tbody>\(topPenetration.map { (name, dependents) -> String in
                        let anchor = name.replacingOccurrences(of: " ", with: "-")
                        let depList = dependents.sorted().prefix(5).joined(separator: ", ") + (dependents.count > 5 ? " …" : "")
                        return "<tr><td><a href='#pkg-\(anchor)' class='pkg-link-inline'>\(esc(name))</a></td><td class='mono'>\(dependents.count)</td><td style='color:var(--text3);font-size:12px'>\(esc(depList))</td></tr>"
                    }.joined(separator: "\n"))</tbody>
                </table></div>
                """ : "")
                <h3>📝 TODO / FIXME</h3>
                \(topTodoModules.isEmpty ? "<p style=\"color: var(--text3)\">No TODO or FIXME comments found across the codebase.</p>" : """
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>Module</th><th>TODO</th><th>FIXME</th><th>Total</th></tr></thead>
                    <tbody>\(topTodoModules.map { (name, todos) -> String in
                        let fixmes = moduleFixmes[name] ?? 0
                        let anchor = name.replacingOccurrences(of: " ", with: "-")
                        return "<tr><td><a href='#pkg-\(anchor)' class='pkg-link-inline'>\(esc(name))</a></td><td>\(todos)</td><td>\(fixmes)</td><td><strong>\(todos + fixmes)</strong></td></tr>"
                    }.joined(separator: "\n"))</tbody>
                </table></div>
                """)
            </div>
            \(renderModules ? """
            <div class="card">
                <h2>📦 Packages & Modules</h2>
                <p class="subtitle">Showing files with ≥ 20 lines and at least one declaration. Graphs: type references between declarations. <span style="color:#007aff">●</span> class <span style="color:#34c759">●</span> struct <span style="color:#ff9500">●</span> enum <span style="color:#ff3b30">●</span> actor. Arrows from class/actor only.</p>
                \(packageSections)
            </div>
            """ : "")
            \(metadata.assets.totalSizeBytes > 0 ? {
                let a = metadata.assets
                let totalMB = String(format: "%.1f", Double(a.totalSizeBytes) / 1_048_576.0)
                let imageExts: Set<String> = ["png", "jpg", "jpeg", "pdf", "svg", "heic", "webp", "gif", "jxl"]
                let audioExts: Set<String> = ["mp3", "wav", "aac", "m4a", "ogg", "flac", "caf", "aiff"]
                // videoExts: everything else
                func typeEmoji(_ ext: String) -> String {
                    if imageExts.contains(ext) { return "🖼️" }
                    if audioExts.contains(ext) { return "🎧" }
                    return "📺"
                }
                // Group files by type, sorted by size desc
                var filesByType: [String: [AssetFileInfo]] = [:]
                for f in a.allFiles { filesByType[f.ext, default: []].append(f) }
                for key in filesByType.keys { filesByType[key]?.sort { $0.sizeBytes > $1.sizeBytes } }
                let sortedTypes = a.countByType.keys.sorted { (a.sizeByType[$0] ?? 0) > (a.sizeByType[$1] ?? 0) }
                let typeRows = sortedTypes.map { ext -> String in
                    let count = a.countByType[ext] ?? 0
                    let sizeBytes = a.sizeByType[ext] ?? 0
                    let sizeMB = String(format: "%.1f", Double(sizeBytes) / 1_048_576.0)
                    let top3 = (filesByType[ext] ?? []).prefix(3)
                    let heaviestHTML: String
                    if top3.isEmpty {
                        heaviestHTML = "—"
                    } else {
                        heaviestHTML = top3.map { f in
                            let sz = self.formatFileSize(f.sizeBytes)
                            let absPath = repoPath.isEmpty ? f.relativePath : "\(repoPath)/\(f.relativePath)"
                            let pathLink = self.vsLink(path: absPath, label: "<span style='font-size:12px'>\(esc(f.relativePath))</span>")
                            return "<div style='margin:2px 0'><span class='bs-badge-right' style='margin-left:0;margin-right:6px'>\(sz)</span>\(pathLink)</div>"
                        }.joined()
                    }
                    let emoji = typeEmoji(ext)
                    return "<tr><td>\(emoji) <strong>.\(esc(ext))</strong></td><td class='mono'>\(count)</td><td class='mono'>\(sizeMB) MB</td><td>\(heaviestHTML)</td></tr>"
                }.joined(separator: "\n")
                let otherHTML: String
                if !a.otherHeavyExtensions.isEmpty {
                    let exts = a.otherHeavyExtensions.sorted().map { "📄 .\($0)" }.joined(separator: "&ensp;")
                    otherHTML = "<p style='margin-top:12px;color:var(--text3);font-size:13px'>Detected other heavy files in .xcassets: \(exts)</p>"
                } else {
                    otherHTML = ""
                }
                return """
            <div class="card">
                <h2>🎨 Assets — \(totalMB) MB</h2>
                <div class="table-wrap"><table class="file-table">
                    <thead><tr><th>Type</th><th>Files</th><th>Size</th><th>Top-3 Heaviest Files</th></tr></thead>
                    <tbody>\(typeRows)</tbody>
                </table></div>
                \(otherHTML)
            </div>
            """
            }() : "")
            <footer style="text-align:center; padding: 20px 0 10px; color: var(--text3); font-size: 12px;">
                Generator: <a href="https://github.com/Exey/ArchSwiftScope" style="color: var(--accent); text-decoration: none;">ArchSwiftScope</a> · MIT License · Exey Panteleev
            </footer>
            </div>
            <div id="md-view" style="display:none">
                <div class="card">
                    <div class="md-toolbar">
                        <button class="md-copy-btn" onclick="copyMD()">Copy Markdown</button>
                    </div>
                    <pre class="md-pre" id="md-content">\(esc(mdContent))</pre>
                </div>
            </div>
        </div>
        <script>
        window.SECURITY_DATA = \(securityScoreJSONLiteral);
        (function(){
            var D = window.SECURITY_DATA;
            var svg = document.getElementById('sec-gauge-svg');
            if (!svg || !D) return;

            // Half-gauge geometry.
            var r = 80, cx = 100, cy = 104;
            var ns = 'http://www.w3.org/2000/svg';

            // Background arc (left → right semicircle).
            var bg = document.createElementNS(ns, 'path');
            bg.setAttribute('d', 'M ' + (cx - r) + ',' + cy + ' A ' + r + ',' + r + ' 0 0 1 ' + (cx + r) + ',' + cy);
            bg.setAttribute('fill', 'none');
            bg.setAttribute('stroke', '#e0e0e0');
            bg.setAttribute('stroke-width', '16');
            bg.setAttribute('stroke-linecap', 'round');
            svg.appendChild(bg);

            // Foreground arc proportional to score / 1000.
            var pct = Math.min(Math.max(D.score / 1000, 0.001), 0.999);
            var endAngle = Math.PI * (1 - pct);
            var ex = cx + r * Math.cos(endAngle);
            var ey = cy - r * Math.sin(endAngle);
            var col = pct < 0.20 ? '#5a8a7a' : pct < 0.50 ? '#a0a030' : pct < 0.80 ? '#c0a030' : '#c05040';
            var fg = document.createElementNS(ns, 'path');
            fg.setAttribute('d', 'M ' + (cx - r) + ',' + cy + ' A ' + r + ',' + r + ' 0 0 1 ' + ex.toFixed(2) + ',' + ey.toFixed(2));
            fg.setAttribute('fill', 'none');
            fg.setAttribute('stroke', col);
            fg.setAttribute('stroke-width', '16');
            fg.setAttribute('stroke-linecap', 'round');
            svg.appendChild(fg);

            // Band legend with current-band marker.
            var ranges = [
                { lo: 0,   hi: 199,  col: '#5a8a7a', label: 'Hardened' },
                { lo: 200, hi: 499,  col: '#a0a030', label: 'Minor exposure' },
                { lo: 500, hi: 799,  col: '#c0a030', label: 'Elevated risk' },
                { lo: 800, hi: 1000, col: '#c05040', label: 'Critical exposure' }
            ];
            var desc = '';
            for (var i = 0; i < ranges.length; i++) {
                var rg = ranges[i];
                var cur = D.score >= rg.lo && D.score <= rg.hi;
                desc += '<div' + (cur ? ' class="cur"' : '') + '>'
                      + '<span class="rng" style="background:' + rg.col + '"></span>'
                      + rg.lo + '–' + rg.hi + ': ' + rg.label + (cur ? ' ◂' : '') + '</div>';
            }
            var el = document.getElementById('sec-gauge-desc');
            if (el) el.innerHTML = desc;
        })();
        var __graphs = [];
        (function() {
            if (typeof ForceGraph === 'undefined') {
                [].forEach.call(document.querySelectorAll('[id$="graph"]'), function(el) {
                    el.style.cssText = 'display:flex;align-items:center;justify-content:center;';
                    el.innerHTML = '<span style="color:var(--text3);font-size:12px;font-style:italic">Graph unavailable (requires internet connection)</span>';
                });
                return;
            }
            \(packageGraphScripts)
        })();
        (function(){
            var vsBtn = document.getElementById('vs-path-btn');
            if (vsBtn) {
                vsBtn.addEventListener('click', function(){
                    var inp = document.getElementById('vs-path-input');
                    var msg = document.getElementById('vs-path-msg');
                    if (!inp) return;
                    var newBase  = inp.value.trim().replace(/\\/+$/, '');
                    var origBase = inp.dataset.orig;
                    if (!newBase || newBase === origBase) return;
                    var prefix    = 'vscode://file' + origBase;
                    var newPrefix = 'vscode://file' + newBase;
                    var links = document.querySelectorAll('a[href^="' + prefix + '"]');
                    links.forEach(function(a){
                        a.setAttribute('href', newPrefix + a.getAttribute('href').slice(prefix.length));
                    });
                    inp.dataset.orig = newBase;
                    if (msg) msg.textContent = links.length + ' links updated';
                });
            }
        })();
        function switchView(mode) {
            var hv = document.getElementById('html-view');
            var mv = document.getElementById('md-view');
            var bh = document.getElementById('btn-html');
            var bm = document.getElementById('btn-md');
            if (hv) hv.style.display = mode === 'html' ? '' : 'none';
            if (mv) mv.style.display = mode === 'md' ? '' : 'none';
            if (bh) bh.classList.toggle('active', mode === 'html');
            if (bm) bm.classList.toggle('active', mode === 'md');
            localStorage.setItem('archswift-view', mode);
        }
        function copyMD() {
            var pre = document.getElementById('md-content');
            if (!pre) return;
            navigator.clipboard.writeText(pre.textContent).then(function() {
                var btn = document.querySelector('.md-copy-btn');
                if (btn) { btn.textContent = 'Copied!'; setTimeout(function(){ btn.textContent = 'Copy Markdown'; }, 2000); }
            });
        }
        (function(){
            var lightBtn = document.getElementById('theme-light');
            var darkBtn  = document.getElementById('theme-dark');
            var root     = document.documentElement;
            function applyTheme(t) {
                root.setAttribute('data-theme', t);
                if (lightBtn) lightBtn.classList.toggle('active', t === 'light');
                if (darkBtn)  darkBtn.classList.toggle('active',  t === 'dark');
                localStorage.setItem('archswift-theme', t);
                __graphs.forEach(function(g) { try { g.refresh(); } catch(e){} });
            }
            applyTheme(localStorage.getItem('archswift-theme') || 'light');
            lightBtn && lightBtn.addEventListener('click', function() { applyTheme('light'); });
            darkBtn  && darkBtn.addEventListener('click',  function() { applyTheme('dark'); });
        })();
        (function(){
            switchView(localStorage.getItem('archswift-view') || 'html');
        })();
        </script>
        </body>
        </html>
        """

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        print("   HTML written (\((html.utf8.count / 1024))KB)")
    }

    // MARK: - Declaration-Level Graph Builder

    private func buildDeclarationGraph(for pkg: PackageSummary, pageRankScores: [String: Double]) -> GraphData {
        let eligibleFiles = pkg.files.filter {
            !$0.filePath.contains("/Tests/") && !$0.filePath.contains("/Test/") &&
            $0.fileName != "Package.swift" && $0.fileName != "Project.swift"
        }

        struct DeclInfo {
            let name: String; let kind: Declaration.Kind; let filePath: String; let fileName: String
        }

        let graphKinds: Set<Declaration.Kind> = [.class, .struct, .enum, .actor]
        var allDecls: [DeclInfo] = []

        for file in eligibleFiles {
            for decl in file.declarations where graphKinds.contains(decl.kind) && decl.name.count >= 4 && !Declaration.invalidNames.contains(decl.name) {
                allDecls.append(DeclInfo(name: decl.name, kind: decl.kind, filePath: file.filePath, fileName: file.fileName))
            }
        }

        // Cap: for large modules, keep top declarations by file PageRank
        if allDecls.count > maxGraphDeclarations {
            allDecls.sort { (pageRankScores[$0.filePath] ?? 0) > (pageRankScores[$1.filePath] ?? 0) }
            allDecls = Array(allDecls.prefix(maxGraphDeclarations))
        }

        let nodes: [GraphNode] = allDecls.map { d in
            GraphNode(id: "\(d.filePath)::\(d.name)", label: d.name, sublabel: d.fileName,
                      kind: d.kind.rawValue, score: pageRankScores[d.filePath] ?? 0.001, group: pkg.name)
        }

        // Build edges — only class/actor emit outgoing
        let outgoingKinds: Set<Declaration.Kind> = [.class, .actor]
        let outgoingDecls = allDecls.filter { outgoingKinds.contains($0.kind) }
        let uniqueFilePaths = Array(Set(outgoingDecls.map(\.filePath)))

        // Parallel read + tokenize: O(file_length) once per file, then O(1) per type check
        var tokenSetsArr: [Set<String>?] = Array(repeating: nil, count: uniqueFilePaths.count)
        DispatchQueue.concurrentPerform(iterations: uniqueFilePaths.count) { idx in
            guard let content = try? String(contentsOfFile: uniqueFilePaths[idx], encoding: .utf8) else { return }
            tokenSetsArr[idx] = graphTokenize(content)
        }
        var tokenCache: [String: Set<String>] = [:]
        for (idx, path) in uniqueFilePaths.enumerated() {
            if let t = tokenSetsArr[idx] { tokenCache[path] = t }
        }

        var links: [GraphLink] = []
        var seenEdges: Set<String> = []
        for source in outgoingDecls {
            guard let tokens = tokenCache[source.filePath] else { continue }
            for target in allDecls where target.name != source.name {
                let ek = "\(source.name)->\(target.name)"
                guard !seenEdges.contains(ek) else { continue }
                if tokens.contains(target.name) {
                    links.append(GraphLink(source: "\(source.filePath)::\(source.name)", target: "\(target.filePath)::\(target.name)"))
                    seenEdges.insert(ek)
                }
            }
        }

        let connectedIds: Set<String> = Set(links.flatMap { [$0.source, $0.target] })
        let connectedNodes = nodes.filter { connectedIds.contains($0.id) }
        return GraphData(nodes: connectedNodes, links: links)
    }

    private func graphTokenize(_ content: String) -> Set<String> {
        var tokens = Set<String>()
        var i = content.startIndex
        while i < content.endIndex {
            let c = content[i]
            if c.isLetter || c == "_" {
                let start = i
                var len = 1
                i = content.index(after: i)
                while i < content.endIndex {
                    let nc = content[i]
                    guard nc.isLetter || nc.isNumber || nc == "_" else { break }
                    len += 1
                    i = content.index(after: i)
                }
                if len >= 4 { tokens.insert(String(content[start..<i])) }
            } else {
                i = content.index(after: i)
            }
        }
        return tokens
    }

    private func kindIcon(_ kind: Declaration.Kind) -> String {
        switch kind { case .class: return "🔵"; case .struct: return "🟢"; case .enum: return "🟡"; case .protocol: return "🟣"; case .actor: return "🔴"; case .extension: return "🔹" }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// `occ.module` as reported by the parser, when it has one; otherwise the
    /// file's immediate containing folder, so a construct occurrence in a
    /// project with no SwiftPM `Sources/<Module>` layout or `Package.swift`
    /// (a plain Xcode-target codebase) still gets *some* grouping label
    /// instead of no badge at all. This is a display-only fallback — it
    /// never writes back into `ParsedFile.moduleName`, which other sections
    /// (the dependency graph, traffic scanner) rely on meaning "SwiftPM
    /// module", not "nearest folder".
    private func moduleBadgeLabel(_ module: String, filePath: String) -> String {
        guard module.isEmpty else { return module }
        return URL(fileURLWithPath: filePath).deletingLastPathComponent().lastPathComponent
    }

    private func vsLink(path: String, label: String, line: Int? = nil) -> String {
        let href = line.map { "vscode://file/\(path):\($0)" } ?? "vscode://file/\(path)"
        let lineAttr = line.map { " data-line=\"\($0)\"" } ?? ""
        return "<a href=\"\(href)\" class=\"vs-link\" data-path=\"\(path)\"\(lineAttr) title=\"Open in VS Code\">\(label)</a>"
    }

    // MARK: - VS Code Links Card

    private func buildVSCodeLinksCard(repoPath: String, githubURL: String = "", branchName: String = "main", headCommit: String = "") -> String {
        guard !repoPath.isEmpty else { return "" }
        let safePath = esc(repoPath)
        let safeGithub = esc(githubURL.trimmingCharacters(in: .init(charactersIn: "/")))
        let safeBranch = esc(branchName)
        let safeCommit = headCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        let blobRef = safeCommit.isEmpty ? safeBranch : safeCommit
        let hasGithub = !githubURL.isEmpty
        let githubToggle = hasGithub ? """
            <div class="pill-seg" style="margin-left:auto">
                <button class="seg-btn active" id="btn-link-vscode">VS Code</button>
                <button class="seg-btn" id="btn-link-github">GitHub</button>
            </div>
        """ : ""
        return """
        <div class="card" id="vs-links-card" style="padding:14px 28px">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px;flex-wrap:wrap">
                <span style="font-size:18px">🔗</span>
                <h3 style="margin:0;font-size:15px;font-weight:600;color:var(--text)">Links</h3>
                \(githubToggle)
            </div>
            <div id="vs-path-row">
                <p style="font-size:13px;color:var(--text3);margin:0 0 10px">Edit the path prefix for <code style="font-family:'SF Mono',Menlo,monospace;font-size:12px">vscode://</code> links — useful when sharing this report with someone whose project is at a different location.</p>
                <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
                    <input id="vs-path-input" type="text" value="\(safePath)" data-orig="\(safePath)"
                        style="flex:1;min-width:200px;padding:6px 10px;background:var(--bg);border:1px solid var(--border);border-radius:6px;color:var(--text);font-family:'SF Mono',Menlo,monospace;font-size:12px;outline:none">
                    <button id="vs-path-btn" style="padding:6px 14px;background:var(--accent);color:#fff;border:none;border-radius:6px;font-size:13px;font-weight:500;cursor:pointer;white-space:nowrap">Change Path</button>
                    <span id="vs-path-msg" style="font-size:12px;color:var(--text3)"></span>
                </div>
            </div>
            \(hasGithub ? "<div id=\"vs-github-row\" style=\"display:none\"><p style=\"font-size:13px;color:var(--text3);margin:0\">Links open files on <a href=\"\(safeGithub)\" target=\"_blank\" style=\"color:var(--accent)\">\(safeGithub)</a> at <code style=\"font-family:'SF Mono',Menlo,monospace;font-size:12px\">\(blobRef.count == 40 ? String(blobRef.prefix(7)) : blobRef)</code>.</p></div>" : "")
        </div>
        <script>
        (function(){
            var REPO_PATH  = '\(safePath)';
            var GITHUB_URL = '\(safeGithub)';
            var BLOB_REF   = '\(blobRef)';
            function setLinkMode(mode) {
                document.querySelectorAll('a.vs-link').forEach(function(a) {
                    var path = a.dataset.path || '';
                    var line = a.dataset.line || '';
                    if (mode === 'github' && GITHUB_URL) {
                        var rel = path.startsWith(REPO_PATH) ? path.slice(REPO_PATH.length).replace(/^\\//, '') : path;
                        var url = GITHUB_URL + '/blob/' + BLOB_REF + '/' + rel;
                        if (line) url += '#L' + line;
                        a.href = url;
                        a.setAttribute('target', '_blank');
                        a.title = 'Open on GitHub';
                    } else {
                        a.href = 'vscode://file' + path + (line ? ':' + line : '');
                        a.removeAttribute('target');
                        a.title = 'Open in VS Code';
                    }
                });
                var pr = document.getElementById('vs-path-row');
                var gr = document.getElementById('vs-github-row');
                var bvs = document.getElementById('btn-link-vscode');
                var bgh = document.getElementById('btn-link-github');
                if (pr)  pr.style.display  = mode === 'github' ? 'none' : '';
                if (gr)  gr.style.display  = mode === 'github' ? '' : 'none';
                if (bvs) bvs.classList.toggle('active', mode !== 'github');
                if (bgh) bgh.classList.toggle('active', mode === 'github');
                localStorage.setItem('archswift-linkmode', mode);
            }
            // Defer until all vs-link elements exist in the DOM
            document.addEventListener('DOMContentLoaded', function() {
                var saved = \(hasGithub ? "localStorage.getItem('archswift-linkmode') || 'github'" : "'vscode'");
                setLinkMode(saved);
                var bvs = document.getElementById('btn-link-vscode');
                var bgh = document.getElementById('btn-link-github');
                if (bvs) bvs.addEventListener('click', function(){ setLinkMode('vscode'); });
                if (bgh) bgh.addEventListener('click', function(){ setLinkMode('github'); });
            });
        })();
        </script>
        """
    }

    // MARK: - Framework Categorization

    private func buildCategorizedFrameworksHTML(frameworks: Set<String>, tagClass: String) -> String {
        guard !frameworks.isEmpty else { return "" }
        let categories: [(icon: String, name: String)] = [
            ("📱", "UI/Media"),
            ("🗄️", "Data/Networking"),
            ("⚙️", "Architecture/System"),
            ("🔧", "Dev Tools"),
        ]
        var buckets: [String: [String]] = [:]
        for fw in frameworks {
            buckets[frameworkCategory(fw), default: []].append(fw)
        }
        for key in buckets.keys { buckets[key]?.sort() }

        // flex-grow proportional to item count so larger categories get more width
        let cols = categories.compactMap { cat -> String? in
            guard let items = buckets[cat.name], !items.isEmpty else { return nil }
            let n = items.count
            let tags = items.map { "<span class='tag \(tagClass)'>\(esc($0))</span>" }.joined(separator: " ")
            return "<div style='flex:\(n) 0 140px;min-width:120px'><div class='fw-cat-col-head'>\(cat.icon) \(cat.name)</div><div class='tag-cloud' style='line-height:2'>\(tags)</div></div>"
        }
        guard !cols.isEmpty else { return "" }
        return "<div style='display:flex;flex-wrap:wrap;gap:12px 20px;margin-top:4px;align-items:flex-start'>\(cols.joined(separator: "\n"))</div>"
    }

    private func frameworkCategory(_ name: String) -> String {
        let full = name.lowercased()
        let base = (name.components(separatedBy: ".").first ?? name).lowercased()

        // os.* submodules — split before the base lookup
        if base == "os" {
            if full.contains("signpost") || full.contains("log") { return "Dev Tools" }
            return "Architecture/System"  // os.OSAllocatedUnfairLock, os.lock, etc.
        }

        // Architecture / System — reactive, DI, concurrency, system frameworks
        let arch: Set<String> = [
            // Reactive / functional
            "combine", "rxswift", "rxcocoa", "rxrelay", "rxblockingtestscheduler",
            "reactiveswift", "opencombine", "composablearchitecture", "reswift", "reactorkit",
            // DI
            "swinject", "resolver", "factory", "needle",
            // Utilities / concurrency
            "casepaths", "asyncalgorithms", "swiftcheck", "validatedpropertykit",
            "backgroundtasks", "notificationcenter", "objectivec",
            "notify", "simd", "argumentparser", "observation", "distributed",
            "synchronization", "orderedcollections", "swiftsignalkit", "tdbinding",
            "staticthreads", "swiftapi", "instance", "instanceimpl",
            "usernotifications", "pushkit", "dispatch",
            // Apple system / logic frameworks
            "foundation", "cocoa", "intents", "translation",
            "accelerate", "naturallanguage",
            // Native system / C++ libs
            "darwin", "glibc", "ucrt", "shellapi",
            "iokit", "javascriptcore",
            "endian", "expected", "filesystem", "mips", "nlohmann",
            "smmintrin", "span",
        ]
        if arch.contains(base) || base.hasPrefix("rx") { return "Architecture/System" }
        // C++ header-style names: fixed_*, vectors, shelf-pack, etc.
        if base.hasPrefix("fixed_") || base.hasPrefix("vectors") || base.contains("shelf-pack") { return "Architecture/System" }

        // Dev Tools — testing, linting, build, logging, crypto
        let dev: Set<String> = [
            "xctest", "testing", "swifttesting", "quick", "nimble", "snapshottesting",
            "swiftlint", "swiftformat", "swiftgen", "sourcery",
            "swiftsyntax", "swiftsyntaxbuilder", "swiftsyntaxmacros", "swiftsyntaxmacroexpansion",
            "swiftcompilerplugin", "languageserverprotocol", "buildserverprotocol", "symbolkit",
            "packagedescription", "xcodeproj", "xcodegen", "tuist", "pbxproj", "xcscheme",
            "bazelrunfiles", "bazeltestobservation",
            "oslog", "pulse", "swiftlog", "cocoalumberjack", "ddlog",
            "cryptokit", "jwtkit", "commoncrypto",
            "endpointsecurity", "coreservices", "mobilecoreservices",
            "pathkit", "rainbow", "swiftcli", "swiftcmodule",
            "spectre", "customdump", "appcenter", "appcentercrashe", "appcentercrashs",
            "fabkitprotocol", "boost", "lldb",
            "assertmacros", "languageserverprotocoltransport",
            "testingutils",
        ]
        if dev.contains(base) { return "Dev Tools" }
        if base.hasPrefix("bazel") || (base.contains("syntax") && base.contains("swift")) { return "Dev Tools" }

        // UI / Media — rendering, AV, AR/VR, maps, UI toolkits
        let ui: Set<String> = [
            "swiftui", "uikit", "appkit", "tvuikit", "watchkit", "tvservices",
            "snapkit", "tinyconstraints", "hero", "lottie", "charts", "swiftuix", "tokamak",
            "avfaudio", "audiotoolbox", "audiounit", "avfoundation", "avkit",
            "callkit", "clockkit",
            "coregraphics", "coreimage", "coremedia", "coretext", "corevideo",
            "coreanimation", "corehaptics", "coremotion", "sensorkit",
            "eventkitui", "glkit", "iosurface", "linkpresentation",
            "mediaplayer", "messageui", "messages",
            "metalperformanceshaders", "metalkit", "metal",
            "pdfkit", "passkit", "quartzcore", "quicklook", "replaykit",
            "speech", "usernotificationsui", "visionkit",
            "asyncdisplaykit", "sdwebimage", "kingfisher", "nuke",
            "arkit", "realitykit", "scenekit", "spritekit", "gamekit", "gameplaykit",
            "mapkit", "corelocation", "corelocationui",
            "photos", "photosui", "vision",
            "widgetkit", "appintents",
            "tguikit", "fxpagecontrol", "componentflow", "display",
            "opengl", "opengles", "avrouting", "videotoolbox",
            "media", "thorvg", "gif_lib", "webp", "mozjpeg", "metal_stdlib",
            "ecore", "evas", "efl",
            // UI components / video capture / codec interfaces (Telegram-style vendored)
            "buttonsshared", "buttonsshared2", "uikitruntimeutils",
            "videocaptureinterface", "videocaptureinterfaceimpl",
            "calayer", "cgpath", "orientationmodule", "qrcodegenerator",
            "codec_api", "codec_app_def", "codec_def",
            "fakeaudiodevicemodule",
        ]
        if ui.contains(base) { return "UI/Media" }
        // Media codec libs (libavcodec, libavformat, libyuv, libswresample, …)
        if base.hasPrefix("lib") || base.hasPrefix("ecore") || base.hasPrefix("evas") { return "UI/Media" }

        // Data / Networking — storage, networking, serialisation, contacts
        // addressbook is contact data, not UI
        if base == "addressbook" || base == "addressbookui" { return "Data/Networking" }

        return "Data/Networking"
    }

    // MARK: - Data Structures Card

    private func buildDSHTML(_ matches: [DSMatch]) -> String {
        guard !matches.isEmpty else { return "" }
        let byCat = Dictionary(grouping: matches, by: \.category)
        // A lone populated category would otherwise sit in the left half of the
        // 2-column `.ds-sections` grid with the right half empty — let it span
        // the full card width instead.
        let populatedCats = DSCategory.allCases.filter { !(byCat[$0] ?? []).isEmpty }.count
        var h = "<div class='ds-sections'>"
        for cat in DSCategory.allCases {
            guard let items = byCat[cat], !items.isEmpty else { continue }
            h += "<div class='ds-group\(populatedCats == 1 ? " ds-group-full" : "")'>"
            h += "<div class='ds-group-head'>\(cat.icon) \(esc(cat.rawValue.uppercased()))</div>"
            h += "<div class='ds-items'>"
            for m in items {
                h += "<div class='ds-item'>"
                h += "<div class='ds-item-top'>\(dsNameHTML(m.name))<span class='ds-item-count'>\(m.count)</span></div>"
                if let detail = DataStructureDetector.detail(forLinkedMatch: m.name) {
                    h += "<div class='ds-item-detail'>\(esc(detail))</div>"
                }
                let maxOcc = 50
                let sortedOcc = m.occurrences.sorted { $0.module < $1.module }
                var occParts: [String] = []
                for (idx, occ) in sortedOcc.enumerated() {
                    if idx == maxOcc { occParts.append("<span class='ds-occ ds-more'>+\(sortedOcc.count - maxOcc) more</span>"); break }
                    let label = occ.line > 0 ? "\(esc(occ.typeName)):\(occ.line)" : esc(occ.typeName)
                    let link = occ.line > 0
                        ? vsLink(path: occ.filePath, label: label, line: occ.line)
                        : vsLink(path: occ.filePath, label: label)
                    let modLabel = moduleBadgeLabel(occ.module, filePath: occ.filePath)
                    let modBadge = modLabel.isEmpty ? "" : "<span class='ds-module'>\(esc(modLabel))</span>"
                    occParts.append("<span class='ds-occ'>\(modBadge)\(link)</span>")
                }
                h += "<div class='ds-item-occ'>\(occParts.joined())</div>"
                h += "</div>"
            }
            h += "</div></div>"
        }
        h += "</div>"
        return h
    }

    private func dsNameHTML(_ name: String) -> String {
        guard let url = WikipediaLinks.url(forDataStructure: name) else {
            return "<span class='ds-item-name'>\(esc(name))</span>"
        }
        return "<a class='ds-item-name ds-wiki-link' href=\"\(url)\" target='_blank' rel='noopener noreferrer' title='Wikipedia: \(esc(name))'>\(esc(name))</a>"
    }

    private func algoNameHTML(_ name: String) -> String {
        guard let url = WikipediaLinks.url(forAlgorithm: name) else {
            return "<span class='ds-item-name'>\(esc(name))</span>"
        }
        return "<a class='ds-item-name ds-wiki-link' href=\"\(url)\" target='_blank' rel='noopener noreferrer' title='Wikipedia: \(esc(name))'>\(esc(name))</a>"
    }

    // MARK: - Algorithms Card

    private func buildAlgoHTML(_ matches: [AlgoMatch]) -> String {
        guard !matches.isEmpty else { return "" }
        let byCat = Dictionary(grouping: matches, by: \.category)
        let populatedCats = AlgoCategory.allCases.filter { !(byCat[$0] ?? []).isEmpty }.count
        var h = "<div class='ds-sections'>"
        for cat in AlgoCategory.allCases {
            guard let items = byCat[cat], !items.isEmpty else { continue }
            h += "<div class='ds-group\(populatedCats == 1 ? " ds-group-full" : "")'>"
            h += "<div class='ds-group-head'>\(cat.icon) \(esc(cat.rawValue.uppercased()))</div>"
            h += "<div class='ds-items'>"
            for m in items {
                h += "<div class='ds-item'>"
                h += "<div class='ds-item-top'>\(algoNameHTML(m.name))<span class='ds-item-count'>\(m.count)</span></div>"
                let maxOcc = 50
                let sortedOcc = m.occurrences.sorted { $0.module < $1.module }
                var occParts: [String] = []
                for (idx, occ) in sortedOcc.enumerated() {
                    if idx == maxOcc { occParts.append("<span class='ds-occ ds-more'>+\(sortedOcc.count - maxOcc) more</span>"); break }
                    let label = occ.line > 0 ? "\(esc(occ.symbol)):\(occ.line)" : esc(occ.symbol)
                    let link = occ.line > 0
                        ? vsLink(path: occ.filePath, label: label, line: occ.line)
                        : vsLink(path: occ.filePath, label: label)
                    let modLabel = moduleBadgeLabel(occ.module, filePath: occ.filePath)
                    let modBadge = modLabel.isEmpty ? "" : "<span class='ds-module'>\(esc(modLabel))</span>"
                    occParts.append("<span class='ds-occ'>\(modBadge)\(link)</span>")
                }
                h += "<div class='ds-item-occ'>\(occParts.joined())</div>"
                h += "</div>"
            }
            h += "</div></div>"
        }
        h += "</div>"
        return h
    }

    // MARK: - Magic Constants Card

    private func buildConstantsHTML(_ matches: [ConstantMatch]) -> String {
        guard !matches.isEmpty else { return "" }
        let byCat = Dictionary(grouping: matches, by: \.category)
        let populatedCats = AlgoCategory.allCases.filter { !(byCat[$0] ?? []).isEmpty }.count
        var h = "<div class='ds-sections'>"
        for cat in AlgoCategory.allCases {
            guard let items = byCat[cat], !items.isEmpty else { continue }
            h += "<div class='ds-group\(populatedCats == 1 ? " ds-group-full" : "")'>"
            h += "<div class='ds-group-head'>\(cat.icon) \(esc(cat.rawValue.uppercased()))</div>"
            h += "<div class='ds-items ds-items-2col'>"
            for m in items {
                h += "<div class='ds-item'>"
                h += "<div class='ds-item-top'>\(algoNameHTML(m.name))<span class='ds-item-count'>\(m.count)</span></div>"
                let maxOcc = 50
                let sortedOcc = m.occurrences.sorted { $0.module < $1.module }
                var occParts: [String] = []
                for (idx, occ) in sortedOcc.enumerated() {
                    if idx == maxOcc { occParts.append("<span class='ds-occ ds-more'>+\(sortedOcc.count - maxOcc) more</span>"); break }
                    let label = occ.line > 0 ? "\(esc(occ.symbol)):\(occ.line)" : esc(occ.symbol)
                    let link = occ.line > 0
                        ? vsLink(path: occ.filePath, label: label, line: occ.line)
                        : vsLink(path: occ.filePath, label: label)
                    let modLabel = moduleBadgeLabel(occ.module, filePath: occ.filePath)
                    let modBadge = modLabel.isEmpty ? "" : "<span class='ds-module'>\(esc(modLabel))</span>"
                    occParts.append("<span class='ds-occ'>\(modBadge)\(link)</span>")
                }
                h += "<div class='ds-item-occ'>\(occParts.joined())</div>"
                h += "</div>"
            }
            h += "</div></div>"
        }
        h += "</div>"
        return h
    }

    // MARK: - Big O Complexity Health

    private func buildComplexityHTML(_ report: ComplexityReport) -> String {
        guard report.hasData else { return "" }

        func healthColor(_ v: Int) -> String {
            v >= 80 ? "var(--green)" : v >= 50 ? "var(--orange)" : "var(--red)"
        }
        func bar(icon: String, label: String, value: Int, hotspots: Int) -> String {
            let hs = hotspots == 0 ? "no hotspots" : "\(hotspots) hotspot\(hotspots == 1 ? "" : "s")"
            return """
            <div class='bigo-bar'>\
            <div class='bigo-bar-head'><span>\(icon) \(esc(label))</span>\
            <span class='bigo-score' style='color:\(healthColor(value))'>\(value)<span class='bigo-score-max'>/100</span></span></div>\
            <div class='bigo-track'><div class='bigo-fill' style='width:\(value)%;background:\(healthColor(value))'></div></div>\
            <div class='bigo-bar-sub'>\(hs)</div>\
            </div>
            """
        }

        // Collection usage line
        let u = report.usage
        var usageParts: [String] = []
        if u.array > 0 {
            let lazySuffix = u.lazy > 0 ? " <span style='color:var(--text3)'>(lazy <b>\(u.lazy)</b>)</span>" : ""
            usageParts.append("Array <b>\(u.array)</b>\(lazySuffix)")
        }
        if u.dictionary > 0 { usageParts.append("Dictionary <b>\(u.dictionary)</b>") }
        if u.set > 0        { usageParts.append("Set <b>\(u.set)</b>") }
        if u.sequence > 0   { usageParts.append("Sequence <b>\(u.sequence)</b>") }
        let usageLine = usageParts.isEmpty ? ""
            : "<p class='bigo-usage'>Classic collections in use — \(usageParts.joined(separator: " · "))</p>"

        var h = "<p class='subtitle'>Heuristic estimate from iteration nesting (nested loops &amp; higher-order closures) and collection allocations. Anything O(N²) or worse is listed below.</p>"
        h += usageLine
        h += "<div class='bigo-bars'>"
        h += bar(icon: "⏱️", label: "Time Complexity Health", value: report.timeHealth, hotspots: report.timeViolations.count)
        h += bar(icon: "📦", label: "Space Complexity Health", value: report.spaceHealth, hotspots: report.spaceViolations.count)
        h += "</div>"

        func violationList(_ title: String, _ vs: [ComplexityViolation]) -> String {
            guard !vs.isEmpty else { return "" }
            let maxShown = 40
            var rows = ""
            for (i, v) in vs.enumerated() {
                if i == maxShown {
                    rows += "<div class='bigo-viol bigo-more'>+\(vs.count - maxShown) more</div>"
                    break
                }
                let fileName = URL(fileURLWithPath: v.filePath).lastPathComponent
                let link = vsLink(path: v.filePath, label: esc("\(fileName):\(v.line)"), line: v.line)
                let modBadge = v.module.isEmpty ? "" : "<span class='ds-module'>\(esc(v.module))</span>"
                let expClass: String
                switch v.order {
                case 2: expClass = "bigo-exp-2"
                case 3: expClass = "bigo-exp-3"
                case 4: expClass = "bigo-exp-4"
                default: expClass = "bigo-exp-n"
                }
                let orderBadge = v.exponentChar.isEmpty
                    ? "O(N)"
                    : "O(N<span class='bigo-exp \(expClass)'>\(v.exponentChar)</span>)"
                rows += """
                <div class='bigo-viol'>\
                <span class='bigo-order'>\(orderBadge)</span>\
                <span class='bigo-sym'>\(esc(v.symbol))</span>\
                <span class='bigo-reason'>\(esc(v.reason))</span>\
                <span class='bigo-link'>\(modBadge)\(link)</span>\
                </div>
                """
            }
            return "<div class='bigo-viol-group'><div class='bigo-viol-head'>\(esc(title))</div>\(rows)</div>"
        }

        let lists = violationList("⏱️ Time hotspots", report.timeViolations)
            + violationList("📦 Space hotspots", report.spaceViolations)
        if lists.isEmpty {
            h += "<p class='bigo-clean'>✓ No O(N²)+ hotspots detected.</p>"
        } else {
            h += lists
        }
        return h
    }

    // MARK: - Traffic Card

    private func buildTrafficHTML(_ result: TrafficResult) -> String {
        var h = "<h2>🛜 Traffic</h2>"
        h += "<p class=\"subtitle\">\(result.inbound.count) inbound · \(result.outbound.count) outbound connection signals detected from string literals.</p>"
        h += renderTrafficTable(title: "📥 Inbound", entries: result.inbound)
        h += renderTrafficTable(title: "📤 Outbound", entries: result.outbound)
        return h
    }

    private func renderTrafficTable(title: String, entries: [TrafficEntry]) -> String {
        var t = "<div class=\"sub-card\"><h3 class=\"sub-card-title\">\(title) <span class=\"count\">(\(entries.count))</span></h3>"
        if entries.isEmpty {
            t += "<p style=\"color:var(--text3);font-style:italic\">No signals detected.</p>"
        } else {
            // Group entries by (proto, display-uri); preserve insertion order
            struct TrafficGroup {
                let proto: String
                let uri: String
                let dataFmt: String
                var calls: [(filePath: String, module: String, line: Int)]
            }
            var groups: [TrafficGroup] = []
            var groupIndex: [String: Int] = [:]
            for e in entries {
                let displayURI = !e.port.isEmpty && !e.uri.contains(e.port) ? "\(e.uri):\(e.port)" : e.uri
                let key = "\(e.proto)|\(displayURI)"
                if let idx = groupIndex[key] {
                    groups[idx].calls.append((e.filePath, e.module.isEmpty ? "root" : e.module, e.line))
                } else {
                    groupIndex[key] = groups.count
                    groups.append(TrafficGroup(
                        proto: e.proto, uri: displayURI,
                        dataFmt: e.dataFmt.isEmpty ? "—" : e.dataFmt,
                        calls: [(e.filePath, e.module.isEmpty ? "root" : e.module, e.line)]
                    ))
                }
            }

            t += "<div class=\"table-wrap\"><table class=\"file-table\"><thead><tr>"
            t += "<th>Protocol</th><th>URI / Pattern</th><th>Data</th><th>Files · Modules</th>"
            t += "</tr></thead><tbody>"
            for g in groups {
                let data = esc(g.dataFmt)
                let filesHTML: String
                if g.calls.count == 1 {
                    let c = g.calls[0]
                    let fname = URL(fileURLWithPath: c.filePath).lastPathComponent
                    let link = vsLink(path: c.filePath, label: esc(fname), line: c.line > 0 ? c.line : nil)
                    filesHTML = "<span class=\"mono\">\(link)</span> <span style=\"color:var(--text3)\">·</span> <span class=\"mono\">\(esc(c.module))</span>"
                } else {
                    let items = g.calls.map { c -> String in
                        let fname = URL(fileURLWithPath: c.filePath).lastPathComponent
                        let link = vsLink(path: c.filePath, label: esc(fname), line: c.line > 0 ? c.line : nil)
                        return "<div class=\"traffic-file-item\"><span class=\"mono\">\(link)</span> <span style=\"color:var(--text3)\">·</span> <span class=\"mono\">\(esc(c.module))</span></div>"
                    }.joined()
                    filesHTML = "<div class=\"traffic-multi\">\(items)</div>"
                }
                let uriCell: String
                if g.calls.count > 1 {
                    uriCell = "<span class=\"mono\" style=\"font-weight:600\">\(esc(g.uri))</span> <span class=\"traffic-count\">\(g.calls.count)</span>"
                } else {
                    uriCell = "<span class=\"mono\">\(esc(g.uri))</span>"
                }
                t += "<tr>"
                t += "<td style=\"white-space:nowrap\">\(trafficProtoTag(g.proto))</td>"
                t += "<td>\(uriCell)</td>"
                t += "<td class=\"mono\" style=\"white-space:nowrap\">\(data)</td>"
                t += "<td>\(filesHTML)</td>"
                t += "</tr>"
            }
            t += "</tbody></table></div>"
        }
        t += "</div>"
        return t
    }

    private func trafficProtoTag(_ proto: String) -> String {
        let (bg, fg) = trafficProtoColors(proto)
        return "<span class=\"tag\" style=\"background:\(bg);color:\(fg);font-size:11px\">\(esc(proto))</span>"
    }

    private func trafficProtoColors(_ proto: String) -> (String, String) {
        switch proto {
        case "REST":      return ("#27ae60", "#fff")
        case "gRPC":      return ("#2980b9", "#fff")
        case "WebSocket": return ("#e67e22", "#fff")
        case "GraphQL":   return ("#8e44ad", "#fff")
        default:          return ("#7f8c8d", "#fff")
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes) B"
        }
    }

    // MARK: - Security Risks HTML

    /// Serializes the security score into a JS object literal consumed by the gauge script.
    private func securityScoreJSON(_ score: SecurityScore) -> String {
        let cats = score.categories.map { c -> String in
            "{id:\(c.category.rawValue),name:\"\(jsEsc(c.category.title))\",risk:\(c.riskPercent),points:\(c.points),weight:\(c.weight),assessed:\(c.notAssessed ? "false" : "true")}"
        }.joined(separator: ",")
        return "{score:\(score.total),cats:[\(cats)]}"
    }

    private func buildSecurityHTML(_ results: [APResult], score: SecurityScore) -> String {
        let passed = results.filter { $0.passed }
        let failed = results.filter { !$0.passed }

        // ── Header: gauge (left) + 13-category weight bars (right) ──
        var header = "<h2>🚨 Security Risks <span style=\"color:var(--text3);font-size:14px;font-weight:400\">(\(results.count) active checks · index 0–1000)</span></h2>"
        header += "<p class=\"subtitle\">Higher index = more risk. Index aggregates 14 weighted categories; each category's risk scales with violation density. Categories without active checks are shown as <em>not assessed</em>.</p>"

        // Left column: gauge placeholder (drawn by JS) + band legend.
        let gaugeBlock = """
        <div class="sec-gauge-wrap">
          <svg class="sec-gauge-svg" id="sec-gauge-svg" viewBox="0 0 200 124"></svg>
          <div class="sec-gauge-label">DANGER INDEX</div>
          <div class="sec-gauge-val" id="sec-gauge-val">\(score.total) / 1000</div>
          <div class="sec-gauge-desc" id="sec-gauge-desc"></div>
        </div>
        """

        // Right column: one weighted bar per category (risk %, weight, points).
        let catBars = score.categories.map { c -> String in secCategoryBar(c) }.joined()
        let weightBars = """
        <div class="sec-weight-bars">
          <div class="sec-weight-title">Category Weights → 1000 Index</div>
          \(catBars)
        </div>
        """

        let topRow = """
        <div class="sec-toprow">
          \(gaugeBlock)
          \(weightBars)
        </div>
        """

        // ── Pass / fail summary ──
        var summary = ""
        if !passed.isEmpty {
            summary += "<div class=\"ap-summary\"><span class=\"ap-pass-badge\">✓ \(passed.count) passed</span><span class=\"ap-fail-badge\">✗ \(failed.count) failed</span></div>"
        } else {
            summary += "<div class=\"ap-summary\"><span class=\"ap-fail-badge\">✗ \(failed.count) failed</span></div>"
        }

        // ── Per-category detail (OOP-vs-POP-style bars + violations) ──
        // Group results by category, preserving the 1...13 order.
        var resultsByCategory: [SecurityCategory: [APResult]] = [:]
        for r in results { resultsByCategory[r.check.category, default: []].append(r) }
        let scoreByCategory = Dictionary(uniqueKeysWithValues: score.categories.map { ($0.category, $0) })

        var detail = "<div class=\"sec-detail\">"
        for category in SecurityCategory.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let cs = scoreByCategory[category]
            detail += secCategorySection(
                category: category,
                results: resultsByCategory[category] ?? [],
                catScore: cs
            )
        }
        detail += "</div>"

        return header + topRow + summary + detail
    }

    /// A single weighted bar in the header's right-hand column.
    private func secCategoryBar(_ c: CategoryScore) -> String {
        let cat = c.category
        let riskColor = secRiskColor(c.riskPercent)
        let fillW = max(0, min(100, c.riskPercent))
        let valueText: String
        let barFill: String
        if c.notAssessed {
            valueText = "<span class=\"sec-wb-na\">not assessed</span>"
            barFill = "<div class=\"sec-wb-fill sec-wb-na-fill\" style=\"width:100%\"></div>"
        } else {
            valueText = "<span class=\"sec-wb-pts\" style=\"color:\(riskColor)\">\(c.points)/\(c.weight)</span>"
            barFill = "<div class=\"sec-wb-fill\" style=\"width:\(fillW)%;background:\(riskColor)\"></div>"
        }
        return """
        <div class="sec-wb-row">
          <span class="sec-wb-name"><span class="sec-wb-num">\(cat.rawValue)</span>\(cat.icon) \(esc(cat.title))</span>
          <div class="sec-wb-track">\(barFill)</div>
          \(valueText)
          <span class="sec-wb-weight">W \(cat.weight)</span>
        </div>
        """
    }

    /// A per-category detail section: header + (checks with bars & violations) or a "not assessed" note.
    private func secCategorySection(category: SecurityCategory, results: [APResult], catScore: CategoryScore?) -> String {
        let weightStr = "weight \(category.weight) / 1000"
        let assessed = !results.isEmpty

        // Section header bar.
        let riskPct = catScore?.riskPercent ?? 0
        let riskColor = secRiskColor(riskPct)
        let headerRight: String = assessed
            ? "<span class=\"sec-sec-risk\" style=\"color:\(riskColor)\">\(riskPct)% risk · \(catScore?.points ?? 0)/\(category.weight) pts</span>"
            : "<span class=\"sec-sec-risk sec-sec-na\">not assessed</span>"

        var html = """
        <div class="sec-sec">
          <div class="sec-sec-head">
            <span class="sec-sec-num">\(category.rawValue)</span>
            <span class="sec-sec-icon">\(category.icon)</span>
            <span class="sec-sec-title">\(esc(category.title))</span>
            <span class="sec-sec-weight">\(weightStr)</span>
            \(headerRight)
          </div>
          <div class="sec-sec-blurb">\(esc(category.blurb))</div>
        """

        if !assessed {
            html += "<div class=\"sec-sec-empty\">No active checks in this category yet — informational only, contributes 0 to the index.</div>"
            html += "</div>"
            return html
        }

        // Order checks HIGH → MEDIUM → LOW.
        let ordered = [APPriority.high, .medium, .low].flatMap { pri in
            results.filter { $0.check.priority == pri }
        }

        for r in ordered {
            // Use uncapped totalCount for bar width and label so 7823 force-unwraps
            // look different from 100, matching the CLI output.
            let count = r.totalCount
            let shown = r.violations.count
            let isFail = !r.passed
            let barColor = isFail ? secPriorityColor(r.check.priority) : "#5a8a7a"
            // Per-check bar width: scale absolute count on a log curve so big counts don't blow out.
            let barW: Int = {
                guard count > 0 else { return 0 }
                let v = min(100, Int((log(Double(count) + 1.0) / log(101.0) * 100).rounded()))
                return max(6, v)
            }()
            let statusIcon = isFail ? "✗" : "✓"
            let countLabel: String = {
                if !isFail { return "0" }
                return count > shown ? "\(count) (showing \(shown))" : "\(count)"
            }()

            html += """
            <div class="sec-check">
              <div class="sec-check-row">
                <span class="sec-check-status" style="color:\(isFail ? "var(--red)" : "#34c759")">\(statusIcon)</span>
                \(apPriBadge(r.check.priority))
                <span class="sec-check-name">\(esc(r.check.name))</span>
                <div class="sec-check-track"><div class="sec-check-fill" style="width:\(barW)%;background:\(barColor)"></div></div>
                <span class="sec-check-count" style="color:\(isFail ? "var(--red)" : "var(--text3)")">\(countLabel)</span>
              </div>
            """

            if isFail {
                html += "<div class=\"sec-check-desc\">\(esc(r.check.description))</div>"
                html += "<div class=\"sec-violations\">"
                for v in r.violations {
                    let authorBadge = v.author.map { "<span class=\"ap-author-badge\">\(esc($0))</span>" } ?? ""
                    let fileLabel = v.line > 0 ? "\(esc(v.file)):\(v.line)" : esc(v.file)
                    let fileRef = v.line > 0
                        ? vsLink(path: v.fullPath, label: fileLabel, line: v.line)
                        : "<span>\(fileLabel)</span>"
                    html += "<div class=\"ap-violation\"><span class=\"ap-file\">\(fileRef)</span><span class=\"ap-snippet\">\(esc(v.snippet))</span>\(authorBadge)</div>"
                }
                html += "</div>"
            }
            html += "</div>"
        }

        html += "</div>"
        return html
    }

    /// Risk-percent → band color (matches gauge bands).
    private func secRiskColor(_ pct: Int) -> String {
        switch pct {
        case ..<25:  return "#5a8a7a"
        case 25..<50: return "#a0a030"
        case 50..<75: return "#c0a030"
        default:      return "#c05040"
        }
    }

    /// Priority → bar color for failing checks.
    private func secPriorityColor(_ p: APPriority) -> String {
        switch p {
        case .high:   return "#c05040"
        case .medium: return "#c0a030"
        case .low:    return "#a0a030"
        }
    }

    /// Minimal JS-string escaping for embedding category names in a JS object literal.
    private func jsEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func apPriBadge(_ p: APPriority) -> String {
        switch p {
        case .high:   return "<span class=\"ap-priority ap-pri-high\">HIGH</span>"
        case .medium: return "<span class=\"ap-priority ap-pri-med\">MEDIUM</span>"
        case .low:    return "<span class=\"ap-priority ap-pri-low\">LOW</span>"
        }
    }

    // MARK: - OOP vs POP HTML

    private func buildOOPvsPOPHTML(_ s: OOPvsPOPStats) -> String {
        let pop = s.popScore
        let markerPct = max(4, min(96, pop))

        func accentColor(_ v: Int) -> String {
            v >= 60 ? "#34c759" : v >= 40 ? "#ff9500" : "#ff3b30"
        }
        func miniBar(_ v: Double) -> String {
            let w = Int(v * 100)
            let color = v >= 0.65 ? "#34c759" : v >= 0.40 ? "#ff9500" : "#ff3b30"
            return "<div style=\"display:flex;align-items:center;gap:6px\"><div style=\"flex:1;height:5px;background:var(--border);border-radius:3px;min-width:60px;overflow:hidden\"><div style=\"height:100%;width:\(w)%;background:\(color);border-radius:3px\"></div></div><span class=\"mono\" style=\"font-size:11px;color:var(--text3);min-width:28px;text-align:right\">\(w)%</span></div>"
        }
        func signal(_ v: Double) -> String {
            if v >= 0.65 { return "<span class='tag tag-pop'>POP</span>" }
            if v >= 0.40 { return "<span class='tag tag-mixed'>Mixed</span>" }
            return "<span class='tag tag-oop'>OOP</span>"
        }
        func catBar(_ score: Int, _ label: String, _ weight: String) -> String {
            let color = accentColor(score)
            return """
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:7px">\
            <span style="font-size:11px;color:var(--text3);min-width:160px">\(label)</span>\
            <div style="flex:1;height:6px;background:var(--border);border-radius:3px;overflow:hidden">\
            <div style="height:100%;width:\(score)%;background:\(color);border-radius:3px"></div></div>\
            <span class="mono" style="font-size:11px;min-width:32px;text-align:right;color:\(color)">\(score)%</span>\
            <span style="font-size:10px;color:var(--text3);min-width:36px">\(weight)</span>\
            </div>
            """
        }
        func sectionHeader(_ title: String) -> String {
            "<tr><td colspan='5' style=\"padding:10px 0 4px;font-size:11px;font-weight:600;color:var(--text3);letter-spacing:0.06em;text-transform:uppercase;border-top:2px solid var(--border)\">\(title)</td></tr>"
        }
        func row(_ n: Int, _ name: String, _ value: String, _ score: Double, _ inv: String = "") -> String {
            let invTag = inv.isEmpty ? "" : " <span style=\"font-size:10px;color:var(--text3)\">\(inv)</span>"
            let b = "border-top:1px solid var(--border)"
            return "<tr><td class=\"mono\" style=\"color:var(--text3);\(b)\">\(n)</td><td style=\"\(b)\">\(name)\(invTag)</td><td class=\"mono\" style=\"\(b)\">\(value)</td><td style=\"\(b)\">\(miniBar(score))</td><td style=\"\(b)\">\(signal(score))</td></tr>"
        }
        func infoRow(_ name: String, _ value: String) -> String {
            let b = "border-top:1px solid var(--border)"
            return "<tr><td style=\"\(b)\"></td><td style=\"\(b);color:var(--text3)\">\(name)</td><td class=\"mono\" style=\"\(b);color:var(--text3)\">\(value)</td><td style=\"\(b)\"></td><td style=\"\(b)\"></td></tr>"
        }

        func naBar() -> String {
            "<div style=\"display:flex;align-items:center;gap:6px\"><div style=\"flex:1;height:5px;background:var(--border);border-radius:3px;min-width:60px\"></div><span class=\"mono\" style=\"font-size:11px;color:var(--text3);min-width:28px;text-align:right\">N/A</span></div>"
        }
        func naRow(_ n: Int, _ name: String, _ reason: String) -> String {
            let b = "border-top:1px solid var(--border)"
            return "<tr><td class=\"mono\" style=\"color:var(--text3);\(b)\">\(n)</td><td style=\"\(b);color:var(--text3)\">\(name)</td><td class=\"mono\" style=\"\(b);color:var(--text3)\">\(reason)</td><td style=\"\(b)\">\(naBar())</td><td style=\"\(b);color:var(--text3)\">&mdash;</td></tr>"
        }

        let noProto = s.totalProtocols == 0
        let protoDensityVal = "\(s.totalProtocols) protocols · \(s.totalClasses + s.totalStructs) types"
        let implProtos     = s.singleConformerProtocols + s.multiConformerProtocols
        let protoExtVal    = implProtos > 0 ? "\(s.protocolExtWithCode) / \(implProtos) implemented" : "no implemented protocols"
        let assocVal       = "\(s.assocTypeCount) / \(s.totalProtocols) protocols"
        let genericFuncVal = "\(s.genericFuncCount) in \(s.totalClasses + s.totalStructs) types"
        let breadthVal     = "\(s.multiConformerProtocols) broad · \(s.singleConformerProtocols) single-impl · \(s.totalProtocols - s.multiConformerProtocols - s.singleConformerProtocols) untracked"
        let conformDist    = "0: \(s.typesWithZeroConformances) · 1: \(s.typesWithOneConformance) · 2+: \(s.typesWithTwoPlusConformances)"
        let protoHeader    = noProto ? "Protocol Design · (M1 only — no protocols defined)" : "Protocol Design"

        let someUserVal    = "\(s.someUserDefinedCount) usages of user-defined protocols"
        let protoCompVal   = "\(s.protocolCompositionCount) usages"

        let protoRows: [String] = noProto ? [
            sectionHeader(protoHeader),
            row(1, "Protocol definitions",                    protoDensityVal, s.s_protocolDensity),
            row(2, "Constrained generics",                    genericFuncVal,  s.s_genericFunc),
            naRow(3, "Conformance breadth",                   "no protocols — N/A"),
            naRow(4, "Protocol extensions with default impl", "no protocols — N/A"),
            naRow(5, "<code>associatedtype</code> usage",     "no protocols — N/A"),
            naRow(6, "<code>some</code> user-defined",        "no protocols — N/A"),
            naRow(7, "Protocol composition (<code>A &amp; B</code>)", "no protocols — N/A"),
            infoRow("↳ Per-type conformance distribution",    conformDist),
        ] : [
            sectionHeader(protoHeader),
            row(1, "Protocol definitions",                       protoDensityVal, s.s_protocolDensity),
            row(2, "Constrained generics",                       genericFuncVal,  s.s_genericFunc),
            row(3, "Conformance breadth",                        breadthVal,      s.s_conformanceBreadth, "↑ 2+ = POP"),
            row(4, "Protocol extensions with default impl",      protoExtVal,     s.s_protoExt),
            row(5, "<code>associatedtype</code> usage",          assocVal,        s.s_assocType),
            row(6, "<code>some</code> user-defined",             someUserVal,     s.s_someUser),
            row(7, "Protocol composition (<code>A &amp; B</code>)", protoCompVal, s.s_protoComposition),
            infoRow("↳ Per-type conformance distribution",       conformDist),
            infoRow("↳ <code>some</code> stdlib / framework",
                    "\(s.someFrameworkCount) usages  ·  SwiftUI idiom, weak signal"),
        ]

        let tbody = (protoRows + [
            sectionHeader("Value Semantics"),
            row(8,  "Struct vs Class ratio",
                "\(s.totalStructs) structs · \(s.totalClasses) classes",  s.s_structRatio),
            row(9,  "<code>final</code> keyword",
                "\(s.finalClasses) / \(s.totalClasses) classes",          s.s_final),
            row(10, "Enums with associated values",
                "\(s.enumsWithAssocValues) / \(s.totalEnums) enums",      s.s_enumAssoc),
            infoRow("↳ Extension count (informational)",
                    "\(s.extensionCount) extensions"),

            sectionHeader("Anti-inheritance"),
            row(11, "Inheritance depth",
                "avg \(String(format:"%.1f", s.avgInheritanceDepth)) · max \(s.maxInheritanceDepth) · \(s.deepInheritanceCount) deep ≥ 3",
                s.s_inheritDepth, "↓ lower = POP"),
            row(12, "<code>override</code> density",
                "\(s.overrideCount) in \(s.totalClasses) classes",        s.s_overrideDensity, "↓ lower = POP"),
            row(13, "NSObject inheritance",
                "\(s.nsObjectCount) / \(s.totalClasses) classes",          s.s_nsObject, "↓ lower = POP"),

            sectionHeader("Counter-signals"),
            infoRow("⚠ Singletons (static shared / instance)",
                    "\(s.singletonCount) found\(s.singletonCount > 0 ? " — OOP indicator" : "")"),
        ]).joined()

        let protoDesignLabel = noProto ? "Protocol Design (M1+generics)" : "Protocol Design"

        return """
        <h2>🧬 OOP vs POP</h2>
        <p class="subtitle">Style signal across \(s.totalTypes) types · Protocol Design 55% · Value Semantics 30% · Anti-inheritance 15%</p>
        <div style="margin:16px 0 24px">
          <div style="display:flex;justify-content:space-between;font-size:11px;color:var(--text3);margin-bottom:6px">
            <span>◀ OOP</span><span>POP ▶</span>
          </div>
          <div style="position:relative;height:14px;margin-bottom:20px">
            <div style="height:14px;border-radius:8px;background:linear-gradient(to right,#ff3b30 0%,#ff9500 40%,#34c759 100%)"></div>
            <div style="position:absolute;top:-5px;left:\(markerPct)%;transform:translateX(-50%);width:3px;height:24px;background:white;border-radius:2px;box-shadow:0 1px 4px rgba(0,0,0,0.35)"></div>
            <div style="position:absolute;top:-28px;left:\(markerPct)%;transform:translateX(-50%);background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:2px 8px;font-size:12px;font-weight:700;white-space:nowrap;box-shadow:0 1px 3px rgba(0,0,0,0.1);color:\(accentColor(pop))">\(pop)% POP</div>
          </div>
          \(catBar(s.protoDesignScore,    protoDesignLabel,     "W=55%"))
          \(catBar(s.valueSemanticsScore, "Value Semantics",    "W=30%"))
          \(catBar(s.antiInheritScore,    "Anti-inheritance",   "W=15%"))
        </div>
        <div class="table-wrap">
        <table class="file-table" style="table-layout:fixed">
          <colgroup>
            <col style="width:24px"><col style="width:40%"><col><col style="width:110px"><col style="width:70px">
          </colgroup>
          <thead><tr><th>#</th><th>Metric</th><th>Value</th><th>POP Score</th><th>Signal</th></tr></thead>
          <tbody>\(tbody)</tbody>
        </table>
        </div>
        """
    }

}

private extension Character {
    var isWordChar: Bool { isLetter || isNumber || self == "_" }
}
