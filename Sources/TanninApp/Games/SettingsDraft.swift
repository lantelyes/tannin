import TanninCore

/// The switches on the game settings screen, as concrete values the controls can bind to.
struct SettingsDraft: Equatable {
    var rayTracing: Bool
    var metalFX: Bool
    var frameCap: Int
    var performanceHUD: Bool
    var metal4: Bool

    init(_ settings: GameSettings) {
        rayTracing = settings.rayTracingOn
        metalFX = settings.metalFXOn
        frameCap = settings.frameCapValue
        performanceHUD = settings.performanceHUDOn
        metal4 = settings.metal4On
    }

    /// Only values that differ from the default are stored.
    var settings: GameSettings {
        GameSettings(rayTracingOn: rayTracing, metalFXOn: metalFX, frameCapValue: frameCap,
                     performanceHUDOn: performanceHUD, metal4On: metal4)
    }

    static let frameCaps = [0, 30, 60, 120]
}
