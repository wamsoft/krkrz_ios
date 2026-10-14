# gamecenter プラグイン (iOS) - Game Center (GameKit) の TJS バインディング。
# TJS の GameCenter クラスは krkrz_android の PlayGames と同じ形 (manual.tjs)。
# ios-config.json の cmake.plugins に "gamecenter" を書くと、gen-config.py が
# Game Center の entitlement (com.apple.developer.game-center) を自動で付ける。
# Personal Team (無料) の署名では Game Center は使えない。

include(${KRKRZ_BASE}/krkrz_dev/src/plugins/tp_stub/krkrz.cmake)

krkrz_plugin(gamecenter
    NCBIND
    SOURCES
        GameCenter.mm
    LIBRARIES
        SDL3::SDL3
        "-framework GameKit"
        "-framework UIKit"
)

# ObjC++ (ARC)。Xcode ジェネレータでは言語別の生成式が効かないので属性でも指定する
target_compile_options(gamecenter PRIVATE -fobjc-arc)
set_target_properties(gamecenter PROPERTIES XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES)
