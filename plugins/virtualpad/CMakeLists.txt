# VirtualPad プラグイン (iOS) - 半透明の仮想パッドを描画し、タッチを SDL 仮想ジョイスティックへ流す。
#
# VirtualPad.cpp / VirtualPad.h / Main.cpp は krkrz_android の
# app/src/main/cpp/virtualpad/ と同一内容で管理する (仮想パッドは iOS / Android
# だけの機能なので krkrz_dev には置かない)。どちらかを直したらもう一方へ写すこと。
# 差があるのはビルド設定と、Android の JniBridge.cpp (Java 側設定画面との橋渡し) だけ。

include(${KRKRZ_BASE}/krkrz_dev/src/plugins/tp_stub/krkrz.cmake)

krkrz_plugin(virtualpad
    NCBIND
    SOURCES
        Main.cpp
        VirtualPad.cpp
    LIBRARIES
        SDL3::SDL3
)

# エンジンの glad GLES2 ローダのヘッダ。GL 関数ポインタはエンジン側でロード済みの
# ものを共用する (静的プラグインなのでアプリ本体の glad シンボルにそのまま乗る)。
target_include_directories(virtualpad PRIVATE
    ${KRKRZ_BASE}/krkrz_dev/src/core/common/glad/include)
