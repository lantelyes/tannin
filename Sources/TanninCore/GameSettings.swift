import Foundation

/// How one game should run. A nil field means "leave it to the default", and writes nothing.
public struct GameSettings: Sendable, Equatable {
    /// Which graphics layer the game is given. Automatic writes nothing.
    public var layer: GraphicsLayer
    // D3DMetal's own.
    public var rayTracing: Bool?
    public var metalFX: Bool?
    public var metal4: Bool?
    /// DXMT's own: draw the game smaller by this factor and enlarge it. Nil is off.
    public var upscaling: Double?
    /// DXVK's own: prepare effects in the background instead of pausing the game for them.
    public var backgroundEffects: Bool?
    // On every layer.
    public var frameCap: Int?
    public var performanceHUD: Bool?

    public init(layer: GraphicsLayer = .automatic, rayTracing: Bool? = nil, metalFX: Bool? = nil, frameCap: Int? = nil,
                performanceHUD: Bool? = nil, metal4: Bool? = nil, upscaling: Double? = nil, backgroundEffects: Bool? = nil) {
        self.layer = layer
        self.rayTracing = rayTracing
        self.metalFX = metalFX
        self.frameCap = frameCap
        self.performanceHUD = performanceHUD
        self.metal4 = metal4
        self.upscaling = upscaling
        self.backgroundEffects = backgroundEffects
    }

    /// What a field means when it is left alone, per Apple's Read Me for an M1/M2 Mac on macOS 27.
    public enum Default {
        public static let rayTracing = false
        public static let metalFX = false
        public static let frameCap = 0
        public static let performanceHUD = false
        public static let metal4 = true
        public static let upscaling = 0.0
        public static let backgroundEffects = false
    }

    /// The upscaling factors DXMT is given. 0 stands for off.
    public static let upscalingFactors: [Double] = [0, 1.5, 2, 3]

    /// Builds settings from concrete values, storing nothing for values that equal the default.
    public init(layer: GraphicsLayer = .automatic, rayTracingOn: Bool, metalFXOn: Bool, frameCapValue: Int, performanceHUDOn: Bool,
                metal4On: Bool, upscalingValue: Double = Default.upscaling, backgroundEffectsOn: Bool = Default.backgroundEffects) {
        self.init(
            layer: layer,
            rayTracing: rayTracingOn == Default.rayTracing ? nil : rayTracingOn,
            metalFX: metalFXOn == Default.metalFX ? nil : metalFXOn,
            frameCap: frameCapValue == Default.frameCap ? nil : frameCapValue,
            performanceHUD: performanceHUDOn == Default.performanceHUD ? nil : performanceHUDOn,
            metal4: metal4On == Default.metal4 ? nil : metal4On,
            upscaling: upscalingValue == Default.upscaling ? nil : upscalingValue,
            backgroundEffects: backgroundEffectsOn == Default.backgroundEffects ? nil : backgroundEffectsOn
        )
    }

    public var rayTracingOn: Bool { rayTracing ?? Default.rayTracing }
    public var metalFXOn: Bool { metalFX ?? Default.metalFX }
    public var frameCapValue: Int { frameCap ?? Default.frameCap }
    public var performanceHUDOn: Bool { performanceHUD ?? Default.performanceHUD }
    public var metal4On: Bool { metal4 ?? Default.metal4 }
    public var upscalingValue: Double { upscaling ?? Default.upscaling }
    public var backgroundEffectsOn: Bool { backgroundEffects ?? Default.backgroundEffects }

    /// The same settings with defaults spelled out as nil, so two ways of saying the same thing compare equal.
    public var normalized: GameSettings {
        GameSettings(layer: layer, rayTracingOn: rayTracingOn, metalFXOn: metalFXOn, frameCapValue: frameCapValue,
                     performanceHUDOn: performanceHUDOn, metal4On: metal4On, upscalingValue: upscalingValue,
                     backgroundEffectsOn: backgroundEffectsOn)
    }

    /// The same settings without the ones that do nothing on `effective`, the layer the game really gets.
    /// With the layer not known yet (a game that is not installed, on Automatic) only the shared ones are kept.
    public func keeping(onlyWhatAppliesTo effective: GraphicsLayer?) -> GameSettings {
        var result = self
        if effective != .d3dMetal { result.rayTracing = nil; result.metalFX = nil; result.metal4 = nil }
        if effective != .dxmt { result.upscaling = nil }
        if effective != .dxvk { result.backgroundEffects = nil }
        return result
    }

