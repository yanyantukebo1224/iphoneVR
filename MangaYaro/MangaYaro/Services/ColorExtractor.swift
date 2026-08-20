import SwiftUI

/// 表紙画像の雰囲気に合わせたアクセントグラデーションを自動抽出・生成するヘルパー
public struct ColorExtractor {
    
    /// タイトルやIDハッシュに基づいて洗練されたカラーグラデーションを生成（モック＆演出用）
    public static func themeGradient(for seed: String) -> LinearGradient {
        let hash = abs(seed.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash + 40) % 360) / 360.0
        
        let color1 = Color(hue: hue1, saturation: 0.6, brightness: 0.35)
        let color2 = Color(hue: hue2, saturation: 0.8, brightness: 0.15)
        let color3 = Color.black
        
        return LinearGradient(
            colors: [color1, color2, color3],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public static func mainAccentColor(for seed: String) -> Color {
        let hash = abs(seed.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.75, brightness: 0.9)
    }
}
