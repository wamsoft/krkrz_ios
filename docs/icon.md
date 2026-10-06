# アプリアイコン

iOS のアプリアイコンは **1024x1024 の PNG 1 枚** から作る (Xcode 14 以降の単一サイズ方式)。
ホーム画面・設定・Spotlight・App Store などの各サイズは Xcode がビルド時に縮小して作る。

## 置き場所と設定

案件フォルダにアイコンを置き、`ios-config.json` の `icon` で指定する
(パスは `PROJECT_DIR` 基準。`${BUILD_SYSTEM_DIR}` 等の変数も使える)。

```
<案件>/
├── ios-config.json
└── icon/
    ├── AppIcon-1024.png          … 通常 (必須)
    ├── AppIcon-1024-dark.png     … ダーク外観 (任意, iOS 18+)
    └── AppIcon-1024-tinted.png   … ティント外観 (任意, iOS 18+)
```

```jsonc
// 1 枚だけ
"icon": "icon/AppIcon-1024.png"

// iOS 18 のダーク / ティント外観も用意する場合
"icon": {
  "default": "icon/AppIcon-1024.png",
  "dark":    "icon/AppIcon-1024-dark.png",
  "tinted":  "icon/AppIcon-1024-tinted.png"
}
```

`icon` を省略するとアイコン無し (Xcode の既定の白いアイコン) になる。
ビルド時に `scripts/gen-config.py` が `build/ios/generated/Assets.xcassets/AppIcon.appiconset`
を生成し、アプリに組み込まれる。

このリポジトリのサンプルは `icon/AppIcon-1024.png` (元データ `icon/AppIcon.svg`。
krkrz_android のランチャーアイコンと同じ素材)。

## 画像の要件

| 項目 | 要件 |
|---|---|
| サイズ | 1024x1024 px ちょうど (違うとビルド時にエラー) |
| 形式 | PNG。sRGB / Display P3 |
| 透過 | **通常アイコンはアルファチャンネル無し** (App Store がアルファ付きを拒否する。ビルド時に警告を出す) |
| 角丸 | 付けない (正方形で塗りつぶす。角丸マスクは OS がかける) |
| 余白 | 重要な要素は中央寄りに (角丸で四隅が欠ける) |
| ダーク | 背景を透過 (アルファ可) にし、前景だけを描く。OS が暗い背景を敷く |
| ティント | グレースケールの前景のみ (アルファ可)。OS がユーザーの選んだ色で着色する |

## アルファチャンネルの外し方

アルファ付きの PNG しか無い場合、macOS 標準の `sips` で外せる
(JPEG を経由するので、気になる場合は画像編集ツールで背景を塗って書き出す)。

```bash
sips -s format jpeg -s formatOptions 100 in.png --out /tmp/icon.jpg
sips -s format png /tmp/icon.jpg --out icon/AppIcon-1024.png
sips -g pixelWidth -g pixelHeight -g hasAlpha icon/AppIcon-1024.png   # hasAlpha: no を確認
```

SVG から作る場合 (Quick Look で描画。SVG の width / height を 1024 にしておく):

```bash
qlmanage -t -s 1024 -o /tmp icon.svg     # → /tmp/icon.svg.png
```

## 注意

- アイコンの反映にはビルドが必要 (`make build` / `make ipa`)。端末側でアイコンが古いまま
  見えるときは、アプリを一度削除して入れ直す。
- 起動画面 (Launch Screen) は Info.plist の `UILaunchScreen` で、現状は黒の単色。
  画像やロゴを出したい場合は `infoPlist` で `UILaunchScreen` の `UIImageName` /
  `UIColorName` を指定し、対応する画像 / 色をアセットカタログに追加する (未対応、要拡張)。
