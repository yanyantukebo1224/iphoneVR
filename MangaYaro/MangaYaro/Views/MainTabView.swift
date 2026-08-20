import SwiftUI

/// アプリメインの3タブ構成View
public struct MainTabView: View {
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("ライブラリ", systemImage: "books.vertical.fill")
                }
                .tag(0)
            
            DiscoverView()
                .tabItem {
                    Label("見つける", systemImage: "sparkles")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(.white)
    }
}
