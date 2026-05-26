// Exey Panteleev
import Foundation

// MARK: - Letter Health

enum LetterHealth {
    case present  // well-populated layer
    case weak     // some evidence but sparse
    case missing  // no evidence found
}

// MARK: - Role Stats

struct RoleStats {
    let fileCount: Int
    let lineCount: Int
    let declCount: Int
    let topPaths:  [String]  // up to 3 paths, sorted by LOC desc

    static let empty = RoleStats(fileCount: 0, lineCount: 0, declCount: 0, topPaths: [])

    var health: LetterHealth {
        if fileCount == 0 && declCount == 0 { return .missing }
        if fileCount <= 1 && lineCount < 150 && declCount <= 1 { return .weak }
        return .present
    }
}

// MARK: - Architecture Letter

struct ArchLetter {
    let letter:       String
    let fullName:     String
    let fileCount:    Int
    let lineCount:    Int
    let declCount:    Int
    let health:       LetterHealth
    let detail:       String
    let examplePaths: [String]

    init(_ letter: String, _ fullName: String, _ stats: RoleStats, detail: String) {
        self.letter       = letter
        self.fullName     = fullName
        self.fileCount    = stats.fileCount
        self.lineCount    = stats.lineCount
        self.declCount    = stats.declCount
        self.health       = stats.health
        self.detail       = detail
        self.examplePaths = stats.topPaths
    }
}

// MARK: - Pattern / Result

struct ArchDetectedPattern {
    let name:       String
    let confidence: Double
    let letters:    [ArchLetter]
    let hint:       String?    // shown when all letter counts are zero
    init(name: String, confidence: Double, letters: [ArchLetter], hint: String? = nil) {
        self.name = name; self.confidence = confidence; self.letters = letters; self.hint = hint
    }
}

struct ArchDetectionResult {
    let patterns: [ArchDetectedPattern]
    let commandLetter: ArchLetter?           // Cmd (Command) — orthogonal to arch pattern
    let eventBusLetter: ArchLetter?          // E (Event Bus) — orthogonal to arch pattern
    var top: ArchDetectedPattern? { patterns.first }
    // FIX #6: aligned to the same 0.15 threshold used at collection time
    var hasDetection: Bool { patterns.first.map { $0.confidence >= 0.15 } ?? false }
}

// MARK: - Detected Component

struct DetectedComponent {
    let name:       String
    let detail:     String
    let icon:       String
    let frameworks: Set<String>
}

// MARK: - Architecture Analyzer

struct ArchAnalyzer {

    // MARK: - Layer Classification

    func classifyLayer(_ filePath: String) -> String {
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

    // MARK: - Apple Framework Component Detection

    func detectComponents(appleFrameworks: Set<String>) -> [DetectedComponent] {
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
            return matched.isEmpty ? nil : DetectedComponent(
                name: check.name, detail: check.detail,
                icon: check.icon, frameworks: matched)
        }
    }

    // MARK: - Architecture Pattern Detection

