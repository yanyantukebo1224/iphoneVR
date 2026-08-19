# iPhoneVR - Moonlight 改造 6DoF 指トラッキング SteamVR HMD システム

iPhone単体を**SteamVR対応の6DoF頭部トラッキング ＋ 両手指21関節指トラッキング VR HMD**化するフルセット実装プロジェクトです。

---

## ⚡ 1. 自動ビルド ＆ CI/CD (GitHub Actions)

本リポジトリには **GitHub Actions ワークフロー** ([`.github/workflows/ios_build.yml`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/.github/workflows/ios_build.yml)) が組み込まれています。

- **iOSアプリ (`MoonlightHMD.app`)**:
  - リポジトリにプッシュすると、GitHub上の `macos-14` (Xcode 15.4) ランナーが自動起動し、iOSアプリを自動ビルドして Artifacts として出力・ダウンロード可能になります。
- **PC側 SteamVR ドライバ (`driver_iphonevr.dll`)**:
  - `windows-latest` ランナーが MSVC/CMake で自動コンパイルし、ビルド済みドライバを出力します。

---

## 🛠️ 2. ワンクリック セットアップ手順

### PC側 (SteamVR ドライバのセットアップ)
1. 本リポジトリ内の [`setup_steamvr_driver.bat`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/setup_steamvr_driver.bat) をダブルクリックで実行。
2. 自動で SteamVR に `driver_iphonevr` が追加・登録されます。
3. （独自ビルドする場合）[`build_pc_driver.bat`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/build_pc_driver.bat) をダブルクリックすると C++ ドライバ DLL が自動ビルドされます。

### iPhone側 (iOSアプリのインストール)
1. GitHub Actions の Build 成果物から `MoonlightHMD-iOS-Build` をダウンロード、または Xcode で [`iOS/MoonlightHMD`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD) をビルド。
2. アプリを起動し、PCのIPアドレスを指定して **「Start VR HMD Mode」** をタップ！

---

## 🎯 クリティカル最適化ポイントの実装一覧

- **① Skeletal 31ボーン補正**: [`hand_controller_driver.cpp`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/SteamVR_Driver/src/hand_controller_driver.cpp)
- **② DirectModeオフ (仮想HMD)**: [`default.vrsettings`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/SteamVR_Driver/driver_iphonevr/resources/settings/default.vrsettings)
- **③ ARKit ➔ OpenVR 座標変換・軸反転**: [`hmd_device_driver.cpp`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/SteamVR_Driver/src/hmd_device_driver.cpp)
- **Metalゼロコピー表示 (`CVMetalTextureCache`)**: [`MoonlightVRViewController.swift`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD/VRRender/MoonlightVRViewController.swift)
- **C struct バイナリ UDP送信**: [`BinaryUDPStreamer.swift`](file:///c:/Users/USER/OneDrive/Desktop/iphoneVR/iOS/MoonlightHMD/Network/BinaryUDPStreamer.swift)
