import Foundation

/// How one game should run. A nil field means "leave it to the default", and writes nothing.
public struct GameSettings: Sendable, Equatable {
    public var rayTracing: Bool?
    public var metalFX: Bool?
    public var frameCap: Int?
    public var performanceHUD: Bool?
    public var metal4: Bool?

    public init(rayTracing: Bool? = nil, metalFX: Bool? = nil, frameCap: Int? = nil, performanceHUD: Bool? = nil, metal4: Bool? = nil) {
        self.rayTracing = rayTracing
        self.metalFX = metalFX
        self.frameCap = frameCap
        self.performanceHUD = performanceHUD
        self.metal4 = metal4
    }

    /// What a field means when it is left alone, per Apple's Read Me for an M1/M2 Mac on macOS 27.
    public enum Default {
        public static let rayTracing = false
        public static let metalFX = false
        public static let frameCap = 0
        public static let performanceHUD = false
        public static let metal4 = true
    }

    /// Builds settings from concrete values, storing nothing for values that equal the default.
    public init(rayTracingOn: Bool, metalFXOn: Bool, frameCapValue: Int, performanceHUDOn: Bool, metal4On: Bool) {
        self.init(
            rayTracing: rayTracingOn == Default.rayTracing ? nil : rayTracingOn,
            metalFX: metalFXOn == Default.metalFX ? nil : metalFXOn,
            frameCap: frameCapValue == Default.frameCap ? nil : frameCapValue,
            performanceHUD: performanceHUDOn == Default.performanceHUD ? nil : performanceHUDOn,
            metal4: metal4On == Default.metal4 ? nil : metal4On
        )
    }

    public var rayTracingOn: Bool { rayTracing ?? Default.rayTracing }
    public var metalFXOn: Bool { metalFX ?? Default.metalFX }
    public var frameCapValue: Int { frameCap ?? Default.frameCap }
    public var performanceHUDOn: Bool { performanceHUD ?? Default.performanceHUD }
    public var metal4On: Bool { metal4 ?? Default.metal4 }

    /// The same settings with defaults spelled out as nil, so two ways of saying the same thing compare equal.
    public var normalized: GameSettings {
        GameSettings(rayTracingOn: rayTracingOn, metalFXOn: metalFXOn, frameCapValue: frameCapValue,
                     performanceHUDOn: performanceHUDOn, metal4On: metal4On)
    }

    /// Variables Tannin owns in a game's launch options. Anything else the user typed there is kept.
    static let ownedKeys = ["CX_ACTIVE_GRAPHICS_BACKEND", "D3DM_SUPPORT_DXR", "D3DM_ENABLE_METALFX", "D3DM_MAX_FPS", "MTL_HUD_ENABLED", "D3DM_MTL4"]

    /// Reads Tannin's variables back out of a game's launch options.
    public init(parsing launchOptions: String) {
        self.init()
        for word in launchOptions.split(separator: " ", omittingEmptySubsequences: true) {
            let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "D3DM_SUPPORT_DXR": rayTracing = parts[1] == "1"
            case "D3DM_ENABLE_METALFX": metalFX = parts[1] == "1"
            case "D3DM_MAX_FPS": frameCap = Int(parts[1])
            case "MTL_HUD_ENABLED": performanceHUD = parts[1] == "1"
            case "D3DM_MTL4": metal4 = parts[1] == "1"
            default: break
            }
        }
    }

    var assignments: [String] {
        var result: [String] = []
        if let rayTracing { result.append("D3DM_SUPPORT_DXR=\(rayTracing ? 1 : 0)") }
        if let metalFX { result.append("D3DM_ENABLE_METALFX=\(metalFX ? 1 : 0)") }
        if let frameCap, frameCap > 0 { result.append("D3DM_MAX_FPS=\(frameCap)") }
        if let performanceHUD { result.append("MTL_HUD_ENABLED=\(performanceHUD ? 1 : 0)") }
        if let metal4 { result.append("D3DM_MTL4=\(metal4 ? 1 : 0)") }
        return result
    }

    /// Merges these settings into existing launch options: Tannin's variables are replaced, everything else stays.
    /// With nothing to set and nothing of the user's own, the result is empty, so Steam's field is left clear.
    public func launchOptions(merging existing: String = "") -> String {
        var words = existing.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        words.removeAll { word in Self.ownedKeys.contains { word.hasPrefix("\($0)=") } }
        let own = assignments
        if own.isEmpty, words.allSatisfy({ $0 == "%command%" }) { return "" }
        if !words.contains("%command%") { words.append("%command%") }
        return (own + words).joined(separator: " ")
    }
}

/// Ready-made choices offered before the individual switches.
public enum GamePreset: String, Sendable, CaseIterable, Identifiable {
    case recommended, bestSpeed, bestBattery, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recommended: "Recommended"
        case .bestSpeed: "Best speed"
        case .bestBattery: "Best battery"
        case .custom: "Custom"
        }
    }

    /// The settings a preset stands for. Custom has none of its own.
    public var settings: GameSettings? {
        switch self {
        case .recommended: GameSettings()
        case .bestSpeed: GameSettings(rayTracing: false, metalFX: true).normalized
        case .bestBattery: GameSettings(frameCap: 30)
        case .custom: nil
        }
    }

    /// Which preset these settings amount to.
    public init(matching settings: GameSettings) {
        let normalized = settings.normalized
        self = Self.allCases.first { $0.settings?.normalized == normalized } ?? .custom
    }
}
