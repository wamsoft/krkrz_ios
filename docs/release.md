# 配布ビルド (Archive / ipa)

`make archive` / `make ipa` は開発用ビルドとは別の設定で Release ビルドを作る。

| | 開発用 (`make build`) | 配布用 (`make archive` / `make ipa`) |
|---|---|---|
| ビルドディレクトリ | `build/ios/<sdk>-<arch>` | `build/ios/dist` |
| 生成物 | `build/ios/generated` | `build/ios/generated-dist` |
| 構成 | Debug | Release |
| REPL (`-replweb`) | `ios-config.json` の `repl` (既定 true) | **常に無し** |
| エンジンの `MASTER` | OFF | **ON** (REPL / 統計 / メモリオーバーレイ等を除外、ログ既定 WARNING) |
| `NSLocalNetworkUsageDescription` | repl 有効時に自動追加 | 追加しない |

`ios-config.json` の `repl` を書き換える必要は無い (配布ビルドは設定に関係なく REPL を含めない)。

## 事前準備

1. `local.mk` に Team ID: `DEVELOPMENT_TEAM=XXXXXXXXXX`
2. Xcode > Settings > Accounts でその Team の Apple ID にサインイン
3. App Store / TestFlight / Ad Hoc に出す場合は有料の Apple Developer Program の Team が必要
   (Personal Team は `development` 書き出しのみ)
4. App Store Connect に出す場合は、App Store Connect 上にアプリ (Bundle ID) を登録しておく
5. `ios-config.json` の `version` (表示バージョン) と `build` (ビルド番号) を更新する。
   **`build` はアップロードごとに増やす** (同じ version 内で重複不可)

## 手順

```bash
make ipa                                     # development (開発用署名。登録済みデバイスに入る)
make ipa EXPORT_METHOD=release-testing       # Ad Hoc (登録済みデバイスへの配布)
make ipa EXPORT_METHOD=app-store-connect     # App Store Connect / TestFlight 提出用
PROJECT_DIR=/path/to/案件 make ipa EXPORT_METHOD=app-store-connect
```

- `make archive` … `build/ios/archive/krkrz.xcarchive` を作る (Xcode の Organizer でも開ける)
- `make ipa` … archive の後、`build/ios/ipa/` に ipa を書き出す。
  `ios-config.json` の `ipa.baseName` があれば `<baseName>-<version>-<build>[-<method>].ipa` に改名する
  (`app-store-connect` は method を付けない)

署名は自動 (`signingStyle: automatic`)。Xcode が必要な証明書・プロファイルを作る
(`-allowProvisioningUpdates`)。

## 書き出した ipa の使い道

| method | 使い道 |
|---|---|
| `development` | 開発用。`xcrun devicectl device install app --device <UDID> <ipa>` や Finder / Apple Configurator で、Team に登録済みのデバイスへ入れる |
| `release-testing` | Ad Hoc。登録済みデバイスへの配布 (社内テスト等) |
| `app-store-connect` | App Store Connect へアップロードし、TestFlight / 審査に出す |

App Store Connect へのアップロードは次のいずれか:

- **Transporter.app** (Mac App Store) に ipa をドラッグ
- Xcode の **Organizer** で `build/ios/archive/krkrz.xcarchive` を開き *Distribute App*
- コマンドライン: `xcrun altool --upload-app -f <ipa> -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>`
  (App Store Connect API キー。`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` に置く)

## 提出前チェックリスト

- [ ] `version` / `build` を更新した
- [ ] アイコン (1024x1024・アルファ無し) を設定した ([icon.md](icon.md))
- [ ] `displayName` (ホーム画面の名前) を確認した
- [ ] `orientations` / `devices` (iPhone / iPad) を確認した
- [ ] 実機で `make ipa` (development) を入れて起動・セーブ / ロード・音声を確認した
- [ ] 暗号化の申告: Info.plist の `ITSAppUsesNonExemptEncryption` は既定 false (独自暗号を使う場合は見直す)
- [ ] App Store Connect 側: プライバシー (データ収集の申告)、年齢レーティング、スクリーンショット
- [ ] 大容量データ (アプリサイズ上限に近い場合) は Background Assets 対応が必要 (未対応)

## トラブルシュート

- **`errSecInternalComponent`** (署名時): README「実機ビルドの初回準備」の
  `security set-key-partition-list` を一度実行する
- **`No profiles for ... were found`**: Xcode にサインインしているか、Team ID が合っているか、
  (development / Ad Hoc の場合) デバイスが Team に登録されているかを確認。
  デバイス登録は `make build SDK=device DEVICE=<UDID>` を一度通すと自動で行われる
- **Archive が «Generic Xcode Archive» になる / ipa 書き出しに失敗する**: アプリ以外のターゲットが
  Archive に入っている。CMakeLists.txt で `CMAKE_XCODE_ATTRIBUTE_SKIP_INSTALL=YES`、アプリ本体のみ `NO`
  にしている (cmake/KrkrzIOS.cmake)