    func detectPattern(files: [ParsedFile]) -> ArchDetectionResult {
        let rc = RoleCounter(files: files)
        let allImports = Set(files.flatMap(\.imports))
        var patterns: [ArchDetectedPattern] = []

        let tcaConf = scoreTCA(rc: rc, imports: allImports)
        if tcaConf >= 0.15 { patterns.append(buildTCA(rc: rc, confidence: tcaConf, imports: allImports)) }

        let vipConf = scoreVIP(rc: rc)
        if vipConf >= 0.15 { patterns.append(buildVIP(rc: rc, confidence: vipConf)) }

        let viperConf = scoreVIPER(rc: rc)
        if viperConf >= 0.15 { patterns.append(buildVIPER(rc: rc, confidence: viperConf)) }

        let ribsConf = scoreRIBs(rc: rc)
        if ribsConf >= 0.15 { patterns.append(buildRIBs(rc: rc, confidence: ribsConf)) }

        let cleanConf = scoreClean(rc: rc)
        if cleanConf >= 0.15 { patterns.append(buildClean(rc: rc, confidence: cleanConf)) }

        let reduxConf = scoreRedux(rc: rc, imports: allImports)
        if reduxConf >= 0.15 { patterns.append(buildRedux(rc: rc, confidence: reduxConf, imports: allImports)) }

        let mvvmcConf = scoreMVVMC(rc: rc)
        if mvvmcConf >= 0.15 { patterns.append(buildMVVMC(rc: rc, confidence: mvvmcConf)) }

        let mvvmsConf = scoreMVVMS(rc: rc)
        if mvvmsConf >= 0.15 { patterns.append(buildMVVMS(rc: rc, confidence: mvvmsConf)) }

        let mvvmConf = scoreMVVM(rc: rc)
        if mvvmConf >= 0.15 { patterns.append(buildMVVM(rc: rc, confidence: mvvmConf)) }

        let mvpConf = scoreMVP(rc: rc)
        if mvpConf >= 0.15 { patterns.append(buildMVP(rc: rc, confidence: mvpConf)) }

        let mvcConf = scoreMVC(rc: rc, imports: allImports)
        if mvcConf >= 0.15 { patterns.append(buildMVC(rc: rc, confidence: mvcConf, imports: allImports)) }

        let mvConf = scoreMV(rc: rc, imports: allImports)
        if mvConf >= 0.15 { patterns.append(buildMV(rc: rc, confidence: mvConf, imports: allImports)) }

        patterns.sort { $0.confidence > $1.confidence }

        // Cmd (Command) — orthogonal letter, shown in Architecture sub-card
        let topConf = patterns.first?.confidence ?? 0.0
        let cmdLetter = ArchLetter("Cmd", "Command", rc.command,
                                   detail: rc.command.fileCount > 0
                                       ? "\(rc.command.fileCount) command file\(rc.command.fileCount == 1 ? "" : "s")"
                                       : "no command files")
        let commandLetter: ArchLetter? = {
            switch cmdLetter.health {
            case .missing: return nil
            case .weak:    return topConf >= 0.5 ? nil : cmdLetter
            case .present: return cmdLetter
            }
        }()

        // E (Event Bus) — orthogonal letter: NotificationCenter, Combine subjects, EmitterKit, etc.
        let eventBusLibs: Set<String> = ["EmitterKit", "Signals"]
        let matchedEventLibs = allImports.intersection(eventBusLibs)
        let hasCombineEventBus = allImports.contains("Combine") && rc.eventBus.fileCount > 0
        let hasNotificationBus = rc.notificationNameExts >= 3
        let hasEventBusFiles = rc.eventBus.fileCount > 0

        let eventBusLetter: ArchLetter? = {
            guard !matchedEventLibs.isEmpty || hasCombineEventBus || hasNotificationBus || hasEventBusFiles else { return nil }
            var parts: [String] = []
            if !matchedEventLibs.isEmpty { parts.append(matchedEventLibs.sorted().joined(separator: ", ")) }
            if hasCombineEventBus { parts.append("Combine") }
            if hasNotificationBus { parts.append("NotificationCenter") }
            if rc.eventBus.fileCount > 0 { parts.append("\(rc.eventBus.fileCount) file\(rc.eventBus.fileCount == 1 ? "" : "s")") }
            let detail = parts.joined(separator: " · ")
            let baseStats: RoleStats = rc.eventBus.fileCount > 0
                ? rc.eventBus
                : RoleStats(fileCount: 0, lineCount: 0, declCount: hasNotificationBus ? rc.notificationNameExts : 1, topPaths: [])
            return ArchLetter("E", "Event Bus", baseStats, detail: detail)
        }()

        return ArchDetectionResult(patterns: Array(patterns.prefix(5)), commandLetter: commandLetter, eventBusLetter: eventBusLetter)
    }

    // MARK: - Role Counter

    struct RoleCounter {
        let model:          RoleStats
        let view:           RoleStats
        let viewController: RoleStats
        let viewModel:      RoleStats
        let presenter:      RoleStats
        let interactor:     RoleStats
        let router:         RoleStats
        let coordinator:    RoleStats
        let entity:         RoleStats
        let builder:        RoleStats
        let feature:        RoleStats
        let reducer:        RoleStats
        let service:        RoleStats
        let useCase:        RoleStats
        let repository:     RoleStats
        let command:        RoleStats
        let eventBus:       RoleStats
        let notificationNameExts: Int

        let businessLogicProtos:     Int
        let presentationLogicProtos: Int
        let displayLogicProtos:      Int
        let routingLogicProtos:      Int

