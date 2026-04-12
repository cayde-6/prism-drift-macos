import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    final class Coordinator {
        // MTKView keeps its delegate weak, so the coordinator owns the renderer
        // for the lifetime of the SwiftUI wrapper.
        var renderer: Renderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("This app requires a Mac with Metal support.")
        }

        let metalView = MTKView(frame: .zero, device: device)
        let renderer: Renderer

        do {
            renderer = try Renderer(metalView: metalView)
        } catch {
            fatalError("Failed to create the Metal renderer: \(error.localizedDescription)")
        }

        renderer.configure(
            metalView: metalView,
            preferredFramesPerSecond: NSScreen.main?.maximumFramesPerSecond ?? 120,
            paused: false
        )

        context.coordinator.renderer = renderer
        return metalView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // The renderer is entirely driven by MTKView's draw loop.
    }
}
