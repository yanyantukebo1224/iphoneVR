import Foundation
import ARKit
import Vision
import Combine
import UIKit

class ARHandTrackerManager: NSObject, ARSessionDelegate, ObservableObject {
    let session = ARSession()
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.iphonevr.vision.processing", qos: .userInteractive)

    @Published var headPosition: SIMD3<Float> = .zero
    @Published var headRotation: simd_quatf = simd_quatf(real: 1, imag: .zero)
    @Published var leftHandData: HandPacketData?
    @Published var rightHandData: HandPacketData?

    private var isLeftPinchingState: Bool = false
    private var isRightPinchingState: Bool = false

    private var prevLeftLocalPos: SIMD3<Float> = SIMD3<Float>(-0.18, -0.15, -0.45)
    private var prevRightLocalPos: SIMD3<Float> = SIMD3<Float>(0.18, -0.15, -0.45)

    private var prevLeftLocalQuat: simd_quatf = simd_quatf(real: 1, imag: .zero)
    private var prevRightLocalQuat: simd_quatf = simd_quatf(real: 1, imag: .zero)

    private var prevLeftCurls = FingerCurls()
    private var prevRightCurls = FingerCurls()

    var onTrackingDataUpdated: ((SIMD3<Float>, simd_quatf, HandPacketData?, HandPacketData?) -> Void)?

    override init() {
        super.init()
        handPoseRequest.maximumHandCount = 2
        session.delegate = self
    }

    func startTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopTracking() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let rotation = simd_quaternion(transform)

        DispatchQueue.main.async {
            self.headPosition = position
            self.headRotation = rotation
        }

        let pixelBuffer = frame.capturedImage
        let visionOrientation = currentCGImagePropertyOrientation()

        processingQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: visionOrientation, options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                self.processHandObservation(results: self.handPoseRequest.results, frame: frame)
            } catch {
                print("Vision Hand Pose Error: \(error)")
            }
        }
    }

    private func currentCGImagePropertyOrientation() -> CGImagePropertyOrientation {
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
    }

    private func processHandObservation(results: [VNHumanHandPoseObservation]?, frame: ARFrame) {
        var newLeft: HandPacketData?
        var newRight: HandPacketData?

        if let observations = results, !observations.isEmpty {
            if observations.count >= 2 {
                let sortedObs = observations.sorted { obs1, obs2 in
                    let x1 = (try? obs1.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    let x2 = (try? obs2.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    return x1 < x2
                }
                newLeft = extract21Joints(from: sortedObs[0], chirality: 0)
                newRight = extract21Joints(from: sortedObs[1], chirality: 1)
            } else if let singleObs = observations.first {
                let wristX = (try? singleObs.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                let chirality: UInt32 = (wristX >= 0.5) ? 1 : 0
                if chirality == 1 {
                    newRight = extract21Joints(from: singleObs, chirality: 1)
                } else {
                    newLeft = extract21Joints(from: singleObs, chirality: 0)
                }
            }
        }

        let gcMgr = GameControllerManager.shared
        let leftInput = gcMgr.getInputData(for: 0)
        let rightInput = gcMgr.getInputData(for: 1)

        let isExpFinger = VRSettingsManager.shared.isFingerTrackingExperimentalEnabled

        // 左手データ統合
        if newLeft == nil {
            var leftDummy = createDefaultHandData(chirality: 0)
            leftDummy.controller = leftInput
            leftDummy.isTracked = 1
            if leftInput.isConnected == 1 {
                leftDummy.curls = generateControllerCurls(input: leftInput, isLeft: true)
                leftDummy.splays = generateControllerSplays(input: leftInput, isLeft: true)
            }
            newLeft = leftDummy
        } else {
            newLeft?.controller = leftInput
        }

        // 右手データ統合
        if newRight == nil {
            var rightDummy = createDefaultHandData(chirality: 1)
            rightDummy.controller = rightInput
            rightDummy.isTracked = 1
            if rightInput.isConnected == 1 {
                rightDummy.curls = generateControllerCurls(input: rightInput, isLeft: false)
                rightDummy.splays = generateControllerSplays(input: rightInput, isLeft: false)
            }
            newRight = rightDummy
        } else {
            newRight?.controller = rightInput
        }

        if var left = newLeft {
            applySmartControllerOverride(handData: &left, input: leftInput, isLeft: true, isExpFinger: isExpFinger)
            newLeft = left
        }

        if var right = newRight {
            applySmartControllerOverride(handData: &right, input: rightInput, isLeft: false, isExpFinger: isExpFinger)
            newRight = right
        }

        DispatchQueue.main.async {
            self.leftHandData = newLeft
            self.rightHandData = newRight
        }

        onTrackingDataUpdated?(headPosition, headRotation, newLeft, newRight)
    }

    /// Joy-Con優先制御および実験的フィンガートラッキングの適用
    private func applySmartControllerOverride(
        handData: inout HandPacketData,
        input: ControllerInputData,
        isLeft: Bool,
        isExpFinger: Bool
    ) {
        if input.isConnected == 1 {
            // Joy-Con接続時：物理操作を最優先
            handData.isPinching = 0
            handData.pinchDistance = 1.0

            let cRot = input.controllerRot
            if (cRot.w != 1.0 || cRot.x != 0.0 || cRot.y != 0.0 || cRot.z != 0.0) && (cRot.w != 0.0 || cRot.x != 0.0 || cRot.y != 0.0 || cRot.z != 0.0) {
                handData.joints.0.orientation = cRot
            }

            if !isExpFinger {
                handData.curls = generateControllerCurls(input: input, isLeft: isLeft)
                handData.splays = generateControllerSplays(input: input, isLeft: isLeft)
            }
        } else {
            // Joy-Con非接続時（ハンドトラッキング単体）
            if !isExpFinger {
                if handData.isPinching == 1 {
                    handData.curls.thumb = 0.70
                    handData.curls.index = 0.75
                    handData.curls.middle = 0.20
                    handData.curls.ring = 0.20
                    handData.curls.pinky = 0.20
                } else if handData.curls.middle > 0.65 && handData.curls.ring > 0.65 {
                    handData.curls.thumb = 0.80
                    handData.curls.index = 0.85
                    handData.curls.middle = 0.90
                    handData.curls.ring = 0.90
                    handData.curls.pinky = 0.90
                }
            }
        }
    }

    private func generateControllerCurls(input: ControllerInputData, isLeft: Bool) -> FingerCurls {
        var curls = FingerCurls()
        curls.index = input.triggerValue
        let grip = input.gripValue
        curls.middle = grip
        curls.ring = grip
        curls.pinky = grip

        let isThumbBusy = (input.buttonMask != 0) || (abs(input.stickX) > 0.08) || (abs(input.stickY) > 0.08)
        curls.thumb = isThumbBusy ? 0.65 : 0.15
        return curls
    }

    private func generateControllerSplays(input: ControllerInputData, isLeft: Bool) -> FingerSplays {
        var splays = FingerSplays()
        splays.thumb = isLeft ? -0.15 : 0.15
        splays.index = isLeft ? -0.05 : 0.05
        splays.middle = 0.0
        splays.ring = isLeft ? 0.05 : -0.05
        splays.pinky = isLeft ? 0.10 : -0.10
        return splays
    }

    private func createDefaultHandData(chirality: UInt32) -> HandPacketData {
        let isLeft = (chirality == 0)
        let defaultPos = Vector3f(
            x: isLeft ? -0.18 : 0.18,
            y: -0.15,
            z: -0.45
        )
        let wristBone = BoneTransform(position: defaultPos, orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let tupleJoints = (
            wristBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone, dummyBone
        )
        return HandPacketData(
            chirality: chirality,
            isTracked: 0,
            isPinching: 0,
            pinchDistance: 1.0,
            curls: FingerCurls(),
            splays: FingerSplays(),
            joints: tupleJoints,
            controller: ControllerInputData()
        )
    }

    private func extract21Joints(from observation: VNHumanHandPoseObservation, chirality: UInt32) -> HandPacketData? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all),
              let wristPoint = recognizedPoints[.wrist] else { return nil }

        let isLeft = (chirality == 0)

        // 1. ピンチ判定
        var isPinching: UInt32 = 0
        var pinchDist: Float = 1.0
        var currentPinchState = isLeft ? isLeftPinchingState : isRightPinchingState

        if let thumbTip = recognizedPoints[.thumbTip], let indexTip = recognizedPoints[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx * dx + dy * dy)

            if currentPinchState {
                if pinchDist > 0.080 { currentPinchState = false }
            } else {
                if pinchDist < 0.050 { currentPinchState = true }
            }

            if isLeft {
                isLeftPinchingState = currentPinchState
            } else {
                isRightPinchingState = currentPinchState
            }
            isPinching = currentPinchState ? 1 : 0
        }

        // 2. 光学逆投影と動的Depthによるカメラローカル3D位置（Position）の算出
        let wx = Float(wristPoint.location.x)
        let wy = Float(wristPoint.location.y)

        // 手のひらサイズからカメラからの奥行き距離（Depth: 0.25m〜0.85m）を動的実測
        var palmScale: Float = 0.15
        if let midMCP = recognizedPoints[.middleMCP] {
            let pdx = Float(midMCP.location.x) - wx
            let pdy = Float(midMCP.location.y) - wy
            palmScale = max(0.04, hypot(pdx, pdy))
        }
        let dynamicDepth: Float = max(0.25, min(0.85, 0.065 / palmScale))

        // カメラローカル座標系 (X: 右, Y: 上, Z: 前方マイナス)
        let fovFactor: Float = 1.15
        let localX: Float = (wx - 0.5) * dynamicDepth * fovFactor + (isLeft ? -0.05 : 0.05)
        let localY: Float = (wy - 0.5) * dynamicDepth * fovFactor - 0.05
        let localZ: Float = -dynamicDepth

        let rawLocalPos = SIMD3<Float>(localX, localY, localZ)
        let posAlpha: Float = 0.65
        let prevPos = isLeft ? prevLeftLocalPos : prevRightLocalPos
        let smoothLocalPos = prevPos * (1.0 - posAlpha) + rawLocalPos * posAlpha
        if isLeft { prevLeftLocalPos = smoothLocalPos } else { prevRightLocalPos = smoothLocalPos }

        // 3. 手のひら3軸直交基底による手首ローカル3D回転（Rotation）の算出
        var wristQuat = Quaternionf(w: 1, x: 0, y: 0, z: 0)

        let midMCP = recognizedPoints[.middleMCP]
        let idxMCP = recognizedPoints[.indexMCP]
        let litMCP = recognizedPoints[.littleMCP]

        if let mid = midMCP, let idx = idxMCP, let lit = litMCP {
            // 前方ベクトル: 手首 -> 中指付け根
            let fwdX = Float(mid.location.x) - wx
            let fwdY = Float(mid.location.y) - wy
            let fwdLen = max(0.001, hypot(fwdX, fwdY))
            let vFwd = SIMD3<Float>(fwdX / fwdLen, fwdY / fwdLen, -0.25)

            // 横ベクトル: 人差し指MCP -> 小指MCP
            let rX = Float(lit.location.x - idx.location.x)
            let rY = Float(lit.location.y - idx.location.y)
            let rLen = max(0.001, hypot(rX, rY))
            let vRight = SIMD3<Float>((isLeft ? -rX : rX) / rLen, (isLeft ? -rY : rY) / rLen, 0.20)

            // 法線ベクトル (外積)
            let vUp = simd_normalize(simd_cross(vRight, vFwd))
            let vFwdOrtho = simd_normalize(simd_cross(vUp, vRight))
            let vRightOrtho = simd_normalize(simd_cross(vFwdOrtho, vUp))

            let rotMatrix = simd_float3x3(
                columns: (
                    SIMD3<Float>(vRightOrtho.x, vRightOrtho.y, vRightOrtho.z),
                    SIMD3<Float>(vUp.x, vUp.y, vUp.z),
                    SIMD3<Float>(vFwdOrtho.x, vFwdOrtho.y, vFwdOrtho.z)
                )
            )
            var currentQuat = simd_quatf(rotMatrix)
            if currentQuat.real.isNaN || currentQuat.imag.x.isNaN {
                currentQuat = simd_quatf(real: 1, imag: .zero)
            }

            let prevQuat = isLeft ? prevLeftLocalQuat : prevRightLocalQuat
            let smoothQuat = simd_slerp(prevQuat, currentQuat, 0.50)
            if isLeft { prevLeftLocalQuat = smoothQuat } else { prevRightLocalQuat = smoothQuat }

            wristQuat = Quaternionf(
                w: smoothQuat.real,
                x: smoothQuat.imag.x,
                y: smoothQuat.imag.y,
                z: smoothQuat.imag.z
            )
        }

        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        var bones = Array(repeating: dummyBone, count: 21)

        // bones[0] にカメラローカルな手首相対位置と相対姿勢を格納
        bones[0] = BoneTransform(
            position: Vector3f(x: smoothLocalPos.x, y: smoothLocalPos.y, z: smoothLocalPos.z),
            orientation: wristQuat
        )

        let fingerJointKeys: [VNHumanHandPoseObservation.JointName] = [
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        for (idx, key) in fingerJointKeys.enumerated() {
            if let point = recognizedPoints[key] {
                let relX = Float(point.location.x - wristPoint.location.x) * Float(0.20)
                let relY = Float(point.location.y - wristPoint.location.y) * Float(0.20)
                let relZ = Float(0.0)

                bones[idx + 1] = BoneTransform(
                    position: Vector3f(x: relX, y: relY, z: relZ),
                    orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
                )
            }
        }

        // 4. 幾何学的関節屈曲角による実用Curl計算
        let computeGeometricCurl = { (mcpKey: VNHumanHandPoseObservation.JointName,
                                      pipKey: VNHumanHandPoseObservation.JointName,
                                      dipKey: VNHumanHandPoseObservation.JointName,
                                      tipKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let mcp = recognizedPoints[mcpKey],
                  let pip = recognizedPoints[pipKey],
                  let dip = recognizedPoints[dipKey],
                  let tip = recognizedPoints[tipKey] else { return 0.0 }

            let v1 = SIMD2<Float>(Float(pip.location.x - mcp.location.x), Float(pip.location.y - mcp.location.y))
            let v2 = SIMD2<Float>(Float(dip.location.x - pip.location.x), Float(dip.location.y - pip.location.y))
            let v3 = SIMD2<Float>(Float(tip.location.x - dip.location.x), Float(tip.location.y - dip.location.y))

            let len1 = max(0.0001, hypot(v1.x, v1.y))
            let len2 = max(0.0001, hypot(v2.x, v2.y))
            let len3 = max(0.0001, hypot(v3.x, v3.y))

            let dot1 = max(-1.0, min(1.0, (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)))
            let dot2 = max(-1.0, min(1.0, (v2.x * v3.x + v2.y * v3.y) / (len2 * len3)))

            let totalAngle = acos(dot1) + acos(dot2)
            let normalizedCurl = totalAngle / (Float.pi * 0.85)
            return max(0.0, min(1.0, normalizedCurl))
        }

        let computeGeometricThumbCurl = { () -> Float in
            guard let cmc = recognizedPoints[.thumbCMC],
                  let mp = recognizedPoints[.thumbMP],
                  let ip = recognizedPoints[.thumbIP],
                  let tip = recognizedPoints[.thumbTip],
                  let idxMCP = recognizedPoints[.indexMCP] else { return 0.0 }

            let v1 = SIMD2<Float>(Float(mp.location.x - cmc.location.x), Float(mp.location.y - cmc.location.y))
            let v2 = SIMD2<Float>(Float(ip.location.x - mp.location.x), Float(ip.location.y - mp.location.y))
            let v3 = SIMD2<Float>(Float(tip.location.x - ip.location.x), Float(tip.location.y - ip.location.y))

            let len1 = max(0.0001, hypot(v1.x, v1.y))
            let len2 = max(0.0001, hypot(v2.x, v2.y))
            let len3 = max(0.0001, hypot(v3.x, v3.y))

            let dot1 = max(-1.0, min(1.0, (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)))
            let dot2 = max(-1.0, min(1.0, (v2.x * v3.x + v2.y * v3.y) / (len2 * len3)))

            let angle = acos(dot1) + acos(dot2)
            let distToIndex = hypot(Float(tip.location.x - idxMCP.location.x), Float(tip.location.y - idxMCP.location.y))
            let opposition = max(0.0, min(1.0, (0.16 - distToIndex) / 0.10))

            let rawCurl = (angle / (Float.pi * 0.70)) * 0.6 + opposition * 0.4
            return max(0.0, min(1.0, rawCurl))
        }

        var rawCurls = FingerCurls()
        rawCurls.thumb = computeGeometricThumbCurl()
        rawCurls.index = computeGeometricCurl(.indexMCP, .indexPIP, .indexDIP, .indexTip)
        rawCurls.middle = computeGeometricCurl(.middleMCP, .middlePIP, .middleDIP, .middleTip)
        rawCurls.ring = computeGeometricCurl(.ringMCP, .ringPIP, .ringDIP, .ringTip)
        rawCurls.pinky = computeGeometricCurl(.littleMCP, .littlePIP, .littleDIP, .littleTip)

        let prevC = isLeft ? prevLeftCurls : prevRightCurls
        let cAlpha: Float = 0.60
        let smoothCurls = FingerCurls(
            thumb: prevC.thumb * (1 - cAlpha) + rawCurls.thumb * cAlpha,
            index: prevC.index * (1 - cAlpha) + rawCurls.index * cAlpha,
            middle: prevC.middle * (1 - cAlpha) + rawCurls.middle * cAlpha,
            ring: prevC.ring * (1 - cAlpha) + rawCurls.ring * cAlpha,
            pinky: prevC.pinky * (1 - cAlpha) + rawCurls.pinky * cAlpha
        )
        if isLeft { prevLeftCurls = smoothCurls } else { prevRightCurls = smoothCurls }

        // 5. 各指のSplay（開き）計算
        let computeFingerSplay = { (tipKey: VNHumanHandPoseObservation.JointName, mcpKey: VNHumanHandPoseObservation.JointName, refMcpKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let tip = recognizedPoints[tipKey], let mcp = recognizedPoints[mcpKey], let ref = recognizedPoints[refMcpKey] else { return 0.0 }
            let dx = Float(tip.location.x - mcp.location.x)
            let refDx = Float(ref.location.x - mcp.location.x)
            let splay = (isLeft ? -1.0 : 1.0) * ((dx - refDx) * 5.0)
            return max(-1.0, min(1.0, splay))
        }

        var splays = FingerSplays()
        splays.thumb = isLeft ? -0.2 : 0.2
        splays.index = computeFingerSplay(.indexTip, .indexMCP, .middleMCP)
        splays.middle = 0.0
        splays.ring = computeFingerSplay(.ringTip, .ringMCP, .middleMCP)
        splays.pinky = computeFingerSplay(.littleTip, .littleMCP, .middleMCP)

        let tupleJoints = (
            bones[0], bones[1], bones[2], bones[3], bones[4],
            bones[5], bones[6], bones[7], bones[8], bones[9],
            bones[10], bones[11], bones[12], bones[13], bones[14],
            bones[15], bones[16], bones[17], bones[18], bones[19], bones[20]
        )

        let controllerInput = GameControllerManager.shared.getInputData(for: chirality)

        return HandPacketData(
            chirality: chirality,
            isTracked: 1,
            isPinching: isPinching,
            pinchDistance: pinchDist,
            curls: smoothCurls,
            splays: splays,
            joints: tupleJoints,
            controller: controllerInput
        )
    }
}



