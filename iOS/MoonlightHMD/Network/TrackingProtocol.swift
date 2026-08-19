import Foundation

struct Vector3f {
    var x: Float
    var y: Float
    var z: Float
}

struct Quaternionf {
    var w: Float
    var x: Float
    var y: Float
    var z: Float
}

struct BoneTransform {
    var position: Vector3f
    var orientation: Quaternionf
}

typealias HandJointsTuple = (
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
    BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform
)

struct HandPacketData {
    var chirality: UInt8
    var isTracked: UInt8
    var isPinching: UInt8
    var pinchDistance: Float
    var joints: HandJointsTuple
}
