# 吉里吉里Z iOS 版 プロジェクト

吉里吉里Z (krkrz) を iOS / iPadOS で動かすための外枠テンプレート。
`krkrz_android` と同じく、このリポジトリは「共通のビルドシステム」で、
案件 (ios-config.json + 資材) は別フォルダに置いてビルドできる。

エンジン本体・プラグインは `${KRKRZ_BASE}/krkrz_dev` を参照する
(このリポジトリには含まれない)。

| ドキュメント | 内容 |
|---|---|
| [docs/release.md](docs/release.md) | 配布ビルド (Archive / ipa)、App Store Connect 提出、提出前チェックリスト |
| [docs/icon.md](docs/icon.md) | アプリアイコンの置き場所・設定・画像要件 |
| [docs/ios-design.md](docs/ios-design.md) | 設計検討と実装経緯 |

## 必要なもの

- Xcode 15 以降 (Command Line Tools 含む), CMake 3.24 以降
- vcpkg (`VCPKG_ROOT`)
- 実機ビルド時: Apple Developer の Team ID (`local.mk` に `DEVELOPMENT_TEAM=XXXXXXXXXX`)

## セットアップ

[krkrz_dev](https://github.com/wamsoft/krkrz_dev) をこのリポジトリと**同じ階層**に clone する
(krkrz_android / krkrz_web と同じ配置)。

```bash
mkdir kirikiri && cd kirikiri
git clone --recursive https://github.com/wamsoft/krkrz_dev.git
git clone https://github.com/wamsoft/krkrz_ios.git
cd krkrz_ios
make run
```

```
kirikiri/            ← KRKRZ_BASE (既定 = このリポジトリの親フォルダ)
├── krkrz_dev/       ← エンジン本体・プラグイン
└── krkrz_ios/       ← このリポジトリ
```

別の場所の krkrz_dev を使う場合は環境変数 `KRKRZ_BASE` (krkrz_dev の**親**フォルダ) を指定する。
iOS 対応のエンジン修正は krkrz_dev の develop ブランチ (2026-10 以降) に入っている。

## 使い方

```bash
make build                 # Simulator 用 Debug ビルド (初回は vcpkg 依存のビルドで時間がかかる)
make run                   # 起動中の Simulator にインストールして起動
make run SIM_DEVICE=<UDID> # Simulator を指定 (未起動なら boot)。一覧: xcrun simctl list devices available
make build SDK=device DEVICE=<UDID>   # 実機用 (UDID は xcrun xctrace list devices)
make run SDK=device DEVICE=<UDID>     # 実機にインストールして起動
make xcode                 # 生成された Xcode プロジェクトを開く (デバッガ用)
make ipa                   # 配布用 Release ビルド (REPL なし) → build/ios/ipa/*.ipa  → docs/release.md
make ipa EXPORT_METHOD=app-store-connect   # App Store Connect / TestFlight 提出用
make distclean             # build/ios を削除

# 案件ビルド
PROJECT_DIR=/path/to/案件 make build
```

| 変数 | 意味 |
|---|---|
| `BUILD_SYSTEM_DIR` | このリポジトリ (自動) |
| `PROJECT_DIR` | 案件フォルダ。`${PROJECT_DIR}/ios-config.json` を読み、`${PROJECT_DIR}/build/ios/` に出力。未指定時はこのリポジトリ自身 (サンプル) |
| `SDK` | `simulator` (既定) / `device` |
| `CONFIG` | `Debug` (既定) / `Release` |

ビルド出力:

```
${PROJECT_DIR}/build/ios/
├── generated/     # gen-config.py の出力 (app.cmake, myapp.cmake, assets/, Assets.xcassets)
├── simulator/     # Xcode プロジェクト + ビルド物 (krkrz/Debug-iphonesimulator/krkrz.app)
└── device/
```

## ios-config.json

`cmake` / `assetPack` は krkrz_android の `app-config.json` と同じスキーマ・同じ動作
(`${VAR}` 展開、相対パスは PROJECT_DIR 基準、mirror / flatten、先勝ち)。

```jsonc
{
  "bundleId": "jp.example.game",
  "displayName": "ゲーム名",
  "version": "1.0",               // CFBundleShortVersionString
  "build": 1,                     // CFBundleVersion
  "deploymentTarget": "16.0",
  "devices": ["iphone", "ipad"],
  "orientations": ["landscapeLeft", "landscapeRight"],  // portrait / portraitUpsideDown も可
  "graphics": "gles",             // "gles" (既定。OpenGL ES, ogl/sdlogl DrawDevice、Canvas / Shader 等の GL 機能が使える)
                                  // | "metal" (SDL_Renderer のみ。GL 機能は使えない)
  "repl": true,                   // ブラウザ REPL (-replweb) を組み込むか。配布ビルドは false
  "icon": "icon/AppIcon-1024.png",// 1024x1024 PNG (アルファ無し)。ダーク / ティントも可 → docs/icon.md
  "ipa": { "baseName": "mygame" },// make ipa の出力名 <baseName>-<version>-<build>.ipa (任意)
  "infoPlist": { },               // Info.plist への追加キー
  "entitlements": { },            // entitlements (任意)
  "cmake": {
    "pluginFolders": ["${BUILD_SYSTEM_DIR}/plugins", "${KRKRZ_BASE}/krkrz_dev/src/plugins"],
    "plugins": ["json"]           // iOS は全プラグイン static で組み込まれる
  },
  "assetPack": {
    "baseFolder": "${PROJECT_DIR}",
    "sources": [
      { "type": "mirror", "from": "data", "exclude": ["**/*.bak", "**/*.psd"] },
      { "type": "flatten", "from": "archive", "include": ["*.xp3"] }
    ]
  }
}
```

assetPack の結果はアプリバンドル直下にコピーされる。エンジンはバンドル直下の
`data.xp3` → `data/startup.tjs` の順に探して起動する。

## 実機ビルドの初回準備

1. Xcode > Settings > Accounts で Apple ID にサインインし、**Settings > Components で iOS プラットフォームを導入**
   (`xcodebuild -downloadPlatform iOS` でも可)。デバイス指定ビルドに必要。
2. `local.mk` に Team ID を書く: `DEVELOPMENT_TEAM=XXXXXXXXXX`
3. iPhone 側でデベロッパモードを有効化 (設定 > プライバシーとセキュリティ > デベロッパモード)
4. `make build SDK=device DEVICE=<UDID>` — 自動署名で接続中のデバイスが Team に登録され、プロファイルが作られる
5. 署名で `errSecInternalComponent` が出る場合 (ターミナル / エージェントからのビルドでキーチェーンの
   許可ダイアログが出せない)、Terminal.app で一度だけ次を実行:
   `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '<ログインパスワード>' ~/Library/Keychains/login.keychain-db`
6. 初回起動時は iPhone で 設定 > 一般 > VPN とデバイス管理 > 開発元を「信頼」

`DEVICE` 未指定の `make build SDK=device` は `-target` ビルドになり、デバイス登録が行われない
(登録済み Team / プロファイルがあればそれで署名される)。

## REPL (開発用)

`"repl": true` のビルドには、エンジンのブラウザ REPL (`-replweb`, HTTP+SSE) が入る。
起動引数で `-replweb=<port>` を渡したときだけ待ち受ける (全インタフェース・IPv6+IPv4)。

```bash
make run REPL=8899                                   # Simulator → http://127.0.0.1:8899/
make run SDK=device DEVICE=<UDID> REPL=8899          # 実機 → USB 経由で http://[<IPv6>]:8899/
```

実機は USB 接続時に CoreDevice が張る IPv6 トンネル経由で届く。アドレスは
`dscacheutil -q host -a name <端末名>.coredevice.local` で引ける (端末名は
`xcrun devicectl list devices` の Hostname)。ブラウザで開くと Console / Watch / Pad の
UI、`curl -X POST --data '<TJS>' http://[...]:8899/cmd` でも評価できる (結果は `/events` の SSE)。
REPL の使い方はエンジン側 `doc/REPL.md` と skill `krkrz-repl` を参照。

初回はローカルネットワーク利用の許可ダイアログが出ることがある (`NSLocalNetworkUsageDescription`
は repl 有効時に自動で Info.plist に入る)。配布ビルドでは `"repl": false` にすること。

## タッチ操作

iOS ではタッチ→マウス変換をエンジン側で行う (SDL 標準の変換は無効)。

| 操作 | 送られるもの |
|---|---|
| 1 本指タップ / ドラッグ | 左ボタンの押下・移動・解放 (押下は 100ms 保留して 2 本指と区別) |
| 2 本指タップ (動かさずに離す) | ESC キー (戻る) |
| 2 本指で上下スワイプ | マウスホイール (指を上へ = 下へスクロール) |

`Window.enableTouch = true` にすると `onTouch*` イベントも届く。
`Window.enableTouchMouse = false` でマウスへの変換を止められる。
