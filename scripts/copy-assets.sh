#!/bin/sh
# Xcode の POST_BUILD から呼ばれ、assetPack のマージ結果をアプリバンドル直下へコピーする。
# 出力先は Xcode のビルド設定 (TARGET_BUILD_DIR / WRAPPER_NAME) から取る
# (CMake の $<TARGET_BUNDLE_DIR> は ${EFFECTIVE_PLATFORM_NAME} がエスケープされて展開されないため)。
# バンドル直下には実行ファイル等もあるので --delete はしない。
set -e
SRC="$1"
DST="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
rsync -a "$SRC/" "$DST/"
