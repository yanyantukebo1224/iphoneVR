import Foundation

/// ネットワークAPIリクエストのレート制限を司るアクター
/// リクエスト間隔を最小250msに固定し、5req/s超過を防止する
public actor RateLimiter {
    private let minIntervalNanoseconds: UInt64
    private var lastRequestTime: DispatchTime = .now()
    
    public init(minIntervalSeconds: Double = 0.25) { // 250ms
        self.minIntervalNanoseconds = UInt64(minIntervalSeconds * 1_000_000_000)
    }
    
    /// リクエスト送信前に呼び出す。必要な待機時間を非同期で休止する。
    public func waitIfNeeded() async {
        let now = DispatchTime.now()
        let nanoSinceLast = now.uptimeNanoseconds - lastRequestTime.uptimeNanoseconds
        
        if nanoSinceLast < minIntervalNanoseconds {
            let sleepTime = minIntervalNanoseconds - nanoSinceLast
            try? await Task.sleep(nanoseconds: sleepTime)
        }
        lastRequestTime = DispatchTime.now()
    }
}
