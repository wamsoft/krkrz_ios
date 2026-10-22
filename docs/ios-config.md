# ios-config.json — iOS 版の設定

プロジェクトフォルダの `ios-config.json` で、バンドル ID・バージョン・対応機種・画面の向き・
グラフィックス方式のほか、組み込むプラグイン (`cmake`) と取り込む資材 (`assetPack`) を指定します。
`scripts/gen-config.py` がこのファイルを読み、`${PROJECT_DIR}/build/ios/generated/` に CMake 用の生成物を作ります。

`cmake` / `assetPack` / パス文字列の `${...}` 展開は、krkrz_android / krkrz_linux / krkrz_gdk / krkrz_web と
共通の書式です (`${VAR}` 展開、相対パスは `PROJECT_DIR` 基準、mirror / flatten、先勝ち)。共通部分の説明は公開サイトの
[外枠リポジトリの共通設定 (cmake / assetPack)](https://wamsoft.github.io/krkrz_dev/topics/core/platform_config/)
にあります。このページは iOS 版だけの項目と、iOS での動き方を説明します。

## 全体の例

リポジトリ直下の `ios-config.json` がサンプル兼ひな形です。

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
  "a11y": false,                  // 読み上げ (VoiceOver) にダイアログ等を出すか
  "icon": "icon/AppIcon-1024.png",// 1024x1024 PNG (アルファ無し)。ダーク / ティントも可 → icon.md
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

## 項目

| キー | 既定値 | 内容 |
|---|---|---|
| `bundleId` | (必須) | バンドル ID。`make run` で起動するアプリの指定にも使います |
| `displayName` | `krkrz` | ホーム画面に出る名前 |
| `version` | `1.0` | 表示バージョン (`CFBundleShortVersionString`) |
| `build` | `1` | ビルド番号 (`CFBundleVersion`)。App Store Connect にはアップロードごとに増やします |
| `deploymentTarget` | `16.0` | 最低対応 iOS バージョン |
| `devices` | `["iphone", "ipad"]` | 対応機種 |
| `orientations` | `["landscapeLeft", "landscapeRight"]` | 画面の向き。`portrait` / `portraitUpsideDown` も指定できます |
| `graphics` | `gles` | `gles` (OpenGL ES。ogl / sdlogl DrawDevice、Canvas / Shader 等の GL 機能が使えます) か `metal` (SDL_Renderer のみ。GL 機能は使えません) |
| `repl` | `true` | ブラウザ REPL (`-replweb`) を組み込むか。配布ビルド (`make archive` / `make ipa`) はこの値に関係なく REPL を含めません |
| `a11y` | `false` | 読み上げ (VoiceOver) 対応を組み込むか。Elements のダイアログ・`ElementsDialog.setGameA11y` / `a11yLayers` のノード・`announce` を VoiceOver へ出します。`false` でも API は使えます (OS へ出ないだけ) |
| `icon` | なし | アプリアイコン。文字列 1 つか、`default` / `dark` / `tinted` の辞書 ([icon.md](icon.md)) |
| `ipa.baseName` | なし | `make ipa` の出力名を `<baseName>-<version>-<build>[-<method>].ipa` にします ([release.md](release.md)) |
| `infoPlist` | なし | Info.plist への追加キー |
| `entitlements` | なし | entitlements |
| `developmentTeam` | なし | 署名の Team ID。環境変数 / `local.mk` の `DEVELOPMENT_TEAM` があればそちらが優先です |
| `cmake` | | 組み込むプラグイン (外枠共通の書式)。iOS は `dlopen` できないため、`plugins` に挙げたものは全て static で組み込まれます |
| `assetPack` | | 資材の取り込み (外枠共通の書式) |

## 資材の配置

assetPack の結果はアプリバンドル直下にコピーされます。エンジンはバンドル直下の
`data.xp3` → `data/startup.tjs` の順に探して起動します。

## 生成物

`scripts/gen-config.py` は次のものを作ります (出力先は既定で `${PROJECT_DIR}/build/ios/generated/`)。

| ファイル | 内容 |
|---|---|
| `app.cmake` | バンドル ID / バージョン / 向き / グラフィックス方式などの変数 |
| `myapp.cmake` | `TVP_PLUGIN_FOLDERS` / `TVP_PLUGINS` / `TVP_PLUGINS_STATIC` |
| `assets/` | `assetPack.sources` をまとめた資材 (バンドル直下へコピーされます) |
| `Assets.xcassets` | `icon` を指定したときだけ (AppIcon) |
| `app.entitlements` | `entitlements` を指定したときだけ |

設定ファイルの場所は環境変数 `APP_CONFIG_FILE` で変えられます (既定は `${PROJECT_DIR}/ios-config.json`)。
