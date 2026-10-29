import Cocoa
import MetalKit

/// One device, queue and precompiled pipeline shared by all viewer windows.
/// The surface stays at display resolution; zoom never scales a backing bitmap.
final class MetalImageRenderer: NSObject, MTKViewDelegate {
    static let shared = MetalImageRenderer()
    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private let uploads = OperationQueue()

    private override init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        let descriptor = MTLRenderPipelineDescriptor()
        let library = device?.makeDefaultLibrary()
        descriptor.vertexFunction = library?.makeFunction(name: "imageVertex")
        descriptor.fragmentFunction = library?.makeFunction(name: "imageFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm_srgb
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try? device?.makeRenderPipelineState(descriptor: descriptor)
        super.init()
        uploads.maxConcurrentOperationCount = 2
        uploads.qualityOfService = .userInitiated
        uploads.name = "com.fastviewer.texture-upload"
    }

    var isAvailable: Bool { pipeline != nil }

    /// ImageIO has already decoded static previews on its background queue.
    /// Color conversion and GPU upload also stay off the UI thread.
    @discardableResult
    func upload(_ image: CGImage, completion: @escaping (MTLTexture?) -> Void) -> Operation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let texture = autoreleasepool { self?.makeTexture(image) }
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { completion(texture) }
        }
        uploads.addOperation(operation)
        return operation
    }

    internal func makeTexture(_ image: CGImage) -> MTLTexture? {
        guard let device else { return nil }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let bytes = context.data else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: bytesPerRow)
        return texture
    }

    /// Also used by the pixel regression tests with an offscreen GPU target.
    @discardableResult
    internal func render(texture: MTLTexture?, to target: MTLTexture,
                         geometry: SIMD4<Float>, nearest: Bool,
                         drawable: CAMetalDrawable? = nil,
                         synchronizesPresentation: Bool = false) -> MTLCommandBuffer? {
        guard let pipeline, let command = commandQueue?.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        if let texture {
            var geometry = geometry
            var sampling: UInt32 = nearest ? 1 : 0
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&geometry, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentBytes(&sampling, length: MemoryLayout<UInt32>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        if let drawable, !synchronizesPresentation { command.present(drawable) }
        command.commit()
        if let drawable, synchronizesPresentation {
            // Present in the same Core Animation transaction as the new window
            // size, rather than letting AppKit stretch the previous drawable.
            command.waitUntilScheduled()
            drawable.present()
        }
        return command
    }

    func draw(in view: MTKView) {
        guard let surface = view as? MetalImageSurface else { return }
        surface.prepareFrame?()
        guard let drawable = view.currentDrawable else { return }
        let command = render(texture: surface.texture, to: drawable.texture,
               geometry: surface.geometry, nearest: surface.nearest, drawable: drawable,
               synchronizesPresentation: surface.presentsWithTransaction)
        if command != nil {
            surface.lastPresentedDrawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            surface.onFramePresented?(surface.geometry, surface.texture)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.needsDisplay = true
    }
}

final class MetalImageSurface: MTKView {
    internal var prepareFrame: (() -> Void)?
    internal var lastPresentedDrawableSize = CGSize.zero
    internal var onFramePresented: ((SIMD4<Float>, MTLTexture?) -> Void)?
    var texture: MTLTexture? { didSet { needsDisplay = true } }
    var geometry = SIMD4<Float>(1, 1, 0, 0) {
        didSet { if geometry != oldValue { needsDisplay = true } }
    }
    var nearest = false {
        didSet { if nearest != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: .zero, device: MetalImageRenderer.shared.device)
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isPaused = true
        enableSetNeedsDisplay = true
        presentsWithTransaction = true
        framebufferOnly = true
        wantsLayer = true
        layer?.isOpaque = false
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        delegate = MetalImageRenderer.shared
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
