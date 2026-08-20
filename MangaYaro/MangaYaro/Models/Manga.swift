import Foundation
import SwiftUI

/// マンガの作品情報モデル
public struct Manga: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let author: String
    public let coverImageName: String
    public let summary: String
    public let tags: [String]
    public let chapters: [Chapter]
    public var lastReadChapterId: String?
    public var lastReadPageIndex: Int?
    public var isFavorite: Bool
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        author: String,
        coverImageName: String,
        summary: String,
        tags: [String] = [],
        chapters: [Chapter] = [],
        lastReadChapterId: String? = nil,
        lastReadPageIndex: Int? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageName = coverImageName
        self.summary = summary
        self.tags = tags
        self.chapters = chapters
        self.lastReadChapterId = lastReadChapterId
        self.lastReadPageIndex = lastReadPageIndex
        self.isFavorite = isFavorite
    }
    
    /// 全体進捗率（0.0 ~ 1.0）
    public var overallProgress: Double {
        guard !chapters.isEmpty else { return 0.0 }
        let readCount = chapters.filter { $0.isRead }.count
        return Double(readCount) / Double(chapters.count)
    }
}
