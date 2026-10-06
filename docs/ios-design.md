# 吉里吉里Z iOS 版 外枠リポジトリ 設計検討

`krkrz_android` と同じ「外枠テンプレート」方式で、案件フォルダ (`PROJECT_DIR`) を指定すると
その資材を内包した iOS アプリ (.app / .ipa) を作れる構成を目指す。エンジン本体・プラグインは
`${KRKRZ_BASE}/krkrz_dev` を参照し、このリポジトリはビルド定義・パッケージング・iOS 固有プラグインだけを持つ。

作成時点の環境: Xcode 26.3 (iPhoneOS 26.2 SDK) / CMake 3.31 / vcpkg (`arm64-ios`, `arm64-ios-simulator` triplet あり) / Simulator iOS 17.5〜18.5。

---

## 1. 調査結果サマリ

### 1.1 krkrz_android から引き継ぐもの

| 要素 | Android での実装 | iOS での扱い |
|---|---|---|
| 案件設定 | `app-config.json` (単一ソース) | `ios-config.json` (同じ思想・`cmake` / `assetPack` は同スキーマ) |
| BUILD_SYSTEM_DIR / PROJECT_DIR 分離 | settings.gradle / Makefile | Makefile + CMake でそのまま踏襲。出力は `${PROJECT_DIR}/build/ios/` |
| `${VAR}` 展開・相対パスは PROJECT_DIR 基準 | build.gradle `expandEnv` / `resolvePath` | 生成スクリプトで同仕様を実装 |
| cmake セクション → `myapp.cmake` 生成 | `generateMyappCmake` (gradle) | 生成スクリプトで同一出力 (`TVP_PLUGIN_FOLDERS` / `TVP_PLUGINS` / `TVP_PLUGINS_STATIC`) |
| assetPack.sources (mirror/flatten, include/exclude, 先勝ち, 差分コピー) | build.gradle `runCopyRules` | 同仕様で再実装。出力先をアプリバンドルに入れる |
| ネイティブ CMake の組み立て | `app/src/main/cpp/CMakeLists.txt` | ほぼ同じ流れ (`KRKRZ_DEFINES_PLATFORM` → SDL3 事前解決 → `CommonExternals.cmake` → `add_subdirectory(core)`) |
| 外枠固有プラグイン | `app/src/main/cpp/<name>/` (`if(NOT ANDROID) return()`) | `plugins/<name>/` (`if(NOT IOS) return()`) |
| PAD (大容量配信) | Play Asset Delivery | Background Assets (後フェーズ) |
| Debug 専用 REPL | abstract unix socket + adb | TCP (Simulator は localhost / 実機は iproxy 等) |

### 1.2 krkrz_dev (エンジン) 側の現状

- エントリは `SDL_MAIN_USE_CALLBACKS` (`sdl3/environ/main.cpp`) で、iOS の UIApplicationMain 管理下でもそのまま動く形。ライフサイクル (background / low memory / terminating) もハンドル済み。
- core の CMake には `CMAKE_SYSTEM_NAME STREQUAL "iOS"` 分岐が既に 3 箇所 (`KRKRZ_DESKTOP` OFF、バンドル内 exe 配置、動的プラグイン警告)。ソース側はほぼ iOS 未考慮。
- `sources.cmake` の APPLE 分岐 (`stdapp` + `sdl3/base/resource.cpp` + movie + ThreadImpl) は iOS でもそのまま使える見込み。
- データ探索は `SDL_GetBasePath()` 基準で `data.xp3` → `data/startup.tjs`。iOS の SDL_GetBasePath はバンドルの resourcePath なので、**バンドル直下に data を置けば Android の Bootstrap コピーのような仕組みは不要**。
- セーブは `SDL_OpenUserStorage` → iOS ではアプリサンドボックス (Library/Application Support 系) になる。
- SDL3 は core が FetchContent (`main` ブランチ、shared) で取るが `if(NOT TARGET SDL3::SDL3)` ガードがあるので外枠から差し替え可能。
- macOS 版は `KRKRZ_USE_OPENGL=OFF` で **SDL_Renderer (Metal) の `sdl` DrawDevice** で動いている。GL 系 (`ogl` / `sdlogl` / Canvas / Shader / Effekseer / threepp) は macOS では未使用。
- Objective-C (.mm) はエンジン・プラグインに 0 件。NSBundle 等も SDL 経由のみ。

### 1.3 エンジン側で必要な修正 (krkrz_dev に入れる)

