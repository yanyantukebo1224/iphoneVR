import Foundation
import Combine

enum HandGestureType {
    case none
    case pinchStart
    case pinching
    case pinchRelease
    case pointing
}

class HandGestureProcessor: ObservableObject {
    @Published var leftGesture: HandGestureType = .none
    @Published var rightGesture: HandGestureType = .none

    private var wasLeftPinching = false
    private var wasRightPinching = false

    func processHandState(leftHand: HandPacketData?, rightHand: HandPacketData?) {
        leftGesture = updateGestureState(hand: leftHand, wasPinching: &wasLeftPinching)
        rightGesture = updateGestureState(hand: rightHand, wasPinching: &wasRightPinching)
    }

    private func updateGestureState(hand: HandPacketData?, wasPinching: inout Bool) -> HandGestureType {
        guard let hand = hand, hand.isTracked == 1 else {
            wasPinching = false
            return .none
        }

        let isPinchingNow = (hand.isPinching == 1)

        if isPinchingNow && !wasPinching {
            wasPinching = true
            return .pinchStart
        } else if isPinchingNow && wasPinching {
            return .pinching
        } else if !isPinchingNow && wasPinching {
            wasPinching = false
            return .pinchRelease
        }

        return .none
    }
}
