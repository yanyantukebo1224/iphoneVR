import SwiftUI

/// 単一マンガページの表示コンポーネント（ズーム＆ドラッグ対応）
public struct PageView: View {
    public let page: Page
    public let chapterTitle: String
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    public init(page: Page, chapterTitle: String = "") {
        self.page = page
        self.chapterTitle = chapterTitle
    }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // モック画像・デザイン表現
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        VStack(spacing: 20) {
                            Image(systemName: page.imageName ?? "book.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white.opacity(0.7))
                            
                            VStack(spacing: 6) {
                                Text(chapterTitle)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Text("PAGE \(page.pageIndex)")
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            // コマ割り風モック線
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 120)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 120)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .aspectRatio(page.aspectRatio, contentMode: .fit)
                    .padding(.horizontal, 12)
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 1.0), 4.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale < 1.05 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = 1.0
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            if scale > 1.2 {
                                scale = 1.0
                                offset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
