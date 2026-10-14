# iOS 固有プラグイン

`plugins/` にある iOS 専用のプラグインの使い方です。どれも静的リンクで、`ios-config.json` の
`cmake.plugins` に名前を書くと組み込まれます。`cmake.pluginFolders` に `${BUILD_SYSTEM_DIR}/plugins` が必要です
(リポジトリ直下のサンプル `ios-config.json` を参照)。

```jsonc
"cmake": {
  "pluginFolders": [ "${BUILD_SYSTEM_DIR}/plugins", "${KRKRZ_BASE}/krkrz_dev/src/plugins" ],
  "plugins": [ "json", "virtualpad", "iosconfig" ]
}
```

## virtualpad — 仮想パッド

画面に半透明の仮想パッド (十字 / A・B・X・Y / L・R) を出し、タッチを SDL の仮想ジョイスティックへ流します。
エンジンからは普通のゲームパッド入力 (`VK_PAD*`) として届きます。パッドに当たらなかったタッチは、
そのままゲーム (マウス / タッチ) へ渡ります。ボタンの配置はセーフエリア (ノッチ・ホームインジケータ) を避けます。

```
VirtualPad.setEnabled(true);    // 表示して入力を受ける / false で隠す
VirtualPad.setOpacity(0.55);    // 不透明度 0.0-1.0
VirtualPad.setPreset(n);        // ボタン配置のプリセット
```

仮想パッドを使うのは iOS と Android だけなので、ソース (`VirtualPad.cpp` / `VirtualPad.h` / `Main.cpp`) は
krkrz_android の `app/src/main/cpp/virtualpad/` と同じ内容で管理します。片方を直したら、もう片方にも同じ変更を入れてください。

## iosconfig — システムメニュー・機能設定画面・権利情報画面

krkrz_android のシステムメニューに相当するものです。画面の左端から右へスワイプすると、左からメニューが出ます。

- 機能設定: 仮想パッドの ON/OFF と不透明度 (端末に保存し、起動時に反映) と、ゲーム側の設定項目
- 権利情報: エンジンと使っているライブラリのライセンス表記 (`TVPGetLicenseString()`)
- ほかのプラグインが足した項目 (`gamecenter` など)

ゲーム側の設定は krkrz_android と同じ TJS のグローバル関数で受け渡します。

| 関数 | 役割 |
|---|---|
| `KrkrzAndroidGetConfig()` | 設定画面に並べる項目の一覧を返す |
| `KrkrzAndroidSetConfig(dict)` | 設定画面で変えた値を受け取る |
| `KrkrzAndroidGetVolume()` / `KrkrzAndroidSetVolume(dict)` | 音量の取得と設定 |

関数が定義されていなければ、設定画面にその旨が出るだけです。引数と戻り値の形は krkrz_android の
`app/src/main/cpp/androidconfig/manual.tjs` と同じです。

TJS から操作する API:

```
IosSystemMenu.open();            // システムメニューを開く / close() で閉じる
IosSystemMenu.openSettings();    // 機能設定画面を直接開く
IosSystemMenu.openLicense();     // 権利情報画面を直接開く
IosSystemMenu.isOpen             // メニューが開いているか
IosSystemMenu.edgeSwipeEnabled = false;   // 左端スワイプで開かないようにする
```

ほかのプラグインは、Objective-C の `NSClassFromString(@"KrkrzSystemMenu")` に
`+addItemWithIdentifier:title:action:` を送ってメニューに項目を足せます (`iosconfig` が無ければ何もしない)。

表示する文字列は krkrz_android の `strings.xml` から `plugins/iosconfig/gen-strings.py` で
`Strings.inc` を生成しています (en / ja / zh-Hans / zh-Hant)。
