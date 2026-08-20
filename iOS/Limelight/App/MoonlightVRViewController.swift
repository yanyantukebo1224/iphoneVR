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

    private var directStreamTask: URLSessionDataTask?
    private var streamSession: URLSession?
    private var receivedDataBuffer = Data()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startDirectDesktopStream()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDirectDesktopStream()
    }

    // 🖥️ PC 画面丸ごとダイレクト VR ストリーム受信 (Port 9051)
    func startDirectDesktopStream() {
        let targetIP = UserDefaults.standard.string(forKey: "pc_target_ip") ?? "192.168.0.13"
        guard let url = URL(string: "http://\(targetIP):9051") else { return }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        streamSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.timeoutInterval = 60.0
        directStreamTask = streamSession?.dataTask(with: request)
        directStreamTask?.resume()
        print("🚀 Connecting to Direct PC Desktop Stream at: \(url)")
    }

    func stopDirectDesktopStream() {
        directStreamTask?.cancel()
        directStreamTask = nil
        streamSession?.invalidateAndCancel()
        streamSession = nil
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

// MARK: - URLSessionDataDelegate (MJPEG Multipart Stream Parser)
extension MoonlightVRViewController: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedDataBuffer.append(data)

        // JPEG の開始マーカー 0xFF, 0xD8 と終了マーカー 0xFF, 0xD9 を探索
        while let startRange = receivedDataBuffer.range(of: Data([0xFF, 0xD8])),
              let endRange = receivedDataBuffer.range(of: Data([0xFF, 0xD9]), in: startRange.upperBound..<receivedDataBuffer.count) {

            let jpegData = receivedDataBuffer.subdata(in: startRange.lowerBound..<endRange.upperBound)
            receivedDataBuffer.removeSubrange(0..<endRange.upperBound)

            if let image = UIImage(data: jpegData) {
                updateTexture(from: image)
            }
        }

        // バッファ肥大化防止
        if receivedDataBuffer.count > 5 * 1024 * 1024 {
            receivedDataBuffer.removeAll()
        }
    }
}