    // MARK: Launch options

    static let variantKey = "NOTPROTON_RUNNER_VARIANT"
    static let layerMarkKey = "NOTPROTON_ENV_TANNIN_LAYER"
    static let dxmtConfigKey = "DXMT_CONFIG"
    static let dxmtFrameRate = "d3d11.preferredMaxFrameRate"
    static let dxmtUpscaleFactor = "d3d11.metalSpatialUpscaleFactor"

    /// Variables Tannin owns in a game's launch options. Anything else the user typed there is kept.
    static let ownedKeys = [
        "CX_ACTIVE_GRAPHICS_BACKEND", "D3DM_SUPPORT_DXR", "D3DM_ENABLE_METALFX", "D3DM_MAX_FPS", "MTL_HUD_ENABLED", "D3DM_MTL4",
        layerMarkKey, "DXMT_METALFX_SPATIAL_SWAPCHAIN", "DXVK_ASYNC", "DXVK_FRAME_RATE",
    ] + EngineSpec.all.map(\.dxvkPlugin)

    private static func split(_ word: String) -> (key: String, value: String)? {
        let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
    }

    private static func words(_ launchOptions: String) -> [String] {
        launchOptions.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    private static func clauses(_ config: String) -> [(key: String, value: String)] {
        config.split(separator: ";").compactMap { clause in
            let parts = clause.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }

    /// Reads Tannin's variables back out of a game's launch options, including ones changed in Steam's own window.
    public init(parsing launchOptions: String) {
        self.init()
        var variant: String?
        var dxvkOn = false
        var marked: String?
        for word in Self.words(launchOptions) {
            guard let (key, value) = Self.split(word) else { continue }
            switch key {
            case "D3DM_SUPPORT_DXR": rayTracing = value == "1"
            case "D3DM_ENABLE_METALFX": metalFX = value == "1"
            case "D3DM_MAX_FPS", "DXVK_FRAME_RATE": if let cap = Int(value), cap > 0 { frameCap = cap }
            case "MTL_HUD_ENABLED": performanceHUD = value == "1"
            case "D3DM_MTL4": metal4 = value == "1"
            case "DXVK_ASYNC": backgroundEffects = value == "1"
            case Self.variantKey: variant = value
            case Self.layerMarkKey: marked = value
            case let key where EngineSpec.all.contains { $0.dxvkPlugin == key }: dxvkOn = value == "1"
            case Self.dxmtConfigKey:
                for clause in Self.clauses(value) {
                    if clause.key == Self.dxmtFrameRate, let cap = Int(clause.value), cap > 0 { frameCap = cap }
                    if clause.key == Self.dxmtUpscaleFactor, let factor = Double(clause.value), factor > 1 { upscaling = factor }
                }
            default: break
            }
        }
        // Each engine has its own names for these; any of them means the same layer.
        if let variant, EngineSpec.all.contains(where: { $0.dxmtVariant == variant }) {
            layer = .dxmt
        } else if let variant, EngineSpec.all.contains(where: { $0.plainVariant == variant }), dxvkOn {
            layer = .dxvk
        } else if marked == "d3dmetal" {
            layer = .d3dMetal
        }
    }

    private static func number(_ value: Double) -> String {
        // DXMT's own spelling: 1.5, 2.0, 3.0.
        String(format: "%.2f", value).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
    }

    /// The assignments for this layer on one engine. `foreignClauses` are parts of the user's own DXMT_CONFIG,
    /// which are kept.
    func assignments(foreignClauses: [String] = [], engine: EngineSpec = .newest) -> [String] {
        var result: [String] = []
        let forD3DMetal = layer == .automatic || layer == .d3dMetal
        let forDXMT = layer == .automatic || layer == .dxmt
        let cap = (frameCap ?? 0) > 0 ? frameCap : nil

        switch layer {
        case .automatic: break
        case .d3dMetal: result.append("\(Self.layerMarkKey)=d3dmetal")
        case .dxmt: result.append("\(Self.variantKey)=\(engine.dxmtVariant)")
        case .dxvk: result += ["\(Self.variantKey)=\(engine.plainVariant)", "\(engine.dxvkPlugin)=1"]
        }
        if forD3DMetal {
            if let rayTracing { result.append("D3DM_SUPPORT_DXR=\(rayTracing ? 1 : 0)") }
            if let metalFX { result.append("D3DM_ENABLE_METALFX=\(metalFX ? 1 : 0)") }
            if let cap { result.append("D3DM_MAX_FPS=\(cap)") }
        }
        var dxmt = foreignClauses
        if forDXMT {
            if let cap { dxmt.append("\(Self.dxmtFrameRate)=\(cap)") }
            if let upscaling, upscaling > 1 {
                result.append("DXMT_METALFX_SPATIAL_SWAPCHAIN=1")
                dxmt.append("\(Self.dxmtUpscaleFactor)=\(Self.number(upscaling))")
            }
        }
        if !dxmt.isEmpty {
            // Steam hands the launch options to a shell, where an unquoted ";" would end the command.
            let value = dxmt.joined(separator: ";")
            result.append(dxmt.count > 1 ? "\(Self.dxmtConfigKey)=\"\(value)\"" : "\(Self.dxmtConfigKey)=\(value)")
        }
        if layer == .dxvk {
            if let backgroundEffects { result.append("DXVK_ASYNC=\(backgroundEffects ? 1 : 0)") }
            if let cap { result.append("DXVK_FRAME_RATE=\(cap)") }
        }
        if let performanceHUD { result.append("MTL_HUD_ENABLED=\(performanceHUD ? 1 : 0)") }
        if forD3DMetal, let metal4 { result.append("D3DM_MTL4=\(metal4 ? 1 : 0)") }
        return result
    }

    /// Merges these settings into existing launch options: Tannin's variables are replaced, everything else stays.
    /// With nothing to set and nothing of the user's own, the result is empty, so Steam's field is left clear.
    /// `engine` is the Wine engine the game runs on, whose layer files the options have to name.
    public func launchOptions(merging existing: String = "", engine: EngineSpec = .newest) -> String {
        var foreignClauses: [String] = []
        var words: [String] = []
        for word in Self.words(existing) {
            guard let (key, value) = Self.split(word) else { words.append(word); continue }
            if Self.ownedKeys.contains(key) { continue }
            if key == Self.variantKey {
                // The user's own runner variant stays unless the chosen layer needs the place.
                let ours = EngineSpec.all.contains { $0.dxmtVariant == value || $0.plainVariant == value }
                if ours || layer == .dxmt || layer == .dxvk { continue }
            }
            if key == Self.dxmtConfigKey {
                foreignClauses += Self.clauses(value)
                    .filter { ![Self.dxmtFrameRate, Self.dxmtUpscaleFactor].contains($0.key) }
                    .map { "\($0.key)=\($0.value)" }
                continue
            }
            words.append(word)
        }
        let own = assignments(foreignClauses: foreignClauses, engine: engine)
        if own.isEmpty, words.allSatisfy({ $0 == "%command%" }) { return "" }
        if !words.contains("%command%") { words.append("%command%") }
        return (own + words).joined(separator: " ")
    }
}

/// Ready-made choices offered before the individual switches. A preset never changes the graphics layer.
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

    /// The settings a preset stands for on a game whose layer is `layer` and really runs on `effective`.
    /// Custom has none of its own.
    public func settings(layer: GraphicsLayer = .automatic, effective: GraphicsLayer? = .d3dMetal) -> GameSettings? {
        switch self {
        case .recommended:
            return GameSettings(layer: layer)
        case .bestSpeed:
            switch effective {
            case .d3dMetal: return GameSettings(layer: layer, metalFX: true)
            // Only D3DMetal has a setting that buys speed. DXMT's upscaling enlarges the picture, it does not
            // draw less (seen with LEGO Builder's Journey, 2026-11-18), and DXVK's background preparing makes
            // a game smoother, not faster, so it is left as a switch of its own (decided 2026-11-18).
            case .dxmt, .dxvk, .automatic, nil: return nil
            }
        case .bestBattery:
            return GameSettings(layer: layer, frameCap: 30)
        case .custom:
            return nil
        }
    }

    /// Which preset these settings amount to.
    public init(matching settings: GameSettings, effective: GraphicsLayer? = .d3dMetal) {
        let normalized = settings.normalized
        self = Self.allCases.first { $0.settings(layer: settings.layer, effective: effective)?.normalized == normalized } ?? .custom
    }

    /// The presets that mean something on this layer.
    public static func offered(effective: GraphicsLayer?) -> [GamePreset] {
        allCases.filter { $0 == .custom || $0.settings(effective: effective) != nil }
    }
}