| 箇所 | 問題 | 対応案 |
|---|---|---|
| `sdl3/environ/form.cpp:136` | `__IOS__` は誰も定義しない → iOS で全画面固定経路に入らない | `SDL_PLATFORM_IOS` に置換 |
| `sdl3/environ/app.cpp:32,55,129` | `__APPLE__` で "macOS" / "macos" を返す | iOS 分岐を追加 (`"iOS"` / `"ios"`) |
| `sdl3/environ/stdapp.cpp` InitPath | データ無し時に `SDL_ShowOpenFolderDialog` | Android 同様 iOS も false を返す |
| `stdapp.cpp:214` `_PluginPath=_AppPath` | 動的プラグイン前提 | iOS は空 (全 static) |
| `src/plugins/tp_stub/krkrz.cmake` | whole-archive の genex が `CXX_COMPILER_ID:Clang` のみ → AppleClang で何も付かず、`NCB_REGISTER_*` だけの .o が ld64 に捨てられる | `$<LINK_LIBRARY:WHOLE_ARCHIVE,...>` (CMake 3.24+) に統一、または AppleClang 時 `-force_load` |
| `common/sound/AudioStream.cpp` (MINIAUDIO_IMPLEMENTATION) | miniaudio は iOS で Objective-C コンパイル必須 (AVAudioSession) | iOS 時のみ `-x objective-c++` + AVFoundation リンク。セッションカテゴリ (ambient / playback) と割り込み復帰の方針を決める |
| `ElementsDialogManager.cpp:1350` / `accesskit_host.cpp` | Cocoa 前提 (`objc_msgSend`, COCOA_WINDOW_POINTER) | iOS では `KRKRZ_USE_A11Y` 既定 OFF なのでまずは OFF。ガードが漏れていないかだけ確認 |
| `src/core/CMakeLists.txt:943` SDL3 FetchContent `main` | 再現性なし | 外枠で版固定して先に供給 (下記) |
| `src/core/CMakeLists.txt:1017` `MACOSX_PACKAGE_LOCATION Resources` | iOS はフラットバンドル。`X.app/Resources/` に入ると SDL_GetBasePath (=`X.app/`) とずれる可能性 | P0 で実際の配置を確認し、必要なら iOS は `""` に |
| `generic/utils/ThreadImpl.cpp:67` | Apple でスレッド名未設定 | (任意) `pthread_setname_np` |

---

## 2. 設計の柱

### 2.1 ビルド方式: CMake の Xcode ジェネレータで .app を直接生成

```
cmake -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos|iphonesimulator \
      -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
      -DVCPKG_TARGET_TRIPLET=arm64-ios|arm64-ios-simulator \
      -DMYAPP_CMAKE_FILE=${PROJECT_DIR}/build/ios/generated/myapp.cmake ...
xcodebuild -project ... -scheme krkrz -configuration Debug|Release [archive / -exportArchive]
```

- **Xcode ジェネレータを選ぶ理由**: コード署名・プロビジョニング・アセットカタログ (アイコン)・LaunchScreen storyboard のコンパイル・Archive/Export を Xcode 標準経路に任せられる。Ninja で .app を組むとこれらを全部自前で書くことになる。
- 生成された .xcodeproj は「生成物」扱い (`${PROJECT_DIR}/build/ios/<sdk>/`)。手で編集しない。Xcode でのデバッグは生成物をそのまま開けばよい。
- vcpkg triplet は SDK ごとに 1 つなので **実機と Simulator はビルドディレクトリを分ける** (`build/ios/device`, `build/ios/simulator`)。x86_64 Simulator は対象外 (Apple Silicon 前提)。
- 却下案: 「エンジンを静的 xcframework 化して手書き Xcode プロジェクトから参照」→ 2 段ビルドになり、プラグイン構成が案件ごとに変わる本構成では利点が薄い。

### 2.2 SDL3 の扱い: 外枠で版固定・静的リンク

- 外枠の CMakeLists で `add_subdirectory(core)` より前に SDL3 を FetchContent (**リリースタグ固定**、Android の AAR と同じ 3.4.x 系に揃える)、`SDL_STATIC=ON / SDL_SHARED=OFF` で `SDL3::SDL3` を作る → core 側の FetchContent はスキップされる。
- 静的にする理由: iOS では動的 framework の埋め込み・署名の手間が増えるだけで利点がない。krkrz 本体も静的プラグインも 1 バイナリにまとめる。
- SDL の iOS 固有設定: `UILaunchStoryboardName` 必須、`SDL_HINT_IOS_HIDE_HOME_INDICATOR`、向きは Info.plist `UISupportedInterfaceOrientations` + `SDL_HINT_ORIENTATIONS` (Android の `sdl_orientations` 相当を ios-config.json のキーにする)。
- 将来 SDL を案件横断で使い回したくなったら、SDL だけ xcframework を事前ビルドして `find_package` させる方式 (Android の prefab と同じ発想) に切り替え可能。

