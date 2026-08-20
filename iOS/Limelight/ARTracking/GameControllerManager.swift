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

    func getInputData(for chirality: UInt32) -> ControllerInputData {
        var inputData = ControllerInputData()
        let controllers = GCController.controllers()
        guard !controllers.isEmpty else {
            inputData.isConnected = 0
            return inputData
        }

        // コントローラーの選択: 2台接続時は 0:Left, 1:Right、1台接続時は両手または該当手
        var selectedController: GCController? = nil
        for ctrl in controllers {
            let name = (ctrl.vendorName ?? "").lowercased()
            if chirality == 0 && (name.contains("joy-con (l)") || name.contains("left")) {
                selectedController = ctrl
                break
            } else if chirality == 1 && (name.contains("joy-con (r)") || name.contains("right")) {
                selectedController = ctrl
                break
            }
        }

        if selectedController == nil {
            if chirality == 0 && controllers.count > 1 {
                selectedController = controllers[0]
            } else if chirality == 1 && controllers.count > 1 {
                selectedController = controllers[1]
            } else {
                selectedController = controllers.first
            }
        }

        guard let controller = selectedController else {
            return inputData
        }

        inputData.isConnected = 1
        var mask: UInt32 = 0

        // 1. ExtendedGamepad
        if let gamepad = controller.extendedGamepad {
            if gamepad.buttonA.isPressed { mask |= ControllerButtonBits.btnAorX }
            if gamepad.buttonB.isPressed { mask |= ControllerButtonBits.btnBorY }
            if gamepad.buttonX.isPressed { mask |= ControllerButtonBits.btnXorPlus }
            if gamepad.buttonY.isPressed { mask |= ControllerButtonBits.btnYorMinus }

            if chirality == 0 {
                // Left
                if gamepad.leftShoulder.isPressed { mask |= ControllerButtonBits.btnGripClick }
                if gamepad.leftTrigger.isPressed { mask |= ControllerButtonBits.btnTriggerClick }
                inputData.triggerValue = Float(gamepad.leftTrigger.value)
                inputData.gripValue = gamepad.leftShoulder.isPressed ? 1.0 : 0.0

                inputData.stickX = Float(gamepad.leftThumbstick.xAxis.value)
                inputData.stickY = Float(gamepad.leftThumbstick.yAxis.value)
                if let stickBtn = gamepad.leftThumbstickButton, stickBtn.isPressed {
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
                if let stickBtn = gamepad.rightThumbstickButton, stickBtn.isPressed {
                    mask |= ControllerButtonBits.btnThumbstickClick
                }
            }

            // D-Pad
            if gamepad.dpad.up.isPressed { mask |= ControllerButtonBits.btnDpadUp }
            if gamepad.dpad.down.isPressed { mask |= ControllerButtonBits.btnDpadDown }
            if gamepad.dpad.left.isPressed { mask |= ControllerButtonBits.btnDpadLeft }
            if gamepad.dpad.right.isPressed { mask |= ControllerButtonBits.btnDpadRight }

            // Menu / System
            if gamepad.buttonMenu.isPressed { mask |= ControllerButtonBits.btnSystem }
            if let opt = gamepad.buttonOptions, opt.isPressed { mask |= ControllerButtonBits.btnSystem }
            if let home = gamepad.buttonHome, home.isPressed { mask |= ControllerButtonBits.btnSystem }
        }

        // 2. PhysicalInputProfile (iOS 14+ 汎用 Switch コントローラー完全対応)
        if #available(iOS 14.0, *) {
            let profile = controller.physicalInputProfile
            for (elementName, element) in profile.elements {
                if let button = element as? GCControllerButtonInput, button.isPressed {
                    let key = elementName.lowercased()
                    if key.contains("buttona") || key.contains("button south") { mask |= ControllerButtonBits.btnAorX }
                    if key.contains("buttonb") || key.contains("button east") { mask |= ControllerButtonBits.btnBorY }
                    if key.contains("buttonx") || key.contains("button west") { mask |= ControllerButtonBits.btnXorPlus }
                    if key.contains("buttony") || key.contains("button north") { mask |= ControllerButtonBits.btnYorMinus }
                    if key.contains("trigger") || key.contains("zl") || key.contains("zr") {
                        mask |= ControllerButtonBits.btnTriggerClick
                        inputData.triggerValue = max(inputData.triggerValue, Float(button.value))
                    }
                    if key.contains("shoulder") || key.contains("button l") || key.contains("button r") || key.contains("sl") || key.contains("sr") {
                        mask |= ControllerButtonBits.btnGripClick
                        inputData.gripValue = 1.0
                    }
                    if key.contains("home") || key.contains("capture") || key.contains("menu") || key.contains("options") || key.contains("minus") || key.contains("plus") || key.contains("share") || key.contains("start") || key.contains("select") {
                        mask |= ControllerButtonBits.btnSystem
                    }
                    if key.contains("thumbstick") || key.contains("stick button") {
                        mask |= ControllerButtonBits.btnThumbstickClick
                    }
                } else if let axis = element as? GCControllerAxisInput {
                    let key = elementName.lowercased()
                    if (key.contains("x") || key.contains("horizontal")) && abs(axis.value) > 0.05 { inputData.stickX = Float(axis.value) }
                    if (key.contains("y") || key.contains("vertical")) && abs(axis.value) > 0.05 { inputData.stickY = Float(axis.value) }
                }
            }
        }

        inputData.buttonMask = mask

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