import MetalKit
import ScreenSaver

/// ScreenSaverView host that embeds the shared Metal renderer inside the saver bundle.
@objc(PrismDriftScreenSaverView)
final class PrismDriftScreenSaverView: ScreenSaverView {
    private var metalView: MTKView?
    private var renderer: Renderer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        // System Settings preview does not need the same frame rate as the fullscreen saver.
        animationTimeInterval = isPreview ? 1.0 / 30.0 : 1.0 / 60.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PrismDriftScreenSaverView must be created with init(frame:isPreview:).")
    }

    override func startAnimation() {
        super.startAnimation()

        ensureMetalPipeline()

        // Reset the shared renderer so the saver always starts from a clean
        // animation phase when macOS activates it on the lock screen.
        renderer?.resetAnimationClock()
        metalView?.draw()
    }

    override func animateOneFrame() {
        // The screen saver timer drives the MTKView manually to stay in sync with ScreenSaverView.
        metalView?.draw()
    }

    override func stopAnimation() {
        super.stopAnimation()

        metalView?.removeFromSuperview()
        metalView = nil
        renderer = nil
    }

    override func layout() {
        super.layout()
        metalView?.frame = bounds
    }

    override var isOpaque: Bool {
        true
    }

    private func ensureMetalPipeline() {
        if metalView != nil, renderer != nil {
            return
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("PrismDriftSaver failed to create the system Metal device.")
            return
        }

        let saverBundle = Bundle(for: PrismDriftScreenSaverView.self)
        let renderer: Renderer

        do {
            renderer = try Renderer(device: device, shaderBundle: saverBundle)
        } catch {
            NSLog("PrismDriftSaver failed to initialize renderer: %@", error.localizedDescription)
            return
        }

        let metalView = MTKView(frame: bounds, device: device)

        metalView.frame = bounds
        metalView.autoresizingMask = [.width, .height]

        // ScreenSaverView owns the timing loop, so the MTKView renders only
        // when animateOneFrame() tells it to draw. Delaying setup until
        // startAnimation() keeps initialization lightweight for the system loader.
        renderer.configure(
            metalView: metalView,
            preferredFramesPerSecond: isPreview ? 30 : 60,
            paused: true
        )

        self.renderer = renderer
        self.metalView = metalView
        addSubview(metalView)
    }
}
