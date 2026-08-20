import Foundation
import GameController
import Combine

class GameControllerManager: ObservableObject {
    static let shared = GameControllerManager()

    @Published var isConnected: Bool = false
    @Published var connectedControllersCount: Int = 0
    @Published var controllerStatusDescription: String = "No Controller Connected"

    private var leftController: GCController?
    private var rightController: GCController?
    private var primaryController: GCController?

    init() {
        setupObservers()
        refreshControllers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    @objc private func controllerDidConnect(_ notification: Notification) {
        refreshControllers()
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        refreshControllers()
    }

    func refreshControllers() {
        let controllers = GCController.controllers()
        DispatchQueue.main.async {
            self.connectedControllersCount = controllers.count
            self.isConnected = !controllers.isEmpty

            if controllers.isEmpty {
                self.controllerStatusDescription = "No Gamepad Connected (Hand Tracking Mode)"
                self.leftController = nil
                self.rightController = nil
                self.primaryController = nil
                return
            }

            self.leftController = nil
            self.rightController = nil
            self.primaryController = controllers.first

            var names: [String] = []

            for controller in controllers {
                let vendor = controller.vendorName ?? "Gamepad"
                names.append(vendor)

                // Nintendo Switch Joy-Con (L) / (R) の自動判別
                if vendor.lowercased().contains("joy-con (l)") || vendor.lowercased().contains("left") {
                    self.leftController = controller
                } else if vendor.lowercased().contains("joy-con (r)") || vendor.lowercased().contains("right") {
                    self.rightController = controller
                }
            }

            // 単一コントローラー (Pro-Con, Xbox, PS, MFi) の場合
            if self.leftController == nil && self.rightController == nil, let mainCtrl = self.primaryController {
                self.rightController = mainCtrl // 右手をメイン操作に
            }

            self.controllerStatusDescription = "Connected: " + names.joined(separator: ", ")
        }
    }

    func getInputData(for chirality: UInt8) -> ControllerInputData {
        var inputData = ControllerInputData()

        let targetController: GCController?
        if chirality == 0 {
            // Left Hand
            targetController = leftController ?? primaryController
        } else {
            // Right Hand
            targetController = rightController ?? primaryController
        }

        guard let controller = targetController, controller.isAttachedToDevice || true else {
            inputData.isConnected = 0
            return inputData
        }

        inputData.isConnected = 1
        var mask: UInt32 = 0

        // Extended Gamepad 入力取得
        if let gamepad = controller.extendedGamepad {
            // Buttons
            if gamepad.buttonA.isPressed { mask |= ControllerButtonBits.btnAorX }
            if gamepad.buttonB.isPressed { mask |= ControllerButtonBits.btnBorY }
            if gamepad.buttonX.isPressed { mask |= ControllerButtonBits.btnXorPlus }
            if gamepad.buttonY.isPressed { mask |= ControllerButtonBits.btnYorMinus }

            // Triggers & Shoulders
            if chirality == 0 {
                // Left
                if gamepad.leftShoulder.isPressed { mask |= ControllerButtonBits.btnGripClick }
                if gamepad.leftTrigger.isPressed { mask |= ControllerButtonBits.btnTriggerClick }
                inputData.triggerValue = Float(gamepad.leftTrigger.value)
                inputData.gripValue = gamepad.leftShoulder.isPressed ? 1.0 : 0.0

                inputData.stickX = Float(gamepad.leftThumbstick.xAxis.value)
                inputData.stickY = Float(gamepad.leftThumbstick.yAxis.value)
                if let leftStickButton = gamepad.leftThumbstickButton, leftStickButton.isPressed {
                    mask |= ControllerButtonBits.btnThumbstickClick
                }
            } else {
                // Right
                if gamepad.rightShoulder.isPressed { mask |= ControllerButtonBits.btnGripClick }
                if gamepad.rightTrigger.isPressed { mask |= ControllerButtonBits.btnTriggerClick }
                inputData.triggerValue = Float(gamepad.rightTrigger.value)
                inputData.gripValue = gamepad.rightShoulder.isPressed ? 1.0 : 0.0

                inputData.stickX = Float(gamepad.rightThumbstick.xAxis.value)
                inputData.stickY = Float(gamepad.rightThumbstick.yAxis.value)
                if let rightStickButton = gamepad.rightThumbstickButton, rightStickButton.isPressed {
                    mask |= ControllerButtonBits.btnThumbstickClick
                }
            }

            // D-Pad
            if gamepad.dpad.up.isPressed { mask |= ControllerButtonBits.btnDpadUp }
            if gamepad.dpad.down.isPressed { mask |= ControllerButtonBits.btnDpadDown }
            if gamepad.dpad.left.isPressed { mask |= ControllerButtonBits.btnDpadLeft }
            if gamepad.dpad.right.isPressed { mask |= ControllerButtonBits.btnDpadRight }

            // Menu / System
            if gamepad.buttonMenu.isPressed {
                mask |= ControllerButtonBits.btnSystem
            }
            if let buttonOptions = gamepad.buttonOptions, buttonOptions.isPressed {
                mask |= ControllerButtonBits.btnSystem
            }
        }

        inputData.buttonMask = mask

        // IMU / Motion 姿勢取得
        if let motion = controller.motion {
            let attitude = motion.attitude
            inputData.controllerRot = Quaternionf(
                w: Float(attitude.w),
                x: Float(attitude.x),
                y: Float(attitude.y),
                z: Float(attitude.z)
            )
        }

        return inputData
    }
}