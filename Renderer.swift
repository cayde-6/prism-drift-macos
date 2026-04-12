import AVFoundation
import CoreGraphics
import CoreVideo
import Metal
import MetalKit
import QuartzCore
import simd

/// Uniform block shared with the Metal fragment shader.
struct Uniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var loopDuration: Float
}

/// Errors surfaced by the shared renderer and the offline video export path.
enum RendererError: LocalizedError {
    case missingDevice
    case failedToCreateCommandQueue
    case failedToLoadLibraryFromBundle(URL?)
    case missingShaderFunction(String)
    case failedToCreatePipelineState(Error)
    case failedToCreateRenderEncoder
    case failedToCreateCommandBuffer
    case failedToCreateTexture
    case failedToCreateAssetWriter(Error)
    case failedToCreatePixelBufferPool
    case failedToCreatePixelBuffer
    case failedToAppendVideoFrame(Int)
    case failedToFinishWriting(Error?)

    var errorDescription: String? {
        switch self {
        case .missingDevice:
            return "A Metal-capable GPU is required."
        case .failedToCreateCommandQueue:
            return "Failed to create a Metal command queue."
        case .failedToLoadLibraryFromBundle(let bundleURL):
            if let bundleURL {
                return "Failed to load the Metal shader library from bundle at \(bundleURL.path)."
            }
            return "Failed to load the Metal shader library from the provided bundle."
        case .missingShaderFunction(let name):
            return "Failed to load the Metal shader function '\(name)'."
        case .failedToCreatePipelineState(let error):
            return "Failed to create the render pipeline state: \(error.localizedDescription)"
        case .failedToCreateRenderEncoder:
            return "Failed to create a Metal render command encoder."
        case .failedToCreateCommandBuffer:
            return "Failed to create a Metal command buffer."
        case .failedToCreateTexture:
            return "Failed to create the offscreen render target texture."
        case .failedToCreateAssetWriter(let error):
            return "Failed to create the video writer: \(error.localizedDescription)"
        case .failedToCreatePixelBufferPool:
            return "Failed to create the pixel buffer pool for video export."
        case .failedToCreatePixelBuffer:
            return "Failed to allocate a pixel buffer for a video frame."
        case .failedToAppendVideoFrame(let frameIndex):
            return "Failed to append video frame \(frameIndex)."
        case .failedToFinishWriting(let error):
            return "Failed to finish writing the exported video: \(error?.localizedDescription ?? "Unknown error.")"
        }
    }
}

/// Shared Metal renderer used by the preview app and the `.saver` bundle.
final class Renderer: NSObject, MTKViewDelegate {
    static let liveLoopDuration: Float = 12.0

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let colorPixelFormat: MTLPixelFormat
    private var animationStartTime = CACurrentMediaTime()

