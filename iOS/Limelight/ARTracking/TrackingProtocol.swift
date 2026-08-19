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
    var isConnected: UInt8 = 0
    var buttonMask: UInt32 = 0
    var stickX: Float = 0
    var stickY: Float = 0
    var triggerValue: Float = 0
    var gripValue: Float = 0
    var controllerRot: Quaternionf = Quaternionf()
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
    var chirality: UInt8 = 0
    var isTracked: UInt8 = 0
    var isPinching: UInt8 = 0
    var pinchDistance: Float = 0
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
