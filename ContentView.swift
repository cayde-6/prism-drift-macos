import SwiftUI

struct ContentView: View {
    var body: some View {
        // The preview app is intentionally just a fullscreen Metal canvas.
        MetalView()
            .ignoresSafeArea()
    }
}
