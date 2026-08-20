import Foundation

/// マンガ単一ページのモデル
public struct Page: Identifiable, Hashable, Codable {
    public let id: String
    public let pageIndex: Int
    public let imageURL: URL?
    public let imageName: String? // モック用ローカル・SF Symbol fallback
    public let aspectRatio: Double // 幅 / 高さ
    
    public init(
        id: String = UUID().uuidString,
        pageIndex: Int,
        imageURL: URL? = nil,
        imageName: String? = nil,
        aspectRatio: Double = 0.707 // A4判標準アスペクト比
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.imageURL = imageURL
        self.imageName = imageName
        self.aspectRatio = aspectRatio
    }
}
