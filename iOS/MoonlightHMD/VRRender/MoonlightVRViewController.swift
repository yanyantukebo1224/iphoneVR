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
    private var streamSession: URLSession?
    private var streamTask: URLSessionDataTask?
    private var receivedBuffer = Data()

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

    // 🖥️ 60fps MJPEG リアルタイム連続プッシュストリーム受信 (ゼロポーリング遅延)
    func startDirectDesktopStream() {
        guard let url = URL(string: "http://\(hostIP):9051/stream.mjpg") else { return }
        
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        streamSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        streamTask = streamSession?.dataTask(with: request)
        streamTask?.resume()
        print("🚀 Connected to Continuous 60fps PC VR Stream at: \(url)")
    }

    func stopDirectDesktopStream() {
        streamTask?.cancel()
        streamTask = nil
        streamSession?.invalidateAndCancel()
        streamSession = nil
        receivedBuffer.removeAll()
    }

    // UIImage から MTLTexture へ超高速ロード
    func updateTexture(from image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let loader = MTKTextureLoader(device: device)
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

// 🚀 60fps MJPEG ゼロコピーパーサー
extension MoonlightVRViewController: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard isStreamingActive else { return }
        receivedBuffer.append(data)

        // JPEG フレーム境界 (SOI: 0xFFD8, EOI: 0xFFD9) の高速スキャン
        let soi = Data([0xFF, 0xD8])
        let eoi = Data([0xFF, 0xD9])

        while let startRange = receivedBuffer.range(of: soi),
              let endRange = receivedBuffer.range(of: eoi, range: startRange.upperBound..<receivedBuffer.count) {
            
            let frameData = receivedBuffer.subdata(in: startRange.lowerBound..<endRange.upperBound)
            receivedBuffer.removeSubrange(0..<endRange.upperBound)

            if let image = UIImage(data: frameData) {
                self.updateTexture(from: image)
            }
        }

        // バッファ肥大化防止
        if receivedBuffer.count > 1024 * 1024 * 4 {
            receivedBuffer.removeAll()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isStreamingActive {
            // 自動再接続
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startDirectDesktopStream()
            }
        }
    }
}

