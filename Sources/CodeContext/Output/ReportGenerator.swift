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
    private let maxGraphDeclarations = 80

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
        skipModules: Bool = false
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

        print("   Generating HTML sections...")

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
            return cleaned.sorted().map { "<span class='tag tag-external'>\(esc($0))</span>" }.joined(separator: " ")
        }()

        // Architecture LAYERS — classify files by path patterns
        var layerCounts: [String: (files: Int, lines: Int)] = [:]
        for file in projectFiles {
            let layer = classifyLayer(file.filePath)
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

        // Architecture COMPONENTS — detect from Apple frameworks used
        let usedAppleFrameworks = classifiedImports[.apple] ?? []
        let detectedComponents = detectComponents(appleFrameworks: usedAppleFrameworks)
        // Every framework name claimed by a detected component — excluded from the raw list below
        let componentCoveredFrameworks: Set<String> = detectedComponents.reduce(into: []) { $0.formUnion($1.frameworks) }
        let componentsHTML: String = {
            guard !detectedComponents.isEmpty else { return "" }
            let items = detectedComponents.map { c -> String in
                "<div class='component-item'><span class='component-icon'>\(c.icon)</span><div><div class='component-name'>\(esc(c.name))</div><div class='component-detail'>\(esc(c.detail))</div></div></div>"
            }.joined(separator: "\n")
            return "<div class='component-grid'>\(items)</div>"
        }()

        // Apple Frameworks — exclude any already shown in Components
        let filteredAppleFrameworks = usedAppleFrameworks.subtracting(componentCoveredFrameworks)
        let appleFrameworksCount = filteredAppleFrameworks.count
        let appleFrameworksHTML: String = {
            guard !filteredAppleFrameworks.isEmpty else { return "" }
            return filteredAppleFrameworks.sorted().map { "<span class='tag tag-apple'>\($0)</span>" }.joined(separator: " ")
        }()

        // ─── Security Risks ───
        print("   Running security checks...")
        let resolvedAPResults = apResults.isEmpty
            ? SecurityAnalyzer.run(files: projectFiles, repoPath: repoPath)
            : apResults
        let swiftFileCountForScore = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count
        let resolvedSecurityScore = securityScore
            ?? SecurityAnalyzer.computeScore(resolvedAPResults, fileCount: swiftFileCountForScore)
        let apCardHTML = buildSecurityHTML(resolvedAPResults, score: resolvedSecurityScore)
        let securityScoreJSONLiteral = securityScoreJSON(resolvedSecurityScore)

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
            for file in projectFiles {
                let key = file.packageName.isEmpty ? "App" : file.packageName
                pkgLines[key, default: 0] += file.lineCount
                pkgDecls[key, default: 0] += file.declarations.filter { $0.kind != .extension }.count
            }
            let lineThreshold = Double(totalLinesAll) * 0.015

            var content = ""
            if let localNames = classifiedImports[.local], !localNames.isEmpty {
                let hasApp = pkgLines["App", default: 0] > 0
                var tags: [String] = []
                if hasApp {
                    let appLines = pkgLines["App", default: 0]
                    tags.append("<a href='#pkg-App' class='tag tag-local pkg-link pkg-major'><span class='pkg-name'>📱 App</span><span class='bs-badge-right'>\(appLines.formatted()) loc</span></a>")
                }
                for name in localNames.sorted() {
                    let bs = packageBuildSystem[name]
                    let bsLabel = bs != nil && bs != .unknown ? "<span class='bs-badge-right'>\(bs!.rawValue)</span>" : ""
                    let anchor = name.replacingOccurrences(of: " ", with: "-")
                    let lines = pkgLines[name, default: 0]
                    let decls = pkgDecls[name, default: 0]
                    let isMajor = Double(lines) >= lineThreshold && lines >= 10_000 && decls >= 80
                    let metalIcon = metalPackages.contains(name) ? "🔘 " : ""
                    let majorClass = isMajor ? " pkg-major" : ""
                    tags.append("<a href='#pkg-\(anchor)' class='tag tag-local pkg-link\(majorClass)'><span class='pkg-name'>\(metalIcon)\(name)</span>\(bsLabel)</a>")
                }
                let totalWithApp = localNames.count + (hasApp ? 1 : 0)
                content += "<div class='import-group'><div style='color:var(--text3);font-size:12px;margin-bottom:8px'>🏠 \(totalWithApp) packages</div><div class='pkg-grid'>\(tags.joined(separator: "\n"))</div></div>"
            }
            if !detectedPrivateFrameworks.isEmpty {
                let tags = detectedPrivateFrameworks.sorted().map { "<span class='tag tag-private'>\($0)</span>" }.joined(separator: " ")
                content += "<div style='margin-top:12px'><p class='private-warn'>🔒 Possible Private Frameworks (\(detectedPrivateFrameworks.count)) — may cause App Store rejection:</p><div class='tag-cloud'>\(tags)</div></div>"
            }
            if !monkeyPatchedLibs.isEmpty {
                let tags = monkeyPatchedLibs.map { lib in "<span class='tag tag-external'>\(esc(lib.name)) <span style='font-size:10px;color:var(--text3)'>\(lib.fileCount) files</span></span>" }.joined(separator: " ")
                content += "<div style='margin-top:12px'><p class='private-warn' style='color:var(--text3)'>🐒 Vendored C/C++ Libraries (\(monkeyPatchedLibs.count)) — excluded from stats:</p><div class='tag-cloud'>\(tags)</div></div>"
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
        let archLinkDist = archNodeCount > 100 ? 220 : 120
        let archChargeStr = archNodeCount > 100 ? -600 : -300

        // Architecture card
        let architectureCardHTML: String = {
            var h = "<h2>🏛️ Architecture</h2>"
            if !layersHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>📐 Layers</h3>\(layersHTML)</div>"
            }
            if !componentsHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🧩 Components <span class='count'>(\(detectedComponents.count))</span></h3>\(componentsHTML)</div>"
            }
            if !appleFrameworksHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🍎 Apple Frameworks <span class='count'>(\(appleFrameworksCount))</span></h3><div class='tag-cloud'>\(appleFrameworksHTML)</div></div>"
            }
            if !externalLibsHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>📦 External Libraries <span class='count'>(\(externalLibsCount))</span></h3><div class='tag-cloud'>\(externalLibsHTML)</div></div>"
            }
            if showArchGraph {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🗺️ Architecture Graph <span class='count'>(\(archRawConnections) connections)</span></h3><div id='arch-graph' class='arch-graph-container'></div></div>"
            }
            if !localPackagesSubCardHTML.isEmpty {
                h += "<div class='sub-card'><h3 class='sub-card-title'>🏠 Local Packages</h3>\(localPackagesSubCardHTML)</div>"
            }
            return h
        }()

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
        var graphCounter = 0
        var packageGraphScripts = ""

        if skipModules {
            print("   Skipping Packages & Modules (--skip-modules)")
        } else {
        print("   Building \(packages.count) package sections...")

        for (pkgIdx, pkg) in packages.enumerated() {
            if (pkgIdx + 1) % 20 == 0 {
                print("   Package \(pkgIdx + 1)/\(packages.count)...")
            }

            let allSorted = pkg.files.sorted { $0.lineCount > $1.lineCount }
            let hasDecl: (ParsedFile) -> Bool = { !$0.declarations.filter { $0.kind != .extension && !Declaration.invalidNames.contains($0.name) }.isEmpty }
            let swiftFiles = allSorted.filter { $0.filePath.hasSuffix(".swift") && $0.lineCount >= 20 && hasDecl($0) }
            let objcFiles = allSorted.filter { !$0.filePath.hasSuffix(".swift") && $0.lineCount >= 20 && hasDecl($0) }
            let isApp = pkg.name == appTargetName
            let icon = isApp ? "📱" : "📦"
            let bsTag: String = {
                guard !isApp else { return "" }
                let bs = pkg.files.first(where: { $0.buildSystem != .unknown })?.buildSystem
                guard let bs = bs else { return "" }
                return " <span class='bs-badge'>\(bs.rawValue)</span>"
            }()

            func makeFileRows(_ files: [ParsedFile]) -> String {
                files.map { file -> String in
                    let decls = file.declarations.filter { $0.kind != .extension && !Declaration.invalidNames.contains($0.name) }
                    let exts = file.declarations.filter { $0.kind == .extension && !Declaration.invalidNames.contains($0.name) }
                    var parts: [String] = decls.map { "\(kindIcon($0.kind))&thinsp;\(esc($0.name))" }
                    parts += exts.map { "🔹&thinsp;\(esc($0.name))" }
                    let declStr = parts.isEmpty ? "—" : parts.joined(separator: "&ensp;")
                    let desc = file.description.isEmpty ? "" : "<div class='file-desc'>💡 \(esc(String(file.description.prefix(120))))</div>"
                    // Show parent folder in light gray
                    let pathComps = file.filePath.components(separatedBy: "/")
                    let folderIdx = max(0, pathComps.count - 2)
                    let folder = pathComps.count >= 2 ? pathComps[folderIdx] + "/" : ""
                    let folderHtml = folder.isEmpty ? "" : "<span style='color:var(--text3);font-weight:400'>\(esc(folder))</span>"
                    let fileLink = vsLink(path: file.filePath, label: "<strong>\(esc(file.fileName))</strong>")
                    return "<tr><td>\(folderHtml)\(fileLink)\(desc)</td><td class='mono'>\(file.lineCount)</td><td>\(decls.count)</td><td class='decl-tags'>\(declStr)</td></tr>"
                }.joined(separator: "\n")
            }

            let swiftRows = makeFileRows(swiftFiles)
            let objcRows = makeFileRows(objcFiles)
            let fileRows: String
            if !objcFiles.isEmpty && !swiftFiles.isEmpty {
                fileRows = swiftRows + "\n<tr><td colspan='4' style='background:var(--bg2);padding:4px 10px;font-size:11px;color:var(--text3);font-weight:600;text-transform:uppercase;letter-spacing:0.05em'>Objective-C</td></tr>\n" + objcRows
            } else {
                fileRows = swiftRows + objcRows
            }

            // Declaration graph
            let graphId = "pkg-graph-\(graphCounter)"
            graphCounter += 1
            let declGraphData = buildDeclarationGraph(for: pkg, pageRankScores: graph.pageRankScores)
            let pkgGraphJSON = (try? String(data: JSONEncoder().encode(declGraphData), encoding: .utf8)) ?? "{\"nodes\":[],\"links\":[]}"
            let showGraph = declGraphData.nodes.count >= 2

            var statsParts: [String] = []
            if pkg.structCount > 0 { statsParts.append("🟢 \(pkg.structCount) structs") }
            if pkg.classCount > 0 { statsParts.append("🔵 \(pkg.classCount) classes") }
            if pkg.enumCount > 0 { statsParts.append("🟡 \(pkg.enumCount) enums") }
            if pkg.protocolCount > 0 { statsParts.append("🟣 \(pkg.protocolCount) protocols") }
            if pkg.actorCount > 0 { statsParts.append("🔴 \(pkg.actorCount) actors") }
            if pkg.extensionCount > 0 { statsParts.append("🔹 \(pkg.extensionCount) extensions") }

            let pkgAnchor = pkg.name.replacingOccurrences(of: " ", with: "-")

            packageSections += """
            <div class="package-section" id="pkg-\(pkgAnchor)">
                <h3>\(icon) \(esc(pkg.name))\(bsTag)
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
                packageGraphScripts += """
                {
                    const d = \(pkgGraphJSON);
                    const el = document.getElementById('\(graphId)');
                    if (d.nodes.length > 0 && el) {
                        const kc = {'class':'#007aff','struct':'#34c759','enum':'#ff9500','actor':'#ff3b30'};
                        const g = ForceGraph()(el)
                            .graphData(d)
                            .nodeLabel(n => n.label + ' (' + n.sublabel + ')\\n' + n.kind)
                            .nodeVal(n => Math.max(n.score * 3000, 5))
                            .nodeColor(n => kc[n.kind] || '#999')
                            .nodeCanvasObject((node, ctx, gs) => {
                                const r = Math.max(Math.sqrt(Math.max(node.score * 3000, 5)) * 0.8, 3);
                                ctx.beginPath();
                                ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
                                ctx.fillStyle = kc[node.kind] || '#999';
                                ctx.fill();
                                if (gs > 0.5) {
                                    ctx.font = `${Math.max(10/gs, 3)}px -apple-system, sans-serif`;
                                    ctx.textAlign = 'center';
                                    ctx.fillStyle = '#333';
                                    ctx.fillText(node.label, node.x, node.y + r + 10/gs);
                                }
                            })
                            .linkDirectionalArrowLength(8)
                            .linkDirectionalArrowRelPos(1)
                            .linkColor(() => 'rgba(0,0,0,0.12)')
                            .width(el.offsetWidth)
                            .height(420);
                        g.d3Force('charge').strength(-250);
                        g.d3Force('link').distance(80);
                    }
                }

                """
            }
        }

        // Arch-level graph script (appended after per-package scripts)
        if showArchGraph {
            packageGraphScripts += """
            {
                const d = \(archGraphJSON);
                const el = document.getElementById('arch-graph');
                if (d.nodes.length > 0 && el) {
                    const g = ForceGraph()(el)
                        .graphData(d)
                        .nodeLabel(n => n.label + ' (' + n.val + ' files)')
                        .nodeVal(n => Math.max(n.val * 2, 4))
                        .nodeColor(() => '#007aff')
                        .nodeCanvasObject((node, ctx, gs) => {
                            const r = Math.max(Math.sqrt(Math.max(node.val * 2, 4)) * 1.2, 4);
                            ctx.beginPath();
                            ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
                            ctx.fillStyle = '#007aff';
                            ctx.fill();
                            if (gs > 0.4) {
                                ctx.font = `${Math.max(11/gs, 3)}px -apple-system, sans-serif`;
                                ctx.textAlign = 'center';
                                ctx.fillStyle = '#333';
                                ctx.fillText(node.label, node.x, node.y + r + 12/gs);
                            }
                        })
                        .linkDirectionalArrowLength(0)
                        .linkColor(() => 'rgba(0,0,0,0.2)')
                        .width(el.offsetWidth)
                        .height(500);
                    g.d3Force('charge').strength(\(archChargeStr));
                    g.d3Force('link').distance(\(archLinkDist));
                }
            }

            """
        }
        } // end if !skipModules

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

        print("   Writing HTML...")

        // ─── HTML ───
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📊</text></svg>">
            <title>🔬 ArchSwiftScope — \(esc(projectName))</title>
            <style>
                :root { --bg: #f5f5f7; --card: #fff; --border: #e5e5ea; --text: #1d1d1f; --text2: #424245; --text3: #86868b; --accent: #0071e3; --red: #ff3b30; }
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
                .pkg-graph-container { width: 100%; height: 420px; border: 1px solid var(--border); border-radius: 10px; margin-bottom: 16px; overflow: hidden; background: #fafafa; }
                .arch-graph-container { width: 100%; height: 500px; border-radius: 8px; overflow: hidden; background: #fafafa; }
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
            <div class="card">
                <h1>🔬 ArchSwiftScope 📋 \(esc(projectName.isEmpty ? "Project" : projectName))</h1>
                <p class="subtitle">Generated \(Date().formatted()) · <span class="branch-badge">\(esc(branchName))</span> branch</p>
                <div class="summary-grid">
                    \(!metadata.swiftVersion.isEmpty ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:20px\">Swift \(esc(metadata.swiftVersion))</div><div class=\"label\">Language</div></div>" : "")
                    \(!metadata.deploymentTargets.isEmpty ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:16px\">\(esc(metadata.deploymentTargets.joined(separator: ", ")))</div><div class=\"label\">Min Deployment</div></div>" : "")
                    \(!metadata.appVersion.isEmpty ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:20px\">\(esc(metadata.appVersion))</div><div class=\"label\">App Version</div></div>" : "")
                    \(metadata.assets.totalSizeBytes > 0 ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:18px\">\(metadata.assets.allFiles.count) <span style=\"font-size:14px;font-weight:400;color:var(--text3)\">(\(String(format: "%.1f", Double(metadata.assets.totalSizeBytes) / 1_048_576.0)) MB)</span></div><div class=\"label\">Assets</div></div>" : "")
                    \({
                        let swiftCount = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.count
                        let objcCount = projectFiles.count - swiftCount
                        if objcCount > 0 {
                            let swiftLines = projectFiles.filter { $0.filePath.hasSuffix(".swift") }.reduce(0) { $0 + $1.lineCount }
                            let pct = totalLines > 0 ? Int(round(Double(swiftLines) / Double(totalLines) * 100)) : 0
                            return """
                            <div class="summary-card"><div class="num">\(swiftCount)</div><div class="label">Swift Files</div></div>
                            <div class="summary-card"><div class="num">\(objcCount)</div><div class="label">ObjC Files</div></div>
                            <div class="summary-card"><div class="num" style="font-size:20px">\(pct)%</div><div class="label">Swift Code</div></div>
                            """
                        } else {
                            return "<div class=\"summary-card\"><div class=\"num\">\(swiftCount)</div><div class=\"label\">Swift Files</div></div>"
                        }
                    }())
                    <div class="summary-card"><div class="num">\(totalLines.formatted())</div><div class="label">Lines of Code</div></div>
                    <div class="summary-card"><div class="num">\(totalDecls)</div><div class="label">Declarations</div></div>
                    <div class="summary-card"><div class="num">\(totalExts)</div><div class="label">Extensions</div></div>
                    <div class="summary-card"><div class="num">\(packages.count)</div><div class="label">Packages</div></div>
                    \(!monkeyPatchedLibs.isEmpty ? "<div class=\"summary-card\"><div class=\"num\">\(monkeyPatchedLibs.count)</div><div class=\"label\">🐒 Vendored Libs</div></div>" : "")
                    <div class="summary-card"><div class="num">\(totalStructs)</div><div class="label">🟢 Structs</div></div>
                    <div class="summary-card"><div class="num">\(totalClasses)</div><div class="label">🔵 Classes</div></div>
                    <div class="summary-card"><div class="num">\(totalEnums)</div><div class="label">🟡 Enums</div></div>
                    <div class="summary-card"><div class="num">\(totalProtocols)</div><div class="label">🟣 Protocols</div></div>
                    <div class="summary-card"><div class="num">\(totalActors)</div><div class="label">🔴 Actors</div></div>
                    \(metadata.metalFiles.count > 0 ? "<div class=\"summary-card\"><div class=\"num\">\(metadata.metalFiles.count)</div><div class=\"label\">🔘 Metal</div></div>" : "")
                </div>
            </div>
            <div class="card">
                \(architectureCardHTML)
            </div>
            <div class="card">
                \(oopCardHTML)
            </div>
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
                <div class="sub-card">
                    <h3 class="sub-card-title">🔥 Code Churn</h3>
                    \(churnSubCard)
                </div>
                <div class="sub-card">
                    <h3 class="sub-card-title">📐 Semantic Standards</h3>
                    \(semanticSubCard)
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
            \(skipModules ? "" : """
            <div class="card">
                <h2>📦 Packages & Modules</h2>
                <p class="subtitle">Showing files with ≥ 20 lines and at least one declaration. Graphs: type references between declarations. <span style="color:#007aff">●</span> class <span style="color:#34c759">●</span> struct <span style="color:#ff9500">●</span> enum <span style="color:#ff3b30">●</span> actor. Arrows from class/actor only.</p>
                \(packageSections)
            </div>
            """)
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
        \(packageGraphScripts)
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
        var links: [GraphLink] = []
        var seenEdges: Set<String> = []

        // Read file contents for source declarations only
        let outgoingDecls = allDecls.filter { outgoingKinds.contains($0.kind) }
        let uniqueFilePaths = Set(outgoingDecls.map(\.filePath))
        var contentCache: [String: String] = [:]
        for path in uniqueFilePaths {
            contentCache[path] = try? String(contentsOfFile: path, encoding: .utf8)
        }

        for source in outgoingDecls {
            guard let content = contentCache[source.filePath] else { continue }
            for target in allDecls where target.name != source.name {
                let ek = "\(source.name)->\(target.name)"
                guard !seenEdges.contains(ek) else { continue }
                if fastContainsType(content, typeName: target.name) {
                    links.append(GraphLink(source: "\(source.filePath)::\(source.name)", target: "\(target.filePath)::\(target.name)"))
                    seenEdges.insert(ek)
                }
            }
        }

        let connectedIds: Set<String> = Set(links.flatMap { [$0.source, $0.target] })
        let connectedNodes = nodes.filter { connectedIds.contains($0.id) }
        return GraphData(nodes: connectedNodes, links: links)
    }

    private func fastContainsType(_ content: String, typeName: String) -> Bool {
        guard content.contains(typeName) else { return false }
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: typeName, range: searchRange) {
            let before = range.lowerBound > content.startIndex ? content[content.index(before: range.lowerBound)] : Character(" ")
            let after = range.upperBound < content.endIndex ? content[range.upperBound] : Character(" ")
            if !before.isWordChar && !after.isWordChar { return true }
            searchRange = range.upperBound..<content.endIndex
        }
        return false
    }

    private func kindIcon(_ kind: Declaration.Kind) -> String {
        switch kind { case .class: return "🔵"; case .struct: return "🟢"; case .enum: return "🟡"; case .protocol: return "🟣"; case .actor: return "🔴"; case .extension: return "🔹" }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func vsLink(path: String, label: String, line: Int? = nil) -> String {
        let href = line.map { "vscode://file/\(path):\($0)" } ?? "vscode://file/\(path)"
        return "<a href=\"\(href)\" class=\"vs-link\" title=\"Open in VS Code\">\(label)</a>"
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
            let count = r.violations.count
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
                return count >= SecurityAnalyzer.maxViolations
                    ? "\(count) (first \(SecurityAnalyzer.maxViolations))"
                    : "\(count)"
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
        let protoHeader    = noProto ? "Protocol Design · 55% weight  (M1 only — no protocols defined)" : "Protocol Design · 55% weight"

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
            sectionHeader("Value Semantics · 30% weight"),
            row(8,  "Struct vs Class ratio",
                "\(s.totalStructs) structs · \(s.totalClasses) classes",  s.s_structRatio),
            row(9,  "<code>final</code> keyword",
                "\(s.finalClasses) / \(s.totalClasses) classes",          s.s_final),
            row(10, "Enums with associated values",
                "\(s.enumsWithAssocValues) / \(s.totalEnums) enums",      s.s_enumAssoc),
            infoRow("↳ Extension count (informational)",
                    "\(s.extensionCount) extensions"),

            sectionHeader("Anti-inheritance · 15% weight"),
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

    // MARK: - Architecture Helpers

    private func classifyLayer(_ filePath: String) -> String {
        let path = filePath.lowercased()
        let name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent.lowercased()
        if path.contains("/test") || name.hasSuffix("test") || name.hasSuffix("tests") || name.hasSuffix("spec") || name.hasSuffix("mock") || name.hasSuffix("stub") || name.hasSuffix("fake") { return "Tests" }
        if path.contains("/api/") || path.contains("/network") || path.contains("/service/") || path.contains("/services/") || path.contains("/endpoint") || name.hasSuffix("api") || name.hasSuffix("service") || name.hasSuffix("client") || name.hasSuffix("endpoint") || name.hasSuffix("request") || name.hasSuffix("response") { return "API / Networking" }
        if path.contains("/model/") || path.contains("/models/") || path.contains("/entity/") || path.contains("/entities/") || path.contains("/domain/") || name.hasSuffix("model") || name.hasSuffix("entity") || name.hasSuffix("dto") { return "Models" }
        if path.contains("/viewmodel") || path.contains("/presenter") || path.contains("/interactor") || name.hasSuffix("viewmodel") || name.hasSuffix("presenter") || name.hasSuffix("interactor") || name.hasSuffix("coordinator") { return "UI / Views" }
        if path.contains("/view/") || path.contains("/views/") || path.contains("/ui/") || path.contains("/scene/") || path.contains("/scenes/") || name.hasSuffix("view") || name.hasSuffix("screen") || name.hasSuffix("cell") || name.hasSuffix("controller") || name.hasSuffix("viewcontroller") { return "UI / Views" }
        if path.contains("/storage") || path.contains("/persistence") || path.contains("/database") || path.contains("/repository") || name.hasSuffix("repository") || name.hasSuffix("store") || name.hasSuffix("storage") || name.hasSuffix("cache") || name.hasSuffix("dao") { return "Persistence" }
        if path.contains("/auth") || name.hasSuffix("auth") || name.hasSuffix("authenticator") || name.hasSuffix("authorization") { return "Auth" }
        if path.contains("/util") || path.contains("/helper") || path.contains("/extension") || name.hasSuffix("util") || name.hasSuffix("helper") || name.hasSuffix("extension") || name.hasSuffix("extensions") || name.hasSuffix("utils") || name.hasSuffix("helpers") { return "Utilities" }
        if path.contains("/config") || path.contains("/setting") || name.hasSuffix("config") || name.hasSuffix("configuration") || name.hasSuffix("settings") || name.hasSuffix("constants") || name.hasSuffix("constant") { return "Config" }
        return "Core"
    }

    private func detectComponents(appleFrameworks: Set<String>) -> [(name: String, detail: String, icon: String, frameworks: Set<String>)] {
        let checks: [(frameworks: Set<String>, name: String, detail: String, icon: String)] = [
            (["SwiftUI"], "SwiftUI", "Declarative UI", "🎨"),
            (["UIKit"], "UIKit", "Imperative UI", "📱"),
            (["AppKit"], "AppKit", "macOS UI", "🖥️"),
            (["Combine"], "Combine", "Reactive Streams", "🔄"),
            (["CoreData"], "CoreData", "Object Graph Persistence", "🗄️"),
            (["SwiftData"], "SwiftData", "Swift-native Persistence", "💾"),
            (["ARKit", "RealityKit"], "AR / Reality", "Augmented Reality", "🥽"),
            (["CoreML", "CreateML"], "CoreML", "Machine Learning", "🧠"),
            (["MapKit"], "MapKit", "Maps & Location", "🗺️"),
            (["AVFoundation", "AVKit"], "AVFoundation", "Audio / Video", "🎬"),
            (["CoreBluetooth"], "Bluetooth", "BLE Communication", "📡"),
            (["HealthKit"], "HealthKit", "Health Data", "❤️"),
            (["AuthenticationServices", "LocalAuthentication"], "Auth Services", "Authentication", "🔐"),
            (["StoreKit"], "StoreKit", "In-App Purchases", "💳"),
            (["CloudKit"], "CloudKit", "iCloud Sync", "☁️"),
            (["CryptoKit"], "CryptoKit", "Cryptography", "🔑"),
            (["Vision"], "Vision", "Computer Vision", "👁️"),
            (["NaturalLanguage"], "NaturalLanguage", "Text Analysis", "📝"),
            (["Metal", "MetalKit"], "Metal", "GPU Computing", "🔘"),
            (["GameKit", "SpriteKit", "GameplayKit"], "Game", "Game Services", "🎮"),
            (["CoreLocation", "CoreLocationUI"], "Location", "Location Services", "📍"),
            (["UserNotifications", "PushKit"], "Notifications", "Push & Local", "🔔"),
            (["WebKit"], "WebKit", "Web Rendering", "🌐"),
            (["Network", "NetworkExtension"], "Network", "Low-level Networking", "🔗"),
            (["CoreMotion", "SensorKit"], "Motion / Sensors", "Device Sensors", "📐"),
            (["Photos", "PhotosUI"], "Photos", "Photo Library", "🖼️"),
            (["Contacts", "ContactsUI"], "Contacts", "Address Book", "👤"),
            (["EventKit"], "EventKit", "Calendar & Reminders", "📅"),
            (["CoreHaptics"], "Haptics", "Haptic Feedback", "📳"),
            (["SceneKit"], "SceneKit", "3D Scenes", "🧊"),
            (["AppIntents"], "App Intents", "Siri & Shortcuts", "🎙️"),
            (["WidgetKit"], "WidgetKit", "Home Screen Widgets", "🔲"),
            (["SwiftTesting", "XCTest"], "Testing", "Unit & UI Tests", "🧪"),
            (["Observation"], "Observation", "Swift Observation", "👀"),
        ]
        return checks.compactMap { check in
            let matched = check.frameworks.intersection(appleFrameworks)
            return matched.isEmpty ? nil : (name: check.name, detail: check.detail, icon: check.icon, frameworks: matched)
        }
    }
}

private extension Character {
    var isWordChar: Bool { isLetter || isNumber || self == "_" }
}
