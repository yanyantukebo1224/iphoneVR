import SwiftUI

/// リーダー画面下部のクイックスライダー（サムネイル＆ページ飛び対応）
public struct ReaderQuickSlider: View {
    @Binding public var currentPageIndex: Int
    public let totalPages: Int
    public let onPageSelected: (Int) -> Void
    
    @State private var isDragging: Bool = false
    
    public init(currentPageIndex: Binding<Int>, totalPages: Int, onPageSelected: @escaping (Int) -> Void) {
        self._currentPageIndex = currentPageIndex
        self.totalPages = totalPages
        self.onPageSelected = onPageSelected
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // スライド中のサムネイルポップアップ風バッジ
            if isDragging {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption2)
                    Text("\(currentPageIndex) / \(totalPages)")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Material.ultraThinMaterial)
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                )
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
            }
            
            HStack(spacing: 16) {
                Text("1")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                
                Slider(
                    value: Binding(
                        get: { Double(currentPageIndex) },
                        set: { newValue in
                            let intVal = Int(newValue.rounded())
                            if intVal != currentPageIndex {
                                currentPageIndex = intVal
                                onPageSelected(intVal)
                            }
                        }
                    ),
                    in: 1...Double(max(1, totalPages)),
                    step: 1
                ) { editing in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isDragging = editing
                    }
                }
                .tint(.accentColor)
                
                Text("\(totalPages)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
        }
    }
}
