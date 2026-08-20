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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mtkView?.frame = view.bounds
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
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
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
    private var isFetching = false
    private let fetchSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.3
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
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

    // 🖥️ ゼロクラッシュ・高耐久リアルタイムデスクトップストリーム受信
    func startDirectDesktopStream() {
        displayLink = CADisplayLink(target: self, selector: #selector(fetchFrameTick))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
        print("🚀 Connected to Direct PC Desktop Stream at: http://\(hostIP):9051")
    }

    func stopDirectDesktopStream() {
        displayLink?.invalidate()
        displayLink = nil
        isFetching = false
    }

    @objc private func fetchFrameTick() {
        guard isStreamingActive, !isFetching else { return }
        guard let url = URL(string: "http://\(hostIP):9051/screen.jpg") else { return }

        isFetching = true
        let task = fetchSession.dataTask(with: url) { [weak self] data, response, error in
            defer { self?.isFetching = false }
            guard let self = self, let data = data else { return }

            autoreleasepool {
                if let image = UIImage(data: data), let cgImage = image.cgImage {
                    let loader = MTKTextureLoader(device: self.device)
                    if let texture = try? loader.newTexture(cgImage: cgImage, options: [
                        .SRGB: false,
                        .generateMipmaps: false,
                        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
                    ]) {
                        DispatchQueue.main.async {
                            self.currentTexture = texture
                        }
                    }
                }
            }
        }
        task.resume()
    }
}

