import AVFoundation
import Foundation
import Metal

struct VideoExportRequest {
    let outputURL: URL
    let size: CGSize
    let fps: Int
    let duration: Double
    let loopDuration: Float

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> VideoExportRequest? {
        guard let outputPath = environment["PRISMDRIFT_EXPORT_VIDEO_PATH"], !outputPath.isEmpty else {
            return nil
        }

        let width = Int(environment["PRISMDRIFT_EXPORT_WIDTH"] ?? "") ?? 3840
        let height = Int(environment["PRISMDRIFT_EXPORT_HEIGHT"] ?? "") ?? 2160
        let fps = Int(environment["PRISMDRIFT_EXPORT_FPS"] ?? "") ?? 240
        let duration = Double(environment["PRISMDRIFT_EXPORT_DURATION"] ?? "") ?? 10.0
        let loopDuration = Float(environment["PRISMDRIFT_EXPORT_LOOP_DURATION"] ?? "") ?? Float(duration)

        return VideoExportRequest(
            outputURL: URL(fileURLWithPath: outputPath),
            size: CGSize(width: max(1, width), height: max(1, height)),
            fps: max(1, fps),
            duration: max(0.1, duration),
            loopDuration: max(0.1, loopDuration)
        )
    }
}

enum VideoExporter {
    /// If export-specific environment variables are present, render a loopable
    /// HEVC movie and return the result without showing the preview window.
    static func exportIfRequested() -> Result<URL, Error>? {
        guard let request = VideoExportRequest.fromEnvironment() else {
            return nil
        }

        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw RendererError.missingDevice
            }

            let renderer = try Renderer(device: device, shaderBundle: .main)
            try renderer.exportLoopVideo(
                to: request.outputURL,
                size: request.size,
                fps: request.fps,
                duration: request.duration,
                loopDuration: request.loopDuration
            )
            return .success(request.outputURL)
        } catch {
            return .failure(error)
        }
    }
}
