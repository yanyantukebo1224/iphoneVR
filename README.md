# iPhoneVR - Moonlight 改造 6DoF 指トラッキング ＆ Switchコントローラー VR HMD システム

iPhone単体を**SteamVR対応の6DoF頭部トラッキング ＋ 両手指21関節指トラッキング ＋ Nintendo Switch Joy-Con/ProコンVRコントローラー対応 VR HMD**化するフルセット実装プロジェクトです。

---

## 🚀 主な機能・特徴

1. **🥽 Moonlight VR HMD (SBS 3D / 低遅延デコード)**:
   - Moonlight core と VideoToolbox による超低遅延 CVPixelBuffer デコード。
   - `CVMetalTextureCache` を用いたゼロコピー Metal レンダリング＆左右眼レンズ歪み補正シェーダー。
2. **🖐️ 21関節フィンガートラッキングの完全動作**:
   - Apple Vision Framework（21関節検出）と各指（親指・人差し指・中指・薬指・小指）の個別 Curl（曲がり度合）計算。
   - SteamVR OpenVR Skeletal 31ボーン構造への完全マッピング（各指独立の握り・開き・ピース・グー・パー・個別指動作）。
   - 適応型平滑化（One Euro Filter）によるブレ・ジッターの抑制。
3. **🎮 Nintendo Switch コントローラー ＆ Gamepad 連携（カメラトラッキング融合）**:
   - `GameController.framework` により、iPhoneにBluetooth接続した Nintendo Switch Joy-Con (L/R) や Switch Pro Controller、Xbox/PSコントローラーを自動認識。
   - 物理コントローラーのボタン（ABXY, Trigger/ZL/ZR, Grip/L/R, スティック, スティック押し込み, メニュー）をSteamVR Inputに連動。
   - コントローラー/手の位置はiPhoneカメラで正確に6DoFトラッキングしつつ、物理ボタン・スティック操作が可能！

---

## ⚡ 自動ビルド ＆ CI/CD (GitHub Actions)

本リポジトリには **GitHub Actions ワークフロー** ([`.github/workflows/ios_build.yml`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/.github/workflows/ios_build.yml)) が組み込まれています。

- **iOSアプリ (`MoonlightHMD.app`)**:
  - リポジトリにプッシュすると、GitHub上の `macos-14` (Xcode 15.4) ランナーが自動起動し、iOSアプリを自動ビルドして Artifacts として出力・ダウンロード可能になります。
- **PC側 SteamVR ドライバ (`driver_iphonevr.dll`)**:
  - `windows-latest` ランナーが MSVC/CMake で自動コンパイルし、ビルド済みドライバを出力します。

---

## 🛠️ ワンクリック セットアップ手順

### PC側 (SteamVR ドライバのセットアップ)
1. 本リポジトリ内の [`setup_steamvr_driver.bat`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/setup_steamvr_driver.bat) をダブルクリックで実行。
2. 自動で SteamVR に `driver_iphonevr` が追加・登録されます。
3. （独自ビルドする場合）[`build_pc_driver.bat`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/build_pc_driver.bat) をダブルクリックすると C++ ドライバ DLL が自動ビルドされます。

### iPhone側 (iOSアプリのインストール ＆ コントローラー接続)
1. （Switch Joy-Con / Proコンを使用する場合）iPhoneの「設定」➔「Bluetooth」から Joy-Con (L)/(R) または Proコントローラーをペアリング。
2. アプリを起動し、PCのIPアドレスを指定して **「Start VR HMD Mode」** をタップ！

---

## 🎯 クリティカル最適化ポイントの実装一覧

- **① 21関節➔31ボーン Skeletal & Gamepad 入力**: [`hand_controller_driver.cpp`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/SteamVR_Driver/src/hand_controller_driver.cpp)
- **② GameController.framework (Joy-Con/Gamepad)**: [`GameControllerManager.swift`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD/Input/GameControllerManager.swift)
- **③ 21関節 & 指Curl計算 ＆ スムージング**: [`ARHandTrackerManager.swift`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD/ARTracking/ARHandTrackerManager.swift)
- **④ DirectModeオフ (仮想HMD)**: [`default.vrsettings`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/SteamVR_Driver/driver_iphonevr/resources/settings/default.vrsettings)
- **⑤ Metalゼロコピー表示 (`CVMetalTextureCache`)**: [`MoonlightVRViewController.swift`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD/VRRender/MoonlightVRViewController.swift)
- **⑥ C struct バイナリ UDP送信**: [`BinaryUDPStreamer.swift`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD/Network/BinaryUDPStreamer.swift)
