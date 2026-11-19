import SwiftUI
import TanninCore

/// The settings that belong to the renderer a game really gets, under that renderer's name. A game drawn by
/// Wine itself, or one whose renderer is not known yet, has only the frame cap, under "Graphics".
struct GameRendererSettings: View {
    @Binding var draft: SettingsDraft
    /// The renderer in effect: the one chosen, or what Automatic comes to.
    let renderer: GraphicsLayer?

    var body: some View {
        Section(renderer.map { "\($0.title) Settings" } ?? "Graphics") {
            switch renderer {
            case .d3dMetal:
                Toggle(isOn: $draft.rayTracing) {
                    Text("Ray Tracing")
                    Text("Better lighting at a lower frame rate. Off by default on M1 and M2.")
                }
                Toggle(isOn: $draft.metalFX) {
                    Text("MetalFX Upscaling")
                    Text("Lets the game’s DLSS setting use Apple’s upscaler.")
                }
            case .dxmt:
                Picker(selection: $draft.upscaling) {
                    ForEach(GameSettings.upscalingFactors, id: \.self) { factor in
                        Text(factor == 0 ? "Off" : "\(factor.formatted())×").tag(factor)
                    }
                } label: {
                    Text("Upscaling")
                    Text("Upscales the game with MetalFX. Lower the in-game resolution for better performance.")
                }
            case .dxvk:
                Toggle(isOn: $draft.backgroundEffects) {
                    Text("Compile Shaders in the Background")
                    Text("Reduces stutter when an effect first appears. Some effects may show up a moment late.")
                }
            case .automatic, nil:
                EmptyView()
            }
            Picker("Frame Cap", selection: $draft.frameCap) {
                ForEach(SettingsDraft.frameCaps, id: \.self) { cap in
                    Text(cap == 0 ? "None" : "\(cap) fps").tag(cap)
                }
            }
            if renderer == .d3dMetal {
                Toggle(isOn: $draft.metal4) {
                    Text("Metal 4 Renderer")
                    Text("The default on macOS 27. Turn off to use Metal 3.")
                }
            }
        }
    }
}
