import TanninCore

/// The controls on a game's page, as concrete values they can bind to.
struct SettingsDraft: Equatable {
    var layer: GraphicsLayer
    var rayTracing: Bool
    var metalFX: Bool
    var frameCap: Int
    var performanceHUD: Bool
    var metal4: Bool
    var upscaling: Double
    var backgroundEffects: Bool

    init(_ settings: GameSettings) {
        layer = settings.layer
        rayTracing = settings.rayTracingOn
        metalFX = settings.metalFXOn
        frameCap = settings.frameCapValue
        performanceHUD = settings.performanceHUDOn
        metal4 = settings.metal4On
        upscaling = settings.upscalingValue
        backgroundEffects = settings.backgroundEffectsOn
    }

    /// Only values that differ from the default are stored.
    var settings: GameSettings {
        GameSettings(layer: layer, rayTracingOn: rayTracing, metalFXOn: metalFX, frameCapValue: frameCap,
                     performanceHUDOn: performanceHUD, metal4On: metal4, upscalingValue: upscaling,
                     backgroundEffectsOn: backgroundEffects)
    }

    static let frameCaps = [0, 30, 60, 120]
}
