# krkrz_ios — 吉里吉里Z iOS 版

日本語 | [English](README_en.md)

吉里吉里Z (krkrz) を iOS / iPadOS で動かすための外枠リポジトリです。CMake の Xcode ジェネレータで
Xcode プロジェクトを作ってビルドし、システムまわりは SDL3 を使います。

- エンジン本体とプラグインのソースは [krkrz_dev](https://github.com/wamsoft/krkrz_dev) を `KRKRZ_BASE`
  経由で参照します。このリポジトリには iOS 固有のビルド定義とパッケージングだけを置きます
- タイトルごとの設定 (`ios-config.json`) と資材は別のフォルダ (プロジェクトフォルダ) に置けます。
  このリポジトリだけでも、同梱のサンプルとしてビルドできます
- `cmake` (プラグイン構成) と `assetPack` (資材の取り込み) は krkrz_android / krkrz_linux / krkrz_gdk /
  krkrz_web と共通の書式です。iOS は `dlopen` できないため、プラグインは全て static で組み込まれます

## 必要なもの

- macOS と Xcode 15 以降 (Command Line Tools を含む)
- CMake 3.24 以降
- Python 3 (`scripts/gen-config.py` などの生成スクリプトに使います)
- [vcpkg](https://github.com/microsoft/vcpkg) — 環境変数 `VCPKG_ROOT` に導入先を指定
- [krkrz_dev](https://github.com/wamsoft/krkrz_dev) — このリポジトリと同じ場所に clone
- 実機ビルドでは Apple Developer の Team ID (`local.mk` に `DEVELOPMENT_TEAM=XXXXXXXXXX`)

## セットアップ

[krkrz_dev](https://github.com/wamsoft/krkrz_dev) をこのリポジトリと**同じ階層**に clone します
(krkrz_android / krkrz_web と同じ配置です)。

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

別の場所の krkrz_dev を使う場合は、環境変数 `KRKRZ_BASE` (krkrz_dev の**親**フォルダ) を指定します。
iOS 対応のエンジン修正は krkrz_dev の develop ブランチ (2026-10 以降) に入っています。

## ビルドと実行

```bash
make build                 # Simulator 用 Debug ビルド (初回は vcpkg 依存のビルドで時間がかかります)
make run                   # 起動中の Simulator にインストールして起動
make run SIM_DEVICE=<UDID> # Simulator を指定 (未起動なら boot)。一覧: xcrun simctl list devices available
make build SDK=device DEVICE=<UDID>   # 実機用 (UDID は xcrun xctrace list devices)
make run SDK=device DEVICE=<UDID>     # 実機にインストールして起動
make xcode                 # 生成された Xcode プロジェクトを開く (デバッガ用)
make ipa                   # 配布用 Release ビルド (REPL なし) → build/ios/ipa/*.ipa  → docs/release.md
make ipa EXPORT_METHOD=app-store-connect   # App Store Connect / TestFlight 提出用
make distclean             # build/ios を削除

make build PROJECT_DIR=/path/to/mygame     # 自分のプロジェクトフォルダをビルド
```

krkrz_dev (src/core) を更新したら、ビルドの前に `make configure` (実機なら
`make configure SDK=device`) を実行してください。`make build` は Xcode プロジェクトが
既にあると作り直さないため、エンジン側でソースファイルが追加・削除されても拾わず、
追加されたファイルがリンクされません (未定義シンボルのリンクエラーになります)。

| 変数 | 意味 |
|---|---|
| `SDK` | `simulator` (既定) / `device` |
| `CONFIG` | `Debug` (既定) / `Release` |
| `DEVICE` | 実機の UDID (`SDK=device` のとき) |
| `SIM_DEVICE` | Simulator の UDID (既定 `booted` = 起動中のもの) |
| `REPL` | 起動時に `-replweb=<port>` を渡す ([REPL](#repl-開発用)) |
| `EXPORT_METHOD` | `make ipa` の書き出し方法 (`development` (既定) / `release-testing` / `app-store-connect`) |

ビルド出力:

```
${PROJECT_DIR}/build/ios/
├── generated/          # gen-config.py の出力 (app.cmake, myapp.cmake, assets/, Assets.xcassets)
├── simulator-<arch>/   # Xcode プロジェクト + ビルド物 (krkrz/Debug-iphonesimulator/krkrz.app)。arch はホストの CPU
├── device-arm64/
├── generated-dist/     # 配布ビルド (make archive / ipa) 用の生成物
├── dist/               # 配布ビルドの Xcode プロジェクト
├── archive/            # krkrz.xcarchive
└── ipa/                # 書き出した ipa
```

## プロジェクトフォルダ (PROJECT_DIR)

このリポジトリは共通のビルドシステムで、ビルドするタイトルの設定と資材は別のフォルダに置けます。

| 変数 | 意味 |
|---|---|
| `BUILD_SYSTEM_DIR` | このリポジトリのルート。Makefile が自動で決めます |
| `PROJECT_DIR` | プロジェクトフォルダ。`${PROJECT_DIR}/ios-config.json` を読み、`${PROJECT_DIR}/build/ios/` に出力します。未指定ならこのリポジトリ自身 (サンプル) |
| `KRKRZ_BASE` | krkrz_dev の親フォルダ。既定はこのリポジトリの親フォルダ |

- `ios-config.json` の相対パスは `PROJECT_DIR` 基準です。このリポジトリの中を指すときは `${BUILD_SYSTEM_DIR}/...` と書きます
- タイトルをまたいで使う環境設定 (`DEVELOPMENT_TEAM` など) は、このリポジトリ直下の `local.mk` (git の管理外) に書きます

## ios-config.json

バンドル ID・バージョン・対応機種・画面の向き・プラグイン・資材を指定します。リポジトリ直下のファイルが
サンプル兼ひな形です。全体の例と各項目の説明は [docs/ios-config.md](docs/ios-config.md) にあります。

| キー | 内容 |
|---|---|
| `bundleId` / `displayName` | バンドル ID とホーム画面の名前 |
| `version` / `build` | 表示バージョン (`CFBundleShortVersionString`) とビルド番号 (`CFBundleVersion`) |
| `deploymentTarget` / `devices` / `orientations` | 最低 iOS バージョン、対応機種 (iPhone / iPad)、画面の向き |
| `graphics` | `gles` (既定。OpenGL ES。Canvas / Shader 等の GL 機能が使えます) / `metal` (SDL_Renderer のみ) |
| `repl` | ブラウザ REPL (`-replweb`) を組み込むか。配布ビルドは設定に関係なく含めません |
| `a11y` | 読み上げ (VoiceOver) 対応を組み込むか。Elements のダイアログ・`setGameA11y` / `a11yLayers` のノード・`announce` を VoiceOver へ出します |
| `icon` | アプリアイコン (1024x1024 PNG)。[docs/icon.md](docs/icon.md) |
| `ipa.baseName` | `make ipa` の出力ファイル名 |
| `infoPlist` / `entitlements` | Info.plist への追加キー、entitlements |
| `cmake` | 組み込むプラグイン (外枠共通の書式)。全て static で組み込まれます |
| `assetPack` | 資材の取り込み (外枠共通の書式)。結果はアプリバンドル直下にコピーされます |

`cmake` / `assetPack` / パスの `${...}` 展開の書式は、公開サイトの
[外枠リポジトリの共通設定](https://wamsoft.github.io/krkrz_dev/topics/core/platform_config/) を参照してください。

## 実機ビルドの初回準備

1. Xcode > Settings > Accounts で Apple ID にサインインし、**Settings > Components で iOS プラットフォームを導入**します
   (`xcodebuild -downloadPlatform iOS` でも可)。デバイス指定ビルドに必要です
2. `local.mk` に Team ID を書きます: `DEVELOPMENT_TEAM=XXXXXXXXXX`
3. iPhone 側でデベロッパモードを有効にします (設定 > プライバシーとセキュリティ > デベロッパモード)
4. `make build SDK=device DEVICE=<UDID>` — 自動署名で接続中のデバイスが Team に登録され、プロファイルが作られます
5. 署名で `errSecInternalComponent` が出る場合 (ターミナル / エージェントからのビルドでキーチェーンの
   許可ダイアログが出せない)、Terminal.app で一度だけ次を実行します:
   `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '<ログインパスワード>' ~/Library/Keychains/login.keychain-db`
6. 初回起動時は iPhone で 設定 > 一般 > VPN とデバイス管理 > 開発元を「信頼」します

`DEVICE` 未指定の `make build SDK=device` は `-target` ビルドになり、デバイス登録は行われません
(登録済みの Team / プロファイルがあればそれで署名されます)。

## 配布ビルドと App Store Connect

`make archive` / `make ipa` は、開発用ビルドとは別のビルドディレクトリで Release + エンジンの `MASTER` 構成
(REPL なし) のビルドを作ります。事前準備・書き出し方法 (`development` / `release-testing` / `app-store-connect`)・
App Store Connect へのアップロード・提出前チェックリストは [docs/release.md](docs/release.md) にあります。

## REPL (開発用)

`"repl": true` のビルドには、エンジンのブラウザ REPL (`-replweb`, HTTP+SSE) が入ります。
起動引数で `-replweb=<port>` を渡したときだけ待ち受けます (全インタフェース・IPv6+IPv4)。

```bash
make run REPL=8899                                   # Simulator → http://127.0.0.1:8899/
make run SDK=device DEVICE=<UDID> REPL=8899          # 実機 → USB 経由で http://[<IPv6>]:8899/
```

実機には、USB 接続時に CoreDevice が張る IPv6 トンネル経由で届きます。アドレスは
`dscacheutil -q host -a name <端末名>.coredevice.local` で引けます (端末名は
`xcrun devicectl list devices` の Hostname)。ブラウザで開くと Console / Watch / Pad の
UI が使えます。`curl -X POST --data '<TJS>' http://[...]:8899/cmd` でも評価できます (結果は `/events` の SSE)。
REPL の使い方はエンジン側の `doc/REPL.md` と skill `krkrz-repl` を参照してください。

初回はローカルネットワーク利用の許可ダイアログが出ることがあります (`NSLocalNetworkUsageDescription`
は repl 有効時に自動で Info.plist に入ります)。配布ビルドでは REPL は自動で外れます。

## タッチ操作

iOS ではタッチからマウスへの変換をエンジン側で行います (SDL 標準の変換は無効です)。

| 操作 | 送られるもの |
|---|---|
| 1 本指タップ / ドラッグ | 左ボタンの押下・移動・解放 (押下は 100ms 保留して 2 本指と区別) |
| 2 本指タップ (動かさずに離す) | ESC キー (戻る) |
| 2 本指で上下スワイプ | マウスホイール (指を上へ = 下へスクロール) |

`Window.enableTouch = true` にすると `onTouch*` イベントも届きます。
`Window.enableTouchMouse = false` でマウスへの変換を止められます。

## iOS 固有プラグイン

`plugins/` に iOS 専用のプラグインがあります。`ios-config.json` の `cmake.plugins` に名前を書くと組み込まれます
(`cmake.pluginFolders` に `${BUILD_SYSTEM_DIR}/plugins` が必要です)。使い方の詳細は [docs/plugins.md](docs/plugins.md) にあります。

| プラグイン | 内容 |
|---|---|
| `virtualpad` | 画面に半透明の仮想パッドを出し、タッチをゲームパッド入力 (`VK_PAD*`) として渡します。krkrz_android と同じソースです |
| `iosconfig` | システムメニュー (左端からスワイプ) と、機能設定画面・権利情報画面を追加します |
| `gamecenter` | Game Center (実績)。TJS の `GameCenter` クラスは krkrz_android の `PlayGames` と同じ形です。有料の Apple Developer Team での署名が必要です |

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/ios-config.md](docs/ios-config.md) | `ios-config.json` の全体の例と各項目、生成物 |
| [docs/plugins.md](docs/plugins.md) | iOS 固有プラグイン (仮想パッド・システムメニュー・Game Center) の使い方 |
| [docs/release.md](docs/release.md) | 配布ビルド (Archive / ipa)、App Store Connect 提出、提出前チェックリスト |
| [docs/icon.md](docs/icon.md) | アプリアイコンの置き場所・設定・画像要件 |
| [docs/ios-design.md](docs/ios-design.md) | 設計検討と実装経緯 |

吉里吉里Z 本体のドキュメントは [公開サイト](https://wamsoft.github.io/krkrz_dev/) にあります。

## ライセンス

このリポジトリ (ビルドスクリプト・ツール・テンプレート) は [MIT License](LICENSE) です。

ビルド時に参照・取得する以下のものは、それぞれのライセンスに従います。このリポジトリのライセンスは及びません。

- 吉里吉里Z 本体とプラグイン (krkrz_dev 配下の各 submodule)
- SDL3 (zlib License) と、vcpkg で取得する依存ライブラリ
- Xcode / iOS SDK (Apple のライセンス条項)

配布物に必要なライセンスの表記は、使ったエンジン・プラグイン・ライブラリに合わせてタイトル側で同梱してください。
