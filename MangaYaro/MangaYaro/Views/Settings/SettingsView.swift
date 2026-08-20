import SwiftUI

/// 設定画面（キャッシュ容量上限、先読み枚数、テーマ設定）
public struct SettingsView: View {
    @AppStorage("prefetchWindowSize") private var prefetchWindowSize: Int = 3
    @AppStorage("maxCacheMB") private var maxCacheMB: Int = 200
    @AppStorage("defaultReadingMode") private var defaultReadingMode: String = "paging"
    
    @State private var showingCacheClearedAlert: Bool = false
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    // キャッシュ & パフォーマンス設定
                    Section {
                        Stepper(value: $prefetchWindowSize, in: 1...5) {
                            HStack {
                                Text("スマート先読み枚数")
                                Spacer()
                                Text("\(prefetchWindowSize) ページ")
                                    .foregroundColor(.accentColor)
                                    .bold()
                            }
                        }
                        
                        Stepper(value: $maxCacheMB, in: 50...1000, step: 50) {
                            HStack {
                                Text("キャッシュ最大容量上限")
                                Spacer()
                                Text("\(maxCacheMB) MB")
                                    .foregroundColor(.accentColor)
                                    .bold()
                            }
                        }
                        
                        Button(role: .destructive, action: {
                            Task {
                                await PageCacheManager.shared.clearAllCache()
                                showingCacheClearedAlert = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("キャッシュを今すぐ消去")
                            }
                        }
                    } header: {
                        Text("パフォーマンス & キャッシュ")
                            .foregroundColor(.gray)
                    } footer: {
                        Text("ページめくり待機時間ゼロを実現するため、バックグラウンドで先読みを行います。レート制限(250ms間隔)が有効です。")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    // リーダーデフォルト設定
                    Section {
                        Picker("デフォルト表示モード", selection: $defaultReadingMode) {
                            Text("Paging (横スワイプ)").tag("paging")
                            Text("Webtoon (縦スクロール)").tag("webtoon")
                        }
                    } header: {
                        Text("リーダー設定")
                            .foregroundColor(.gray)
                    }
                    
                    // アプリ情報
                    Section {
                        HStack {
                            Text("アプリ名")
                            Spacer()
                            Text("MangaYaro")
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("バージョン")
                            Spacer()
                            Text("1.0.0 (Minimal Prototype)")
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("UIフレームワーク")
                            Spacer()
                            Text("SwiftUI (iOS Native)")
                                .foregroundColor(.gray)
                        }
                    } header: {
                        Text("アプリ情報")
                            .foregroundColor(.gray)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("設定")
            .alert("キャッシュ消去完了", isPresented: $showingCacheClearedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("一時保存されたページキャッシュデータが正常に削除されました。")
            }
        }
    }
}
