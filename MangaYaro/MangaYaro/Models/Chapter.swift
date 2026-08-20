import Foundation

/// チャプター（話数）のモデル
public struct Chapter: Identifiable, Hashable, Codable {
    public let id: String
    public let chapterNumber: Int
    public let title: String
    public let pageCount: Int
    public var isRead: Bool
    public var downloadState: DownloadState
    public let pages: [Page]
    
    public enum DownloadState: String, Codable, Hashable {
        case notDownloaded
        case downloading
        case downloaded
    }
    
    public init(
        id: String = UUID().uuidString,
        chapterNumber: Int,
        title: String,
        pageCount: Int,
        isRead: Bool = false,
        downloadState: DownloadState = .notDownloaded,
        pages: [Page] = []
    ) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.title = title
        self.pageCount = pageCount
        self.isRead = isRead
        self.downloadState = downloadState
        self.pages = pages
    }
}
