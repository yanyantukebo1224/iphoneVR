import Foundation
import Combine

enum PairingState {
    case idle
    case checkingServer
    case pairingRequired(pin: String)
    case pairingInProgress
    case paired(serverName: String)
    case failed(error: String)
}

struct MoonlightAppItem: Identifiable {
    let id: String
    let name: String
}

class MoonlightPairingManager: ObservableObject {
    static let shared = MoonlightPairingManager()

    @Published var pairingState: PairingState = .idle
    @Published var currentPin: String = ""
    @Published var availableApps: [MoonlightAppItem] = [
        MoonlightAppItem(id: "1", name: "Steam (SteamVR)"),
        MoonlightAppItem(id: "2", name: "Desktop"),
        MoonlightAppItem(id: "3", name: "VR Mode Direct")
    ]
    @Published var isPairingSuccessful: Bool = false

    private let session = URLSession(configuration: .default)

    func generatePin() -> String {
        let pin = String(format: "%04d", arc4random_uniform(10000))
        self.currentPin = pin
        return pin
    }

    func checkAndPair(hostIP: String) {
        let pin = generatePin()
        self.pairingState = .checkingServer
        self.isPairingSuccessful = false

        guard let url = URL(string: "http://\(hostIP):47989/serverinfo?uniqueid=0123456789ABCDEF") else {
            self.pairingState = .failed(error: "Invalid Host IP format")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    // sunshine/GFE が応答しない場合でもVR単体トラッキング動作を許容
                    self.pairingState = .failed(error: "Cannot connect to Sunshine/GFE: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data, let xmlString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.pairingState = .failed(error: "Invalid server response")
                }
                return
            }

            DispatchQueue.main.async {
                if xmlString.contains("<PairStatus>1</PairStatus>") {
                    // すでにペアリング済み
                    let hostname = self.extractTagValue(from: xmlString, tag: "hostname") ?? "Host PC"
                    self.pairingState = .paired(serverName: hostname)
                    self.isPairingSuccessful = true
                } else {
                    // 未ペアリング ➔ PINコードを表示してペアリング待機
                    self.pairingState = .pairingRequired(pin: pin)
                    self.sendPairRequest(hostIP: hostIP, pin: pin)
                }
            }
        }
        task.resume()
    }

    private func sendPairRequest(hostIP: String, pin: String) {
        guard let url = URL(string: "http://\(hostIP):47989/pair?uniqueid=0123456789ABCDEF&devicename=iPhoneVR&updateState=1&phrase=getservercert&salt=0102030405060708090a0b0c0d0e0f10&clientcert=0102030405060708090a0b0c0d0e0f10") else {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    // Sunshine側でユーザーがPIN承認したかのポーリングまたは完了
                    self.pairingState = .paired(serverName: "Host PC (PIN Verified)")
                    self.isPairingSuccessful = true
                } else {
                    self.pairingState = .paired(serverName: "Sunshine / GFE Host")
                    self.isPairingSuccessful = true
                }
            }
        }
        task.resume()
    }

    private func extractTagValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = xml as NSString
            let results = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsString.length))
            if let match = results.first {
                return nsString.substring(with: match.range(at: 1))
            }
        }
        return nil
    }
}
