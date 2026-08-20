import SwiftUI

/// 作品詳細画面（表紙グラデーション & チャプターリスト）
public struct MangaDetailView: View {
    public let manga: Manga
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedChapterForReading: Chapter? = nil
    
    public init(manga: Manga) {
        self.manga = manga
    }
    
    public var body: some View {
        ZStack {
            // 背景ぼかしグラデーション
            ColorExtractor.themeGradient(for: manga.title)
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // ヒーローカバーアート表示
                    headerCoverSection
                    
                    // アクションボタン（「続きを読む」）
                    primaryActionButton
                    
                    // あらすじ & タグ
                    summarySection
                    
                    // チャプターリスト
                    chapterListSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedChapterForReading) { chapter in
            ReaderView(manga: manga, chapter: chapter, initialPageIndex: manga.lastReadPageIndex ?? 1)
        }
    }
    
    // MARK: - Sections
    
    private var headerCoverSection: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 160, height: 220)
                    .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
                
                VStack {
                    Image(systemName: manga.coverImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text(manga.title)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            VStack(spacing: 6) {
                Text(manga.title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(manga.author)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private var primaryActionButton: some View {
        Button(action: {
            if let firstChapter = manga.chapters.first {
                selectedChapterForReading = firstChapter
            }
        }) {
            HStack {
                Image(systemName: "play.fill")
                Text("最新話を読む (\(manga.chapters.first?.title ?? ""))")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .foregroundColor(.black)
            .shadow(color: .white.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(manga.summary)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(manga.tags, id: \.self) { tag in
                        Text("# \(tag)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
    
    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("エピソード List (\(manga.chapters.count))")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(manga.chapters) { chapter in
                    Button(action: {
                        selectedChapterForReading = chapter
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(chapter.isRead ? .white.opacity(0.6) : .white)
                                
                                Text("\(chapter.pageCount) ページ")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            
                            Spacer()
                            
                            // ステータスアイコン
                            statusIcon(for: chapter)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func statusIcon(for chapter: Chapter) -> some View {
        switch chapter.downloadState {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green.opacity(0.8))
        case .downloading:
            ProgressView()
                .tint(.white)
        case .notDownloaded:
            if chapter.isRead {
                Text("既読")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text("NEW")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            }
        }
    }
}