    init(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm,
        shaderBundle: Bundle = .main
    ) throws {
        self.device = device
        self.colorPixelFormat = colorPixelFormat

        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.failedToCreateCommandQueue
        }

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: shaderBundle)
        } catch {
            // The app target can fall back to the default bundle lookup when the
            // generated metallib is embedded in the main app bundle. The screen
            // saver must resolve from its own bundle explicitly.
            if shaderBundle == .main, let fallbackLibrary = device.makeDefaultLibrary() {
                library = fallbackLibrary
            } else {
                throw RendererError.failedToLoadLibraryFromBundle(shaderBundle.bundleURL)
            }
        }

        guard let vertexFunction = library.makeFunction(name: "fullscreenVertex") else {
            throw RendererError.missingShaderFunction("fullscreenVertex")
        }

        guard let fragmentFunction = library.makeFunction(name: "lightBeamsFragment") else {
            throw RendererError.missingShaderFunction("lightBeamsFragment")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Light Beams Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw RendererError.failedToCreatePipelineState(error)
        }

        self.commandQueue = commandQueue

        super.init()
    }

    convenience init(metalView: MTKView) throws {
        guard let device = metalView.device else {
            throw RendererError.missingDevice
        }

        try self.init(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            shaderBundle: .main
        )
    }

    /// Apply the common MTKView configuration used by the preview app and the screen saver.
    func configure(metalView: MTKView, preferredFramesPerSecond: Int, paused: Bool) {
        metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        metalView.colorPixelFormat = colorPixelFormat
        metalView.framebufferOnly = false
        metalView.isPaused = paused
        metalView.enableSetNeedsDisplay = false
        metalView.autoResizeDrawable = true
        metalView.preferredFramesPerSecond = preferredFramesPerSecond
        metalView.delegate = self

        if let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) {
            metalView.colorspace = displayP3
        }
    }

    /// Reset animation timing when a new preview session or screen saver session starts.
    func resetAnimationClock() {
        animationStartTime = CACurrentMediaTime()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The effect is resolution-independent, so resizing only changes the
        // uniforms passed during the next draw call.
    }

    func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        do {
            try encodeFrame(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                drawableSize: CGSize(width: view.drawableSize.width, height: view.drawableSize.height),
                time: Float(CACurrentMediaTime() - animationStartTime),
                loopDuration: Self.liveLoopDuration
            )
        } catch {
            assertionFailure("Renderer error: \(error.localizedDescription)")
            return
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Render a seamless loopable HEVC movie directly from the shader without
    /// round-tripping through GIFs or screenshots.
    func exportLoopVideo(
        to outputURL: URL,
        size: CGSize,
        fps: Int,
        duration: Double,
        loopDuration: Float
    ) throws {
        let width = max(1, Int(size.width.rounded(.toNearestOrAwayFromZero)))
        let height = max(1, Int(size.height.rounded(.toNearestOrAwayFromZero)))
        let totalFrames = max(1, Int((duration * Double(fps)).rounded(.toNearestOrAwayFromZero)))

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let texture = try makeOffscreenTexture(size: CGSize(width: width, height: height))

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw RendererError.failedToCreateAssetWriter(error)
        }

        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: max(width * height * 8, 60_000_000),
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalKey: fps
        ]

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw RendererError.failedToCreateAssetWriter(
                NSError(domain: "Renderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "The video writer input could not be added."])
            )
        }

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw RendererError.failedToCreatePixelBufferPool
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }

            try autoreleasepool {
                let frameTime = Float(Double(frameIndex) / Double(fps))
                try renderFrame(
                    to: texture,
                    drawableSize: CGSize(width: width, height: height),
                    time: frameTime,
                    loopDuration: loopDuration
                )

                var pixelBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
                guard status == kCVReturnSuccess, let pixelBuffer else {
                    throw RendererError.failedToCreatePixelBuffer
                }

                copy(texture: texture, to: pixelBuffer)

                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw RendererError.failedToAppendVideoFrame(frameIndex)
                }
            }
        }

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw RendererError.failedToFinishWriting(writer.error)
        }
    }

    /// Encode the fullscreen triangle pass that feeds the procedural fragment shader.
    private func encodeFrame(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        time: Float,
        loopDuration: Float
    ) throws {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw RendererError.failedToCreateRenderEncoder
        }

        var uniforms = Uniforms(
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            time: time,
            loopDuration: loopDuration
        )

        encoder.label = "Light Beams Encoder"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func renderFrame(
        to texture: MTLTexture,
        drawableSize: CGSize,
        time: Float,
        loopDuration: Float
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.failedToCreateCommandBuffer
        }

        let renderPassDescriptor = makeRenderPassDescriptor(
            texture: texture,
            clearColor: MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        )

        try encodeFrame(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            drawableSize: drawableSize,
            time: time,
            loopDuration: loopDuration
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makeOffscreenTexture(size: CGSize) throws -> MTLTexture {
        let width = max(1, Int(size.width.rounded(.toNearestOrAwayFromZero)))
        let height = max(1, Int(size.height.rounded(.toNearestOrAwayFromZero)))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.failedToCreateTexture
        }

        return texture
    }

    private func makeRenderPassDescriptor(texture: MTLTexture, clearColor: MTLClearColor) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = clearColor
        return descriptor
    }

    private func copy(texture: MTLTexture, to pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = texture.width
        let height = texture.height
        let region = MTLRegionMake2D(0, 0, width, height)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
    }
}
