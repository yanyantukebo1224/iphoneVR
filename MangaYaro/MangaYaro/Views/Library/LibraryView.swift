import SwiftUI

/// ホーム・ライブラリ画面（ポスターグリッド & 進捗バー）
public struct LibraryView: View {
    @State private var mangas: [Manga] = MockDataService.shared.sampleMangas
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("ライブラリ")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(mangas) { manga in
                                NavigationLink(destination: MangaDetailView(manga: manga)) {
                                    mangaPosterCard(manga)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
        }
    }
    
    private func mangaPosterCard(_ manga: Manga) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // カバーポスターカード
            ZStack(alignment: .bottomLeading) {
                ColorExtractor.themeGradient(for: manga.title)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                VStack {
                    Image(systemName: manga.coverImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // お気に入りハートバッジ
                if manga.isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .padding(8)
                                .background(Circle().fill(Material.ultraThinMaterial))
                                .padding(8)
                        }
                        Spacer()
                    }
                }
                
                // 読書進捗バー（下部オーバーレイ）
                VStack(alignment: .leading, spacing: 4) {
                    Text(manga.title)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // プログレスバー
                    GeometryReader { p in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: p.size.width * CGFloat(manga.overallProgress))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(10)
                .background(
                    Rectangle()
                        .fill(Material.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            // 進捗状況テキスト
            HStack {
                Text("\(Int(manga.overallProgress * 100))% 読了")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
        }
    }
}
