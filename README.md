# 吉里吉里Z iOS 版 プロジェクト

吉里吉里Z (krkrz) を iOS / iPadOS で動かすための外枠テンプレート。
`krkrz_android` と同じく、このリポジトリは「共通のビルドシステム」で、
案件 (ios-config.json + 資材) は別フォルダに置いてビルドできる。

エンジン本体・プラグインは `${KRKRZ_BASE}/krkrz_dev` を参照する
(このリポジトリには含まれない)。設計の詳細は [docs/ios-design.md](docs/ios-design.md)。

## 必要なもの

- Xcode 15 以降 (Command Line Tools 含む), CMake 3.24 以降
- vcpkg (`VCPKG_ROOT`)
- `KRKRZ_BASE`: krkrz_dev の親フォルダ
- 実機ビルド時: Apple Developer の Team ID (`local.mk` に `DEVELOPMENT_TEAM=XXXXXXXXXX`)

## 使い方

```bash
make build                 # Simulator 用 Debug ビルド (初回は vcpkg 依存のビルドで時間がかかる)
make run                   # Simulator (既定 "iPad Pro 13-inch (M4)") で起動
make run SIM_DEVICE="iPhone 16"
make build SDK=device      # 実機用
make xcode                 # 生成された Xcode プロジェクトを開く (デバッガ用)
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
  "graphics": "metal",            // "metal" (SDL_Renderer) | "gles" (OpenGL ES, ogl/sdlogl DrawDevice)
  "icon": "icon/AppIcon-1024.png",// 1024x1024 PNG 1 枚 (任意)
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
