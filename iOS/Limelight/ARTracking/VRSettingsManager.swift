import Foundation
import Combine

class VRSettingsManager: ObservableObject {
    static let shared = VRSettingsManager()

    @Published var isVRModeEnabled: Bool {
        didSet { UserDefaults.standard.set(isVRModeEnabled, forKey: "vr_mode_enabled") }
    }
    @Published var isHandTrackingEnabled: Bool {
        didSet { UserDefaults.standard.set(isHandTrackingEnabled, forKey: "vr_hand_tracking_enabled") }
    }
    @Published var targetIP: String {
        didSet { UserDefaults.standard.set(targetIP, forKey: "vr_target_ip") }
    }
    @Published var udpPort: String {
        didSet { UserDefaults.standard.set(udpPort, forKey: "vr_udp_port") }
    }
    @Published var handSensitivity: Float {
        didSet { UserDefaults.standard.set(handSensitivity, forKey: "vr_hand_sensitivity") }
    }

    private init() {
        self.isVRModeEnabled = UserDefaults.standard.object(forKey: "vr_mode_enabled") as? Bool ?? true
        self.isHandTrackingEnabled = UserDefaults.standard.object(forKey: "vr_hand_tracking_enabled") as? Bool ?? true
        self.targetIP = UserDefaults.standard.string(forKey: "vr_target_ip") ?? "192.168.0.13"
        self.udpPort = UserDefaults.standard.string(forKey: "vr_udp_port") ?? "9050"
        self.handSensitivity = UserDefaults.standard.float(forKey: "vr_hand_sensitivity") == 0 ? 1.0 : UserDefaults.standard.float(forKey: "vr_hand_sensitivity")
    }
}