### 2.3 グラフィックス (GLES) の扱い

選択肢:

| 案 | 内容 | 長所 | 短所 |
|---|---|---|---|
| **A. SDL_Renderer / Metal** (`KRKRZ_USE_OPENGL=OFF`) | macOS 版と同じ `sdl` DrawDevice | 追加作業ほぼゼロ。Apple 推奨 API。macOS で実績あり | Canvas / Shader / Offscreen / Effekseer / threepp 等の GL 機能が使えない |
| **B. ネイティブ GLES (EAGL)** (`KRKRZ_USE_OPENGL=ON`) | SDL UIKit ドライバの GLES。`ogl` / `sdlogl` デバイス | Android と同じコード経路。GL 系機能・プラグインがそのまま動く | iOS 12 から deprecated (iOS 26.2 SDK にも OpenGLES.framework は残存)。上限 ES 3.0 (エンジンは 3.2→3.0 フォールバック済み、`GLEffect` は `300 es` なので OK)。将来削除リスク |
| C. ANGLE (Metal バックエンド) | GLES を ANGLE 経由で Metal に変換 | GL 互換を保ちつつ deprecated API を回避 | **SDL3 の UIKit ドライバは EGL 非対応** (uikit 実装に EGL 経路なし、確認済み) → SDL へのパッチか自前 EGL サーフェス管理が必要。ANGLE の iOS ビルド・バイナリサイズ (~10MB) |

**方針**:

1. **既定は A (Metal)**。macOS と同じ構成で最短で動かす。GL を使わない一般的なノベル系案件はこれで足りる。
2. **B をビルドオプションとして用意** (`ios-config.json` の `graphics: "metal" | "gles"`)。GL 系機能が必要な案件だけ ON。Android とのコード共有度が最も高く、当面の現実解。
3. C は「Apple が OpenGLES.framework を削除する兆候が出たら」の保険として調査メモに留める。

要確認 (P0/P2 で検証):
- `KRKRZ_USE_OPENGL=ON` 時に `SDL_WINDOW_OPENGL` 付きウィンドウで `sdl` (Metal) デバイスも併用できるか、または GL 有効時は GL デバイス限定になるか。
- バックグラウンド遷移後に GL 呼び出しが走るとプロセスが kill される (iOS 固有)。`SetInBackground` で描画が完全停止するか。
- glad の `gladLoadGLES2(SDL_GL_GetProcAddress)` が EAGL で全関数解決できるか。

### 2.4 データ配置

- assetPack.sources の結果を `${PROJECT_DIR}/build/ios/assets/` にステージングし、**バンドル直下にフォルダ参照としてコピー** (`data/`、`*.xp3`、`resource` 系)。iOS のバンドルは直接ファイルアクセスできるので Android の AssetManager / Bootstrap コピーは不要。
- `resource://` (core `resource/` やフォント) も同じくバンドル直下へ。
- 日本語フォント: エンジンは OS フォントを列挙しない (CoreText 未対応) ので、`fonts.json` 同梱か `KRKRZ_EMBED_BUNDLED_FONTS=ON` 前提。
- 容量: App Store のアプリサイズ上限内なら全同梱。超える案件は **Background Assets (Apple-hosted asset packs)** を PAD 相当として後フェーズで対応。設定キーは `assetPacks[]` として Android の `padPacks` と対になる形で予約しておく。

### 2.5 プラグイン

- iOS は **全プラグイン static** (dlopen 不可)。`ios-config.json` では `cmake.plugins` だけ書けば生成スクリプトが `staticPlugins` に全展開する (明示指定も可)。
- 外枠固有プラグイン (`plugins/` 配下、必要になった順):
  - `virtualpad`: Android 版の描画/入力部分を共有し JNI 部だけ差し替え (Android 側 CMake コメントで想定済み)。共通部は krkrz_dev 側へ移すのが理想。
  - `iosconfig`: Android の `androidconfig` 相当 (設定画面 ↔ TJS)。
  - `gamecenter` (Play Games 相当)、`license` (OSS ライセンス表示) など。
  - ObjC++ (.mm) で UIKit/Apple フレームワークを叩き、TJS へは NCBIND で公開する。メインスレッド/コールバックは Android と同じく continuous event でキューを drain する設計に揃える。
- iOS で除外推奨: WIN 専用群、krkrgles、krkrthreepp (重量級・GL 必須)、krkr_richtext (ICU フルビルド) は必要時に個別検証。

