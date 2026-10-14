# iosconfig プラグイン (iOS) - システムメニュー / 機能設定画面 / 権利情報 (UIKit)。
# krkrz_android の drawer + SettingsActivity + LicenseActivity + androidconfig 相当。
# ゲーム設定の受け渡しは Android と同じ TJS 関数 (KrkrzAndroidGetConfig ほか) を呼ぶ。
# 文言は Android の strings.xml から gen-strings.py で Strings.inc を生成している。

include(${KRKRZ_BASE}/krkrz_dev/src/plugins/tp_stub/krkrz.cmake)

krkrz_plugin(iosconfig
    NCBIND
    SOURCES
        Main.mm
        TjsBridge.mm
        Strings.mm
        SystemMenu.mm
        SettingsViewController.mm
    LIBRARIES
        SDL3::SDL3
        "-framework UIKit"
)

# 全ソース ObjC++ (ARC)。Xcode ジェネレータでは言語別の生成式が効かないので属性でも指定する
target_compile_options(iosconfig PRIVATE -fobjc-arc)
set_target_properties(iosconfig PROPERTIES XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES)
