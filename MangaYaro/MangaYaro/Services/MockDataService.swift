import Foundation

/// アプリ全体のデモ用高精度モックデータ供給サービス
public class MockDataService {
    public static let shared = MockDataService()
    
    public var sampleMangas: [Manga] = []
    
    private init() {
        self.sampleMangas = generateSampleData()
    }
    
    private func generateSampleData() -> [Manga] {
        let manga1Pages = (1...18).map { Page(pageIndex: $0, imageName: "book.fill") }
        let manga1Chapters = [
            Chapter(chapterNumber: 12, title: "第12話: 新たなる試練", pageCount: 18, isRead: false, downloadState: .downloaded, pages: manga1Pages),
            Chapter(chapterNumber: 11, title: "第11話: 漆黒の翼", pageCount: 20, isRead: true, downloadState: .downloaded, pages: manga1Pages),
            Chapter(chapterNumber: 10, title: "第10話: 誓いの言葉", pageCount: 16, isRead: true, downloadState: .notDownloaded, pages: manga1Pages),
            Chapter(chapterNumber: 9, title: "第9話: 秘密の鍵", pageCount: 22, isRead: true, downloadState: .notDownloaded, pages: manga1Pages),
            Chapter(chapterNumber: 8, title: "第8話: 嵐の前の静けさ", pageCount: 19, isRead: true, downloadState: .notDownloaded, pages: manga1Pages),
        ]
        
        let manga1 = Manga(
            id: "manga-1",
            title: "Cyber Frontier (サイバー・フロンティア)",
            author: "ネオ・TOKYO",
            coverImageName: "sparkles",
            summary: "近未来のサイバーパンク都市を舞台に、電脳世界の深淵に挑むハッカー少女の戦いを描くスタイリッシュSFアクション！",
            tags: ["SF", "アクション", "サイバーパンク", "完結間近"],
            chapters: manga1Chapters,
            lastReadChapterId: manga1Chapters[0].id,
            lastReadPageIndex: 3,
            isFavorite: true
        )
        
        let manga2Pages = (1...24).map { Page(pageIndex: $0, imageName: "flame.fill") }
        let manga2Chapters = [
            Chapter(chapterNumber: 45, title: "第45話: 限界突破の炎", pageCount: 24, isRead: false, downloadState: .downloading, pages: manga2Pages),
            Chapter(chapterNumber: 44, title: "第44話: 師匠の教え", pageCount: 20, isRead: true, downloadState: .downloaded, pages: manga2Pages),
            Chapter(chapterNumber: 43, title: "第43話: 宿敵との再会", pageCount: 22, isRead: true, downloadState: .downloaded, pages: manga2Pages),
        ]
        
        let manga2 = Manga(
            id: "manga-2",
            title: "炎の錬金騎士団",
            author: "火ノ宮 炎太",
            coverImageName: "flame.fill",
            summary: "世界を焼き尽くす魔王を倒すため、ちっぽけな熱意と無敵の剣技で駆け抜ける熱血王道ファンタジー！",
            tags: ["ファンタジー", "王道", "バトル", "人気急上昇"],
            chapters: manga2Chapters,
            lastReadChapterId: manga2Chapters[0].id,
            lastReadPageIndex: 10,
            isFavorite: true
        )
        
        let manga3Pages = (1...16).map { Page(pageIndex: $0, imageName: "leaf.fill") }
        let manga3Chapters = [
            Chapter(chapterNumber: 5, title: "第5話: 雨上がりのカフェテラス", pageCount: 16, isRead: false, downloadState: .notDownloaded, pages: manga3Pages),
            Chapter(chapterNumber: 4, title: "第4話: 木漏れ日のスケッチ", pageCount: 16, isRead: false, downloadState: .notDownloaded, pages: manga3Pages),
        ]
        
        let manga3 = Manga(
            id: "manga-3",
            title: "コモレビ・デイズ -日常の欠片-",
            author: "風間 すず",
            coverImageName: "leaf.fill",
            summary: "静かな田舎町の古民家カフェで繰り広げられる、心温まるスローライフ・日常ショートストーリー。",
            tags: ["日常", "ほのぼの", "癒やし", "Webtoon"],
            chapters: manga3Chapters,
            lastReadChapterId: nil,
            lastReadPageIndex: nil,
            isFavorite: false
        )
        
        return [manga1, manga2, manga3]
    }
}