### 2.6 リポジトリ構成案

```
krkrz_ios/
├── Makefile                 # gradlew ラッパーに相当: configure/build/run/archive/export/clean
├── CMakeLists.txt           # 外枠: myapp.cmake 読込, PLATFORM defines, SDL3 固定, core 取り込み, バンドル設定
├── ios-config.json          # サンプル案件設定 (PROJECT_DIR 未指定時に使用)
├── cmake/
│   └── KrkrzIOS.cmake       # バンドル/署名/リソース配置のヘルパ
├── ios/                     # テンプレート
│   ├── Info.plist.in
│   ├── LaunchScreen.storyboard
│   ├── Entitlements.plist.in
│   └── Assets.xcassets/     # AppIcon は 1024px 1 枚から生成
├── plugins/                 # iOS 固有プラグイン (virtualpad, iosconfig, ...)
├── scripts/
│   ├── gen-config.py        # ios-config.json → myapp.cmake / plist 変数 / アセットステージング
│   └── ExportOptions.plist.in
├── resource/                # サンプル用リソース
└── docs/
```

`local.properties` 相当 (案件横断の環境設定: `DEVELOPMENT_TEAM`、署名 ID、App Store Connect API キー) は `BUILD_SYSTEM_DIR/local.mk` (gitignore) に置く。

### 2.7 ios-config.json 案

```jsonc
{
  "bundleId": "jp.wamsoft.krkrz.sample",
  "displayName": "krkrz sample",
  "version": "1.0",            // CFBundleShortVersionString
  "build": 1,                  // CFBundleVersion (単調増加)
  "deploymentTarget": "16.0",
  "devices": ["iphone", "ipad"],
  "orientations": ["landscapeLeft", "landscapeRight"],
  "graphics": "metal",         // "metal" | "gles"
  "icon": "icon/AppIcon-1024.png",
  "infoPlist": { },            // 追加キー (Android の manifestPlaceholders 相当)
  "entitlements": { },
  "cmake": {                   // Android と同スキーマ
    "pluginFolders": ["${BUILD_SYSTEM_DIR}/plugins", "${KRKRZ_BASE}/krkrz_dev/src/plugins"],
    "plugins": ["json", "virtualpad"]
    // staticPlugins 省略時は plugins 全部
  },
  "assetPack": {               // Android と同スキーマ・同セマンティクス
    "baseFolder": "${BUILD_SYSTEM_DIR}",
    "sources": [
      { "type": "mirror", "from": "resource", "to": "" },
      { "type": "mirror", "from": "data", "exclude": ["**/*.bak", "**/*.psd"] },
      { "type": "flatten", "from": "archive", "include": ["*.xp3"] },
      { "type": "mirror", "from": "${KRKRZ_BASE}/krkrz_dev/src/core/resource", "to": "" },
      { "type": "mirror", "from": "${KRKRZ_BASE}/krkrz_dev/src/core/data" }
    ]
  }
}
```

- `cmake` と `assetPack` を Android と完全に同じスキーマにしておけば、案件フォルダに `app-config.json` と `ios-config.json` を並べて同じ `data/` を共有できる。
- assetPack のマージ処理は Android では Groovy 実装。iOS は Python (Xcode CLT に同梱の python3) で書き、将来的には両外枠で共有ツール化も検討。

### 2.8 開発サイクル (Makefile)

| ターゲット | 内容 |
|---|---|
| `make configure SDK=simulator\|device` | config 生成 + `cmake -G Xcode` |
| `make build` | `xcodebuild build` |
| `make run` (simulator) | `xcrun simctl install/launch`、ログは `simctl spawn ... log stream` |
| `make run SDK=device` | `xcrun devicectl device install app / process launch` |
| `make xcode` | 生成 .xcodeproj を開く (デバッガ用) |
| `make archive` / `make ipa` | `xcodebuild archive` → `-exportArchive` |
| `make upload` | App Store Connect API (`xcrun altool` / `notarytool` 相当) で TestFlight へ。Android の play-publish に相当 (後フェーズ) |
| `make repl` | Debug ビルドの REPL へ接続 (Simulator は localhost TCP) |

---

## 3. フェーズ計画