        let storeDecls:  Int
        let stateDecls:  Int
        let actionDecls: Int

        init(files: [ParsedFile]) {
            func stats(
                _ pred: (ParsedFile) -> Bool,
                decl: ((String) -> Bool)? = nil
            ) -> RoleStats {
                let matching = files.filter(pred)
                let dc = decl.map { fn in
                    files.flatMap(\.declarations)
                        .filter { $0.kind != .extension && fn($0.name) }.count
                } ?? 0
                let sorted = matching.sorted { $0.lineCount > $1.lineCount }
                return RoleStats(
                    fileCount: matching.count,
                    lineCount: matching.reduce(0) { $0 + $1.lineCount },
                    declCount: dc,
                    topPaths:  Array(sorted.prefix(3).map(\.filePath))
                )
            }
            func countDecls(_ pred: (String) -> Bool) -> Int {
                files.flatMap(\.declarations)
                    .filter { $0.kind != .extension && pred($0.name) }.count
            }

            // FIX #3: entity excluded — has its own dedicated role
            model = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("model") || n.hasSuffix("dto") ||
                       p.contains("/model/") || p.contains("/models/")
            }, decl: { $0.lowercased().hasSuffix("model") })

            // FIX #1: each clause fully parenthesised to prevent &&/|| precedence bugs
            view = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                let nameMatch = (n.hasSuffix("view") || n.hasSuffix("screen") ||
                                 n.hasSuffix("cell") || n.hasSuffix("component"))
                                && !n.hasSuffix("viewcontroller") && !n.hasSuffix("viewmodel")
                let pathMatch = (p.contains("/views/") || p.contains("/view/"))
                                && !p.contains("viewmodel") && !p.contains("viewcontroller")
                return nameMatch || pathMatch
            })

            viewController = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                return n.hasSuffix("viewcontroller") || n.hasSuffix("controller") ||
                    $0.declarations.contains {
                        $0.kind == .class && $0.name.lowercased().hasSuffix("viewcontroller")
                    }
            })

            viewModel = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("viewmodel") || p.contains("/viewmodels/")
            }, decl: { $0.lowercased().hasSuffix("viewmodel") })

            presenter = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("presenter") || p.contains("/presenters/")
            }, decl: { $0.lowercased().hasSuffix("presenter") })

            interactor = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("interactor") || p.contains("/interactors/")
            }, decl: { $0.lowercased().hasSuffix("interactor") })

            router = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("router") || n.hasSuffix("wireframe") || p.contains("/routers/")
            }, decl: { let l = $0.lowercased(); return l.hasSuffix("router") || l.hasSuffix("wireframe") })

            coordinator = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("coordinator") || p.contains("/coordinators/")
            }, decl: { $0.lowercased().hasSuffix("coordinator") })

            entity = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("entity") || p.contains("/entities/")
            }, decl: { $0.lowercased().hasSuffix("entity") })

            builder = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("builder") || p.contains("/builders/")
            }, decl: { $0.lowercased().hasSuffix("builder") })

            // FIX #5: use fileNameWithoutExtension so "Feature.swift" matches correctly
            feature = stats({
                $0.fileNameWithoutExtension.lowercased().hasSuffix("feature")
            }, decl: { $0.lowercased().hasSuffix("feature") })

            reducer = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("reducer") || p.contains("/reducers/")
            }, decl: { $0.lowercased().hasSuffix("reducer") })

            // FIX #4: service layer separated from useCases (no longer dead code — used in Clean/MVVM+S)
            service = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("service") || p.contains("/services/")
            })

            useCase = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("usecase") || p.contains("/usecases/") || p.contains("/use-cases/")
            })

            repository = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("repository") || p.contains("/repositories/") || p.contains("/repository/")
            })

            command = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                return n.hasSuffix("command") || n.contains("command") ||
                       p.contains("/commands/") || p.contains("/command/")
            }, decl: { let l = $0.lowercased()
                return l.hasSuffix("command") || l.contains("command")
            })

            eventBus = stats({
                let n = $0.fileNameWithoutExtension.lowercased()
                let p = $0.filePath.lowercased()
                let imp = Set($0.imports)
                let nameMatch = n.contains("eventbus") || n.hasSuffix("events") ||
                                n.hasSuffix("event") ||
                                (n.contains("notification") && !n.hasSuffix("viewcontroller") && !n.hasSuffix("controller"))
                let pathMatch = p.contains("/events/") || p.contains("/event/")
                let importMatch = imp.contains("EmitterKit") || imp.contains("Signals")
                return nameMatch || pathMatch || importMatch
            }, decl: { let l = $0.lowercased()
                return l.hasSuffix("eventbus") || l.hasSuffix("eventemitter") ||
                       l.contains("eventbus") || l.hasSuffix("eventcenter")
            })

            notificationNameExts = files.flatMap(\.declarations)
                .filter { $0.kind == .extension && $0.name == "Notification.Name" }.count

            let protos = files.flatMap(\.declarations).filter { $0.kind == .protocol }.map(\.name)
            businessLogicProtos     = protos.filter { $0.hasSuffix("BusinessLogic") }.count
            presentationLogicProtos = protos.filter { $0.hasSuffix("PresentationLogic") }.count
            displayLogicProtos      = protos.filter { $0.hasSuffix("DisplayLogic") }.count
            routingLogicProtos      = protos.filter { $0.hasSuffix("RoutingLogic") }.count

            storeDecls  = countDecls { $0.lowercased().hasSuffix("store") }
            stateDecls  = countDecls { let l = $0.lowercased()
                return l.hasSuffix("state") && !l.hasSuffix("uistate") &&
                       !l.hasSuffix("viewstate") && l != "state" }
            actionDecls = countDecls { let l = $0.lowercased()
                return l.hasSuffix("action") && l != "action" }
        }
    }

    // MARK: - Scoring

    private func scoreTCA(rc: RoleCounter, imports: Set<String>) -> Double {
        var s = 0.0
        if imports.contains("ComposableArchitecture") { s += 0.65 }
        if rc.feature.fileCount  >= 1 { s += rc.feature.fileCount  >= 2 ? 0.20 : 0.10 }
        if rc.feature.declCount  >= 1 { s += rc.feature.declCount  >= 2 ? 0.10 : 0.05 }
        if rc.reducer.fileCount  >= 1 { s += rc.reducer.fileCount  >= 2 ? 0.05 : 0.02 }
        if rc.reducer.declCount  >= 1 { s += rc.reducer.declCount  >= 2 ? 0.10 : 0.05 }
        if rc.stateDecls  >= 1 { s += rc.stateDecls  >= 2 ? 0.08 : 0.04 }
        if rc.actionDecls >= 1 { s += rc.actionDecls >= 2 ? 0.08 : 0.04 }
        if rc.storeDecls  >= 1 { s += 0.05 }
        return min(s, 1.0)
    }

    private func scoreVIP(rc: RoleCounter) -> Double {
        var s = 0.0
        if rc.businessLogicProtos     >= 1 { s += 0.30 }
        if rc.presentationLogicProtos >= 1 { s += 0.25 }
        if rc.displayLogicProtos      >= 1 { s += 0.20 }
        if rc.routingLogicProtos      >= 1 { s += 0.15 }
        if rc.interactor.fileCount    >= 1 { s += rc.interactor.fileCount >= 2 ? 0.05 : 0.02 }
        if rc.presenter.fileCount     >= 1 { s += rc.presenter.fileCount  >= 2 ? 0.05 : 0.02 }
        return min(s, 1.0)
    }

    private func scoreVIPER(rc: RoleCounter) -> Double {
        var hits = 0
        if rc.view.fileCount + rc.viewController.fileCount >= 1             { hits += 1 }
        if rc.interactor.fileCount >= 1 || rc.interactor.declCount >= 1    { hits += 1 }
        if rc.presenter.fileCount  >= 1 || rc.presenter.declCount  >= 1    { hits += 1 }
        if rc.entity.fileCount     >= 1 || rc.entity.declCount     >= 1    { hits += 1 }
        if rc.router.fileCount     >= 1 || rc.router.declCount     >= 1    { hits += 1 }
        guard hits >= 2 else { return 0 }
        let logicPenalty = min(
            Double(rc.businessLogicProtos + rc.presentationLogicProtos + rc.displayLogicProtos) * 0.05,
            0.3)
        return max(0, Double(hits) / 5.0 * 0.85 - logicPenalty)
    }

    private func scoreRIBs(rc: RoleCounter) -> Double {
        var s = 0.0
        let b = rc.builder.fileCount   + rc.builder.declCount
        let r = rc.router.fileCount    + rc.router.declCount
        let i = rc.interactor.fileCount + rc.interactor.declCount
        if b >= 1 { s += b >= 3 ? 0.35 : (b >= 2 ? 0.25 : 0.15) }
        if r >= 1 { s += r >= 3 ? 0.30 : (r >= 2 ? 0.22 : 0.12) }
        if i >= 1 { s += i >= 3 ? 0.25 : (i >= 2 ? 0.18 : 0.10) }
        if s > 0  { s += 0.10 }
        return min(s, 1.0)
    }

    private func scoreClean(rc: RoleCounter) -> Double {
        var hits = 0
        var s    = 0.0
        if rc.useCase.fileCount >= 1 {
            hits += 1
            s += rc.useCase.fileCount >= 3 ? 0.35 : (rc.useCase.fileCount >= 2 ? 0.25 : 0.15)
        }
        if rc.repository.fileCount >= 1 {
            hits += 1
            s += rc.repository.fileCount >= 2 ? 0.30 : 0.18
        }
        if rc.entity.fileCount + rc.entity.declCount >= 2 {
            hits += 1
            s += 0.15
        }
        if rc.service.fileCount >= 1 { s += 0.08 }
        guard hits >= 2 else { return 0 }
        return min(s, 1.0)
    }

    private func scoreRedux(rc: RoleCounter, imports: Set<String>) -> Double {
        guard !imports.contains("ComposableArchitecture") else { return 0 }
        var s = 0.0
        if imports.contains("ReSwift") || imports.contains("Redux") { s += 0.55 }
        if rc.stateDecls  >= 1 { s += rc.stateDecls  >= 2 ? 0.20 : 0.10 }
        if rc.actionDecls >= 1 { s += rc.actionDecls >= 2 ? 0.20 : 0.10 }
        if rc.reducer.fileCount + rc.reducer.declCount >= 1 {
            s += rc.reducer.fileCount >= 2 ? 0.15 : 0.08
        }
        if rc.storeDecls >= 1 { s += 0.10 }
        return min(s, 1.0)
    }

    private func scoreMVVMC(rc: RoleCounter) -> Double {
        guard rc.viewModel.fileCount + rc.viewModel.declCount >= 1 else { return 0 }
        guard rc.coordinator.fileCount + rc.coordinator.declCount >= 1 else { return 0 }
        let vmTotal = rc.viewModel.fileCount + rc.viewModel.declCount
        var s = vmTotal >= 2 ? 0.50 : 0.35
        if rc.viewModel.fileCount   >= 3 { s += 0.20 }
        if rc.coordinator.fileCount >= 2 { s += 0.15 }
        if rc.model.fileCount       >= 1 { s += 0.10 }
        return min(s, 1.0)
    }

    private func scoreMVVMS(rc: RoleCounter) -> Double {
        guard rc.viewModel.fileCount + rc.viewModel.declCount >= 1 else { return 0 }
        guard rc.service.fileCount >= 1 else { return 0 }
        // MVVM+C is more specific when coordinators are present
        guard rc.coordinator.fileCount + rc.coordinator.declCount == 0 else { return 0 }
        let vmTotal = rc.viewModel.fileCount + rc.viewModel.declCount
        var s = vmTotal >= 2 ? 0.40 : 0.25
        if rc.viewModel.fileCount >= 3 { s += 0.15 }
        if rc.service.fileCount   >= 2 { s += 0.20 }
        if rc.model.fileCount     >= 1 { s += 0.10 }
        return min(s, 1.0)
    }

    private func scoreMVVM(rc: RoleCounter) -> Double {
        guard rc.viewModel.fileCount + rc.viewModel.declCount >= 1 else { return 0 }
        let vmTotal = rc.viewModel.fileCount + rc.viewModel.declCount
        var s = vmTotal >= 2 ? 0.40 : 0.22
        if rc.viewModel.fileCount >= 3 { s += 0.20 }
        if rc.model.fileCount     >= 2 { s += 0.15 }
        if rc.view.fileCount + rc.viewController.fileCount >= 2 { s += 0.15 }
        // Penalty when more-specific variants apply
        if rc.coordinator.fileCount + rc.coordinator.declCount > 0 { s -= 0.20 }
        if rc.service.fileCount >= 2 { s -= 0.15 }
        return max(0, min(s, 1.0))
    }

    private func scoreMVP(rc: RoleCounter) -> Double {
        guard rc.presenter.fileCount + rc.presenter.declCount >= 1 else { return 0 }
        guard rc.viewModel.fileCount + rc.viewModel.declCount == 0 else { return 0 }
        let presTotal = rc.presenter.fileCount + rc.presenter.declCount
        var s = presTotal >= 2 ? 0.50 : 0.30
        if rc.presenter.fileCount >= 3 { s += 0.20 }
        if rc.view.fileCount + rc.viewController.fileCount >= 2 { s += 0.20 }
        if rc.model.fileCount >= 1 { s += 0.10 }
        return min(s, 1.0)
    }

    private func scoreMVC(rc: RoleCounter, imports: Set<String>) -> Double {
        guard rc.viewController.fileCount >= 1 else { return 0 }
        guard rc.viewModel.fileCount + rc.viewModel.declCount == 0 else { return 0 }
        guard rc.presenter.fileCount == 0 else { return 0 }
        guard !imports.contains("ComposableArchitecture") else { return 0 }
        var s = rc.viewController.fileCount >= 2 ? 0.40 : 0.25
        if imports.contains("UIKit")         { s += 0.20 }
        if rc.viewController.fileCount >= 5  { s += 0.20 }
        if rc.model.fileCount          >= 1  { s += 0.10 }
        if rc.router.fileCount         == 0  { s += 0.10 }
        return min(s, 1.0)
    }

    private func scoreMV(rc: RoleCounter, imports: Set<String>) -> Double {
        guard imports.contains("SwiftUI") else { return 0 }
        guard rc.viewModel.fileCount + rc.viewModel.declCount == 0 else { return 0 }
        guard rc.viewController.fileCount == 0 else { return 0 }
        var s = 0.5
        if rc.view.fileCount  >= 3 { s += 0.30 }
        if rc.model.fileCount >= 1 { s += 0.20 }
        return min(s, 1.0)
    }

    // MARK: - Pattern Builders

    private func buildTCA(rc: RoleCounter, confidence: Double, imports: Set<String>) -> ArchDetectedPattern {
        let stateStats  = RoleStats(fileCount: 0, lineCount: 0, declCount: rc.stateDecls,  topPaths: [])
        let actionStats = RoleStats(fileCount: 0, lineCount: 0, declCount: rc.actionDecls, topPaths: [])
        let hint: String? = imports.contains("ComposableArchitecture") ? "ComposableArchitecture import" : nil
        return ArchDetectedPattern(name: "TCA", confidence: confidence, letters: [
            ArchLetter("Feature", "Feature", rc.feature,  detail: roleDetail(rc.feature)),
            ArchLetter("State",   "State",   stateStats,  detail: rc.stateDecls  == 0 ? "—" : "\(rc.stateDecls) *State types"),
            ArchLetter("Action",  "Action",  actionStats, detail: rc.actionDecls == 0 ? "—" : "\(rc.actionDecls) *Action enums"),
            ArchLetter("Reducer", "Reducer", rc.reducer,  detail: roleDetail(rc.reducer)),
        ], hint: hint)
    }

    private func buildVIP(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        let vStats  = mergedStats(rc.view, rc.viewController)
        let iDetail = roleDetail(rc.interactor) +
            (rc.businessLogicProtos > 0 ? " · \(rc.businessLogicProtos) BusinessLogic" : "")
        let pDetail = roleDetail(rc.presenter) +
            (rc.presentationLogicProtos > 0 ? " · \(rc.presentationLogicProtos) PresentationLogic" : "")
        var hintParts: [String] = []
        if rc.businessLogicProtos     > 0 { hintParts.append("BusinessLogic \(rc.businessLogicProtos)") }
        if rc.presentationLogicProtos > 0 { hintParts.append("PresentationLogic \(rc.presentationLogicProtos)") }
        if rc.displayLogicProtos      > 0 { hintParts.append("DisplayLogic \(rc.displayLogicProtos)") }
        if rc.routingLogicProtos      > 0 { hintParts.append("RoutingLogic \(rc.routingLogicProtos)") }
        let hint: String? = hintParts.isEmpty ? nil : hintParts.joined(separator: ", ")
        return ArchDetectedPattern(name: "VIP", confidence: confidence, letters: [
            ArchLetter("V", "View",       vStats,        detail: "\(rc.viewController.fileCount) controllers · \(rc.view.fileCount) views"),
            ArchLetter("I", "Interactor", rc.interactor, detail: iDetail),
            ArchLetter("P", "Presenter",  rc.presenter,  detail: pDetail),
        ], hint: hint)
    }

    private func buildVIPER(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        let vStats = mergedStats(rc.view, rc.viewController)
        return ArchDetectedPattern(name: "VIPER", confidence: confidence, letters: [
            ArchLetter("V", "View",       vStats,        detail: "\(vStats.fileCount) files"),
            ArchLetter("I", "Interactor", rc.interactor, detail: roleDetail(rc.interactor)),
            ArchLetter("P", "Presenter",  rc.presenter,  detail: roleDetail(rc.presenter)),
            ArchLetter("E", "Entity",     rc.entity,     detail: roleDetail(rc.entity)),
            ArchLetter("R", "Router",     rc.router,     detail: roleDetail(rc.router)),
        ])
    }

    private func buildRIBs(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        return ArchDetectedPattern(name: "RIBs", confidence: confidence, letters: [
            ArchLetter("R", "Router",     rc.router,     detail: roleDetail(rc.router)),
            ArchLetter("I", "Interactor", rc.interactor, detail: roleDetail(rc.interactor)),
            ArchLetter("B", "Builder",    rc.builder,    detail: roleDetail(rc.builder)),
        ])
    }

    private func buildClean(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        return ArchDetectedPattern(name: "Clean", confidence: confidence, letters: [
            ArchLetter("E",    "Entity",     rc.entity,     detail: roleDetail(rc.entity)),
            ArchLetter("UC",   "Use Case",   rc.useCase,    detail: roleDetail(rc.useCase)),
            ArchLetter("Repo", "Repository", rc.repository, detail: roleDetail(rc.repository)),
            ArchLetter("Svc",  "Service",    rc.service,    detail: roleDetail(rc.service)),
        ])
    }

    private func buildRedux(rc: RoleCounter, confidence: Double, imports: Set<String>) -> ArchDetectedPattern {
        let stateStats  = RoleStats(fileCount: 0, lineCount: 0, declCount: rc.stateDecls,  topPaths: [])
        let actionStats = RoleStats(fileCount: 0, lineCount: 0, declCount: rc.actionDecls, topPaths: [])
        let storeStats  = RoleStats(fileCount: 0, lineCount: 0, declCount: rc.storeDecls,  topPaths: [])
        let matchedImports = ["ReSwift", "Redux"].filter { imports.contains($0) }
        let hint: String? = matchedImports.isEmpty ? nil : matchedImports.joined(separator: ", ") + " import"
        return ArchDetectedPattern(name: "Redux", confidence: confidence, letters: [
            ArchLetter("State",   "State",   stateStats,  detail: rc.stateDecls  == 0 ? "—" : "\(rc.stateDecls) types"),
            ArchLetter("Action",  "Action",  actionStats, detail: rc.actionDecls == 0 ? "—" : "\(rc.actionDecls) enums"),
            ArchLetter("Reducer", "Reducer", rc.reducer,  detail: roleDetail(rc.reducer)),
            ArchLetter("Store",   "Store",   storeStats,  detail: rc.storeDecls  == 0 ? "—" : "\(rc.storeDecls) types"),
        ], hint: hint)
    }

    private func buildMVVMC(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        let vStats = mergedStats(rc.view, rc.viewController)
        return ArchDetectedPattern(name: "MVVM+C", confidence: confidence, letters: [
            ArchLetter("M",  "Model",       rc.model,       detail: roleDetail(rc.model)),
            ArchLetter("V",  "View",        vStats,         detail: "\(vStats.fileCount) files"),
            ArchLetter("VM", "ViewModel",   rc.viewModel,   detail: roleDetail(rc.viewModel)),
            ArchLetter("C",  "Coordinator", rc.coordinator, detail: roleDetail(rc.coordinator)),
        ])
    }

    private func buildMVVMS(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        let vStats = mergedStats(rc.view, rc.viewController)
        return ArchDetectedPattern(name: "MVVM+S", confidence: confidence, letters: [
            ArchLetter("M",   "Model",     rc.model,     detail: roleDetail(rc.model)),
            ArchLetter("V",   "View",      vStats,       detail: "\(vStats.fileCount) files"),
            ArchLetter("VM",  "ViewModel", rc.viewModel, detail: roleDetail(rc.viewModel)),
            ArchLetter("Svc", "Service",   rc.service,   detail: roleDetail(rc.service)),
        ])
    }

    private func buildMVVM(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        let vStats = mergedStats(rc.view, rc.viewController)
        return ArchDetectedPattern(name: "MVVM", confidence: confidence, letters: [
            ArchLetter("M",  "Model",     rc.model,     detail: roleDetail(rc.model)),
            ArchLetter("V",  "View",      vStats,       detail: "\(vStats.fileCount) files"),
            ArchLetter("VM", "ViewModel", rc.viewModel, detail: roleDetail(rc.viewModel)),
        ])
    }

    private func buildMVP(rc: RoleCounter, confidence: Double) -> ArchDetectedPattern {
        let vStats = mergedStats(rc.view, rc.viewController)
        return ArchDetectedPattern(name: "MVP", confidence: confidence, letters: [
            ArchLetter("M", "Model",     rc.model,     detail: roleDetail(rc.model)),
            ArchLetter("V", "View",      vStats,       detail: "\(vStats.fileCount) files"),
            ArchLetter("P", "Presenter", rc.presenter, detail: roleDetail(rc.presenter)),
        ])
    }

    // FIX #2: V = viewFiles only (plain views); C = viewControllerFiles (consistent split)
    private func buildMVC(rc: RoleCounter, confidence: Double, imports: Set<String>) -> ArchDetectedPattern {
        let hint: String? = imports.contains("UIKit") ? "UIKit import" : nil
        return ArchDetectedPattern(name: "MVC", confidence: confidence, letters: [
            ArchLetter("M", "Model",      rc.model,          detail: roleDetail(rc.model)),
            ArchLetter("V", "View",       rc.view,           detail: roleDetail(rc.view)),
            ArchLetter("C", "Controller", rc.viewController, detail: roleDetail(rc.viewController)),
        ], hint: hint)
    }

    private func buildMV(rc: RoleCounter, confidence: Double, imports: Set<String>) -> ArchDetectedPattern {
        let hint: String? = imports.contains("SwiftUI") ? "SwiftUI import" : nil
        return ArchDetectedPattern(name: "MV", confidence: confidence, letters: [
            ArchLetter("M", "Model", rc.model, detail: roleDetail(rc.model)),
            ArchLetter("V", "View",  rc.view,  detail: "\(rc.view.fileCount) SwiftUI views"),
        ], hint: hint)
    }

    // MARK: - Helpers

    private func roleDetail(_ stats: RoleStats) -> String {
        guard stats.fileCount > 0 || stats.declCount > 0 else { return "—" }
        var parts: [String] = []
        if stats.fileCount > 0 { parts.append("\(stats.fileCount) file\(stats.fileCount == 1 ? "" : "s")") }
        if stats.declCount > 0 { parts.append("\(stats.declCount) type\(stats.declCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func mergedStats(_ a: RoleStats, _ b: RoleStats) -> RoleStats {
        // Interleave top paths from each list (both already sorted by LOC desc)
        var merged: [String] = []
        var ai = 0; var bi = 0
        while merged.count < 3 && (ai < a.topPaths.count || bi < b.topPaths.count) {
            if ai < a.topPaths.count { merged.append(a.topPaths[ai]); ai += 1 }
            if merged.count < 3 && bi < b.topPaths.count { merged.append(b.topPaths[bi]); bi += 1 }
        }
        return RoleStats(
            fileCount: a.fileCount + b.fileCount,
            lineCount: a.lineCount + b.lineCount,
            declCount: a.declCount + b.declCount,
            topPaths:  merged
        )
    }
}
