import UIKit
import Metal
import MetalKit
import CoreVideo

class MoonlightVRViewController: UIViewController, MTKViewDelegate {
    private var mtkView: MTKView!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var textureCache: CVMetalTextureCache?

    private var currentTexture: MTLTexture?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMetal()
        setupPipeline()
    }

    private func setupMetal() {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        device = defaultDevice
        commandQueue = device.makeCommandQueue()

        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.delegate = self
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mtkView)

        // ポプちゃん指示: CVMetalTextureCache によるゼロコピーテクスチャ初期化
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    private func setupPipeline() {
        guard let defaultLibrary = device.makeDefaultLibrary() else {
            print("Failed to load default Metal library")
            return
        }
        let vertexProgram = defaultLibrary.makeFunction(name: "vrVertexShader")
        let fragmentProgram = defaultLibrary.makeFunction(name: "vrDistortionFragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexProgram
        pipelineDescriptor.fragmentFunction = fragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    // Moonlightデコーダーからの CVPixelBuffer 受領 (コピーフリー遅延ゼロ)
    func processDecodedFrame(pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTextureOut: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut
        )

        if result == kCVReturnSuccess, let cvTexture = cvTextureOut {
            self.currentTexture = CVMetalTextureGetTexture(cvTexture)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    // MTKView Render Loop (60/120Hz)
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        if let texture = currentTexture {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    var hostIP: String = "192.168.0.13"
    private var isStreamingActive = false
    private var displayLink: CADisplayLink?
    private var isFetchingFrame = false
    private let fetchSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.5
        return URLSession(configuration: cfg)
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isStreamingActive = true
        startDirectDesktopStream()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isStreamingActive = false
        stopDirectDesktopStream()
    }

    // 🖥️ PC 画面丸ごとダイレクト VR ストリーム受信 (Port 9051)
    func startDirectDesktopStream() {
        displayLink = CADisplayLink(target: self, selector: #selector(fetchNextFrame))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
        print("🚀 Connecting to Direct PC Desktop Stream at: http://\(hostIP):9051")
    }

    func stopDirectDesktopStream() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func fetchNextFrame() {
        guard isStreamingActive, !isFetchingFrame else { return }
        guard let url = URL(string: "http://\(hostIP):9051/screen.jpg") else { return }

        isFetchingFrame = true
        let task = fetchSession.dataTask(with: url) { [weak self] data, response, error in
            defer { self?.isFetchingFrame = false }
            guard let self = self, let data = data, let image = UIImage(data: data) else { return }
            self.updateTexture(from: image)
        }
        task.resume()
    }

    // UIImage から MTLTexture へ超高速ロード
    func updateTexture(from image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let loader = MTKTextureLoader(device: device)
        if let texture = try? loader.newTexture(cgImage: cgImage, options: [
            .SRGB: false,
            .generateMipmaps: false
        ]) {
            DispatchQueue.main.async {
                self.currentTexture = texture
            }
        }
    }
}

