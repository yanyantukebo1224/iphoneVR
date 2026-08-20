import Foundation

struct Vector3f {
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
}

struct Quaternionf {
    var w: Float = 1
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
}

struct BoneTransform {
    var position: Vector3f = Vector3f()
    var orientation: Quaternionf = Quaternionf()
}

struct ControllerButtonBits {
    static let btnAorX: UInt32           = (1 << 0)
    static let btnBorY: UInt32           = (1 << 1)
    static let btnXorPlus: UInt32        = (1 << 2)
    static let btnYorMinus: UInt32       = (1 << 3)
    static let btnTriggerClick: UInt32   = (1 << 4)
    static let btnGripClick: UInt32      = (1 << 5)
    static let btnThumbstickClick: UInt32 = (1 << 6)
    static let btnSystem: UInt32         = (1 << 7)
    static let btnDpadUp: UInt32         = (1 << 8)
    static let btnDpadDown: UInt32       = (1 << 9)
    static let btnDpadLeft: UInt32       = (1 << 10)
    static let btnDpadRight: UInt32      = (1 << 11)
}

struct ControllerInputData {
    var isConnected: UInt32 = 0      // 4 bytes (aligned)
    var buttonMask: UInt32 = 0       // 4 bytes
    var stickX: Float = 0            // 4 bytes
    var stickY: Float = 0            // 4 bytes
    var triggerValue: Float = 0      // 4 bytes
    var gripValue: Float = 0         // 4 bytes
    var controllerRot: Quaternionf = Quaternionf() // 16 bytes
}

struct FingerCurls {
    var thumb: Float = 0
    var index: Float = 0
    var middle: Float = 0
    var ring: Float = 0
    var pinky: Float = 0
}

struct FingerSplays {
    var thumb: Float = 0
    var index: Float = 0
    var middle: Float = 0
    var ring: Float = 0
    var pinky: Float = 0
}

typealias HandJointsTuple = (
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform
)

struct HandPacketData {
    var chirality: UInt32 = 0        // 4 bytes (0 = Left, 1 = Right)
    var isTracked: UInt32 = 0        // 4 bytes
    var isPinching: UInt32 = 0       // 4 bytes
    var pinchDistance: Float = 0     // 4 bytes
    var curls: FingerCurls = FingerCurls()
    var splays: FingerSplays = FingerSplays()
    var joints: HandJointsTuple
    var controller: ControllerInputData = ControllerInputData()
}

struct TrackingPacket {
    var magic: UInt32 = 0x52565049
    var sequence: UInt32 = 0
    var timestamp: Double = 0
    var headPosition: Vector3f = Vector3f()
    var headRotation: Quaternionf = Quaternionf()
    var hands: (HandPacketData, HandPacketData)
}