import SwiftUI

/// 見つける（トレンド・検索・ジャンル）画面
public struct DiscoverView: View {
    @State private var searchText: String = ""
    @State private var selectedGenre: String = "すべて"
    
    private let genres = ["すべて", "SF・ファンタジー", "バトル", "日常・スローライフ", "Webtoon", "ホラー"]
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("見つける")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        // 検索バー
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("作品名、作者名、キーワードで検索", text: $searchText)
                                .foregroundColor(.white)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                        )
                        .padding(.horizontal, 20)
                        
                        // ジャンルチップ
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(genres, id: \.self) { genre in
                                    Button(action: { selectedGenre = genre }) {
                                        Text(genre)
                                            .font(.subheadline.weight(selectedGenre == genre ? .bold : .regular))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(selectedGenre == genre ? Color.accentColor : Color.white.opacity(0.1))
                                            )
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // トレンドカルーセル風セクション
                        VStack(alignment: .leading, spacing: 12) {
                            Text("🔥 今週のトレンド作品")
                                .font(.title3.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(MockDataService.shared.sampleMangas) { manga in
                                        NavigationLink(destination: MangaDetailView(manga: manga)) {
                                            trendCard(manga)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
        }
    }
    
    private func trendCard(_ manga: Manga) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ColorExtractor.themeGradient(for: manga.title)
                    .frame(width: 140, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                
                Image(systemName: manga.coverImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Text(manga.title)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
    }
}
