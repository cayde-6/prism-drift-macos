import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let exportResult = VideoExporter.exportIfRequested() {
            switch exportResult {
            case .success(let outputURL):
                print("Exported loop video to \(outputURL.path)")
                exit(EXIT_SUCCESS)
            case .failure(let error):
                fputs("Video export failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        DispatchQueue.main.async {
            self.configurePrimaryWindowIfNeeded()
        }
    }

    /// Configure the preview app's primary window so it behaves like a fullscreen canvas.
    private func configurePrimaryWindowIfNeeded() {
        guard let window = NSApplication.shared.windows.first else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.backgroundColor = .black

        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}

@main
struct PrismDriftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