| フェーズ | ゴール | 主な作業 |
|---|---|---|
| **P0 スパイク** | Simulator で `data/startup.tjs` が起動し描画・入力・音が出る | 最小 CMakeLists (Xcode gen, arm64-ios-simulator, `KRKRZ_USE_OPENGL=OFF`, プラグイン json のみ static)。1.3 のエンジン修正を順次 krkrz_dev へ。vcpkg 依存 (libvpx 等) の iOS ビルド可否確認 |
| **P1 テンプレート化** | 案件フォルダ指定で実機用 .ipa まで作れる | ios-config.json / gen-config.py / assetPack / Info.plist・アイコン・LaunchScreen / 署名 / Makefile 一式 / README |
| **P2 GLES** | `graphics: "gles"` で ogl / sdlogl / Canvas / Effekseer が動く | EAGL 検証、バックグラウンド時の GL 停止確認 |
| **P3 iOS 固有機能** | Android 版と機能パリティ | virtualpad 移植、設定画面、Game Center、REPL (TCP)、Safe Area / ホームインジケータ、オーディオセッション方針 |
| **P4 配信** | 大容量案件・ストア提出の自動化 | Background Assets、TestFlight アップロード自動化、VoiceOver (AccessKit iOS) 検討 |

---

## 4. 決めてほしいこと

1. **最低対応 iOS バージョン** (案: 16.0。SDL3 自体は iOS 11+ だが、検証コストと Background Assets 等を考えると高めでよい)
2. **iPad 対応** の要否 (ユニバーサルにするか iPhone 専用か)
3. **GL 系機能 (Canvas / Shader / Effekseer) が必要な案件が近々あるか** → あれば P2 を前倒し
4. エンジン側修正 (1.3) を krkrz_dev に直接入れてよいか (Android 外枠と同様「外枠からは触らない」原則なので、修正は krkrz_dev 側でコミットする想定)

---

## 5. P0 結果 (2026-10-06)

Simulator (iPad Pro 13" / iOS 18.5) で Metal 版・GLES 版とも `data/startup.tjs` (コアデモギャラリー) が起動・描画することを確認。

実装上の判断・ハマりどころ:

- **xcodebuild は `-scheme` ではなく `-target` + `-sdk`** で叩く。Xcode 26 は scheme ビルド時に destination 解決で iOS 26.x プラットフォーム (Settings > Components) の導入を要求するが、`-target` 指定なら不要。
- **起動画面は storyboard ではなく Info.plist の `UILaunchScreen`**。storyboard のコンパイル (ibtool) もプラットフォーム導入を要求するため。
- **Simulator のアーキはホストに合わせる** (Intel Mac = x86_64, Apple Silicon = arm64)。Makefile が `uname -m` で triplet (`x64-ios-simulator-krkrz` / `arm64-ios-simulator-krkrz`) と `CMAKE_OSX_ARCHITECTURES` を選び、ビルドディレクトリは `simulator-<arch>`。
- **libvpx は overlay port** (`vcpkg-ports/libvpx`)。本家 port は iOS Simulator 向けにビルドできない (libvpx の configure に simulator ターゲットが無く iphoneos 向けオブジェクトになる) ので、simulator のみ generic-gnu + clang `--target` で作る。
- 外枠のバンドル設定 (POST_BUILD の資材コピー等) は、エンジンがターゲット定義直後に呼ぶ `krkrz_platform_target_hook()` 経由で行う (add_custom_command(TARGET) は同一ディレクトリ限定)。資材コピーは Xcode の `TARGET_BUILD_DIR` / `WRAPPER_NAME` を使う (`$<TARGET_BUNDLE_DIR>` は `${EFFECTIVE_PLATFORM_NAME}` が展開されない)。
- HarfBuzz の CoreText shaper 用に CoreText / CoreGraphics / CoreFoundation をリンク。

エンジン (krkrz_dev) に入れた修正:

- iOS 判定 (`SDL_PLATFORM_IOS`)、OS 名 / プラットフォームタグ、データ未検出時の扱い、プラグインパス
- iOS クロスビルドで `CMAKE_SYSTEM_PROCESSOR` が空 → SIMD (NEON/SSE) ソースが落ちる問題
- miniaudio 実装 (AudioStream.cpp) の Objective-C++ コンパイル
- AppleClang の静的プラグイン `-force_load`
- A11Y 無効時の Elements コンパイルエラー
- 常時フルスクリーン環境の GL 経路が縦横別倍率で引き伸ばされていた → レターボックスに統一、GL 経路のマウス座標換算 (Android の GLES にも効く)

残課題:

- 実機ビルド・署名 (`SDK=device`, `DEVELOPMENT_TEAM`)
- Simulator でハードウェアキーボード接続扱いのとき、テキスト入力ベースライン有効でキーボードバーが出る (実機でキーボード無しなら出ない想定。要実機確認)
- タッチ (`mEnableTouch` 時の `tfinger` 換算) のレターボックス対応
- iPad のマルチタスク / 回転、Safe Area
