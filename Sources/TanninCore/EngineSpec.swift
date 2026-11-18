import Foundation

/// One Wine engine Tannin has tested: where it comes from, and the names Steam and the add-on know it by.
/// Only engines listed here can be installed. Each has its own pinned download and its own Steam bridge patch.
public struct EngineSpec: Sendable, Hashable, Identifiable {
    /// The winecx-gptk release, e.g. "4.8.3".
    public let version: String
    /// The Wine version it is built on, e.g. "11.19".
    public let wine: String
    public let pin: Pin
    /// The add-on's build name for the runner made from this engine.
    public let build: String
    /// The compatibility tool Steam lists it as. Must start with "notproton".
    public let toolName: String
    /// Added to the names of this engine's per-layer files, so two engines' files never mix.
    let layerSuffix: String
    /// One line on what it is, for the list of engines.
    public let note: String

    public var id: String { version }
    public var title: String { "Wine \(wine)" }
    /// What Steam shows under Properties, Compatibility.
    public var display: String { "Tannin (Wine \(wine))" }

    public var dxmtVariant: String { "tannin-dxmt\(layerSuffix)" }
    public var plainVariant: String { "tannin-plain\(layerSuffix)" }
    public var dxvkPlugin: String { "NOTPROTON_TANNIN_DXVK\(layerSuffix.uppercased().replacingOccurrences(of: "-", with: "_"))" }

    /// The names are the ones Tannin 0.2 and 0.3 used, so their installs carry on.
    public static let wine1119 = EngineSpec(
        version: Pins.engineVersion, wine: Pins.engineWine, pin: Pins.engine, build: "tannin-1",
        toolName: "notproton-tannin", layerSuffix: "", note: "The newest engine Tannin has tested."
    )

    public static let wine1117 = EngineSpec(
        version: "4.7.3", wine: "11.17", pin: Pins.engine1117, build: "tannin-1117",
        toolName: "notproton-tannin-1117", layerSuffix: "-1117", note: "The version before it."
    )

    /// Every engine this Tannin knows, newest first.
    public static let all: [EngineSpec] = [wine1119, wine1117]
    /// What setup installs.
    public static let newest = wine1119

    public static func named(tool: String) -> EngineSpec? { all.first { $0.toolName == tool } }
}
