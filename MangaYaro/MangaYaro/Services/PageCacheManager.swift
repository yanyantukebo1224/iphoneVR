import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 先読みスライディングウィンドウとキャッシュメモリ管理を行うActor
public actor PageCacheManager {
    public static let shared = PageCacheManager()
    
    #if canImport(UIKit)
    private var memoryCache: [String: UIImage] = [:]
    #else
    private var memoryCache: [String: Data] = [:]
    #endif
    
    private var accessHistory: [String] = []
    private var activePrefetchTasks: [String: Task<Void, Never>] = [:]
    private let rateLimiter = RateLimiter(minIntervalSeconds: 0.25)
    
    /// 設定可能な最大キャッシュアイテム数
    public var maxCacheCount: Int = 30
    /// 先読みウィンドウサイズ（現在のページの前後枚数）
    public var prefetchWindowSize: Int = 3
    
    private init() {}
    
    /// キャッシュキーの生成
    private func cacheKey(chapterId: String, pageIndex: Int) -> String {
        return "\(chapterId)_\(pageIndex)"
    }
    
    #if canImport(UIKit)
    public func getImage(chapterId: String, pageIndex: Int) -> UIImage? {
        let key = cacheKey(chapterId: chapterId, pageIndex: pageIndex)
        if let image = memoryCache[key] {
            touchKey(key)
            return image
        }
        return nil
    }
    
    public func storeImage(_ image: UIImage, chapterId: String, pageIndex: Int) {
        let key = cacheKey(chapterId: chapterId, pageIndex: pageIndex)
        memoryCache[key] = image
        touchKey(key)
        trimCacheIfNeeded()
    }
    #else
    public func getData(chapterId: String, pageIndex: Int) -> Data? {
        let key = cacheKey(chapterId: chapterId, pageIndex: pageIndex)
        if let data = memoryCache[key] {
            touchKey(key)
            return data
        }
        return nil
    }
    
    public func storeData(_ data: Data, chapterId: String, pageIndex: Int) {
        let key = cacheKey(chapterId: chapterId, pageIndex: pageIndex)
        memoryCache[key] = data
        touchKey(key)
        trimCacheIfNeeded()
    }
    #endif
    
    /// 現在のページ位置に合わせてスライディングウィンドウで前後ページを先読みする
    public func updatePrefetchWindow(chapter: Chapter, currentPageIndex: Int) {
        let minIndex = max(0, currentPageIndex - 1)
        let maxIndex = min(chapter.pages.count - 1, currentPageIndex + prefetchWindowSize)
        
        let targetIndices = Array(minIndex...maxIndex)
        let targetKeys = Set(targetIndices.map { cacheKey(chapterId: chapter.id, pageIndex: $0) })
        
        // 範囲外の進行中タスクをキャンセル
        for (key, task) in activePrefetchTasks {
            if !targetKeys.contains(key) {
                task.cancel()
                activePrefetchTasks.removeValue(forKey: key)
            }
        }
        
        // 範囲内の未キャッシュページを非同期取得
        for index in targetIndices {
            let key = cacheKey(chapterId: chapter.id, pageIndex: index)
            guard memoryCache[key] == nil, activePrefetchTasks[key] == nil else { continue }
            
            let page = chapter.pages[index]
            let task = Task {
                await rateLimiter.waitIfNeeded()
                guard !Task.isCancelled else { return }
                
                // 本来のURL fetch または モック処理
                if let url = page.imageURL {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        #if canImport(UIKit)
                        if let image = UIImage(data: data) {
                            self.storeImage(image, chapterId: chapter.id, pageIndex: index)
                        }
                        #else
                        self.storeData(data, chapterId: chapter.id, pageIndex: index)
                        #endif
                    } catch {
                        // エラーハンドリング
                    }
                }
                
                self.removeActiveTask(forKey: key)
            }
            activePrefetchTasks[key] = task
        }
    }
    
    private func removeActiveTask(forKey key: String) {
        activePrefetchTasks.removeValue(forKey: key)
    }
    
    private func touchKey(_ key: String) {
        accessHistory.removeAll { $0 == key }
        accessHistory.append(key)
    }
    
    /// LRUによるキャッシュ即時解放
    private func trimCacheIfNeeded() {
        while memoryCache.count > maxCacheCount, !accessHistory.isEmpty {
            let oldestKey = accessHistory.removeFirst()
            memoryCache.removeValue(forKey: oldestKey)
        }
    }
    
    /// 全キャッシュのクリア
    public func clearAllCache() {
        memoryCache.removeAll()
        accessHistory.removeAll()
        activePrefetchTasks.values.forEach { $0.cancel() }
        activePrefetchTasks.removeAll()
    }
}
