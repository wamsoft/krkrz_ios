// iosconfig プラグイン - 登録と continuous event hook、TJS クラス IosSystemMenu。
//
// hook で毎回やること:
//   - SDL のウィンドウができたらシステムメニューを取り付ける (1 回だけ)
//   - 初回だけ、保存済みの仮想パッド設定を VirtualPad へ反映する
//   - UI から積まれた TJS 呼び出しを実行する

#import "IosConfig.h"

#include "ncbind.hpp"

namespace {

class IosConfigHook : public tTVPContinuousEventCallbackIntf {
    bool mPadApplied = false;
public:
    void TJS_INTF_METHOD OnContinuousCallback(tjs_uint64 /*tick*/) override {
        iosconfig::InstallMenuIfReady();
        if (!mPadApplied) {
            mPadApplied = true;
            iosconfig::ApplyPadPrefs();
        }
        iosconfig::Drain();
    }
};
IosConfigHook *gHook = nullptr;

void registerPlugin() {
    if (!gHook) {
        gHook = new IosConfigHook();
        TVPAddContinuousEventHook(gHook);
    }
}

void unregisterPlugin() {
    if (gHook) {
        TVPRemoveContinuousEventHook(gHook);
        delete gHook;
        gHook = nullptr;
    }
    iosconfig::ShutdownMenu();
    iosconfig::ShutdownQueue();
}

// TJS: IosSystemMenu.open() / close() / openSettings() / openLicense() / isOpen / edgeSwipeEnabled
class IosSystemMenu {
public:
    static tjs_error Factory(IosSystemMenu ** /*obj*/, tjs_int /*np*/,
                             tTJSVariant ** /*p*/, iTJSDispatch2 * /*objthis*/) {
        TVPThrowExceptionMessage(TJSGetMessageMapMessage(TJS_W("TVPCannotCreateInstance")).c_str());
        return TJS_E_FAIL;
    }
    static void open() { iosconfig::OpenMenu(); }
    static void close() { iosconfig::CloseMenu(); }
    // メニューを経由せずに機能設定 / 権利情報を開く (タイトル画面のボタンなどから)
    static void openSettings() { iosconfig::CloseMenu(); iosconfig::OpenSettings(); }
    static void openLicense() { iosconfig::CloseMenu(); iosconfig::OpenLicense(); }
    static bool getIsOpen() { return iosconfig::IsMenuOpen(); }
    // 左端スワイプで開くか (既定 true)。ゲーム側で独自に開く場合などに切る
    static void setEdgeSwipeEnabled(bool enabled) { iosconfig::SetEdgeSwipeEnabled(enabled); }
};

} // namespace

NCB_REGISTER_CLASS(IosSystemMenu) {
    Factory(&Class::Factory);
    NCB_METHOD(open);
    NCB_METHOD(close);
    NCB_METHOD(openSettings);
    NCB_METHOD(openLicense);
    NCB_PROPERTY_RO(isOpen, getIsOpen);
    NCB_PROPERTY_WO(edgeSwipeEnabled, setEdgeSwipeEnabled);
}

NCB_REGISTER_CALLBACK(PreRegist,  registerPlugin,   0, registerIosConfig_0);
NCB_REGISTER_CALLBACK(PostRegist, 0, unregisterPlugin, unregisterIosConfig_0);
