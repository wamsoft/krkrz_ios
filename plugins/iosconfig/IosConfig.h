// iosconfig プラグイン - システムメニュー (左端スワイプで開くパネル) / 設定画面 / 権利情報。
// krkrz_android の drawer + SettingsActivity + LicenseActivity + androidconfig 相当。
//
// スレッド: iOS は SDL のメインコールバックで TJS も UIKit もメインスレッドで動く。
// ただし UIKit のイベント処理中に TJS を直接呼ぶと TJS 実行の途中に割り込む形になり
// うるので、TJS 呼び出しは Android と同じくキューに積み、continuous event hook
// (TJS のイベント処理の区切り) でまとめて実行する (iosconfig::Post)。

#pragma once

#import <Foundation/Foundation.h>

#include "tp_stub.h"

namespace iosconfig {

// ---- TJS 呼び出しキュー (TjsBridge.mm) ----

// block を次の continuous event で実行する (メインスレッドから呼ぶ)。
void Post(void (^block)(void));
// continuous event hook から呼ばれる。
void Drain();
void ShutdownQueue();

// global.<name>(params...) を呼ぶ。関数が無ければ false。
bool CallGlobal(const tjs_char *name, tjs_int numparams, tTJSVariant **params, tTJSVariant *result);
// global.<objName>.<method>(params...) を呼ぶ。オブジェクト / メソッドが無ければ false。
bool CallGlobalMethod(const tjs_char *objName, const tjs_char *method,
                      tjs_int numparams, tTJSVariant **params, tTJSVariant *result);
// global.<name> が定義されているか。
bool HasGlobal(const tjs_char *name);

NSString *ToNSString(const ttstr &s);
ttstr ToTtstr(NSString *s);

// ---- ゲーム設定 (Android の androidconfig と同じ TJS 関数を呼ぶ) ----

// KrkrzAndroidGetConfig() と各音量を取得する。config は関数が無ければ nil。
// volumes は "master" 等 / "charVoice:<名前>" → NSNumber(0-100)。
void FetchConfig(void (^done)(NSDictionary<NSString *, id> *config,
                              NSDictionary<NSString *, NSNumber *> *volumes));
void ApplyConfig(NSDictionary<NSString *, id> *edited);   // KrkrzAndroidSetConfig(dict)
void SetVolume(NSString *key, int value);                 // KrkrzAndroidSetVolume(key, value)

// ---- 仮想パッド設定 (NSUserDefaults に保存し、TJS の VirtualPad へ反映) ----

constexpr int kPadOpacityMin = 10;
constexpr int kPadOpacityMax = 100;
constexpr int kPadOpacityDefault = 55;

bool PadAvailable();                 // virtualpad プラグインが入っているか (TJS の VirtualPad)
bool PadEnabled();
int  PadOpacityPercent();
void SetPadEnabled(bool enabled);    // 保存 + 反映
void SetPadOpacityPercent(int pct);  // 保存 + 反映
void ApplyPadPrefs();                // 起動時に保存値を反映

// ---- 文言 (Strings.mm。Android の strings.xml と同じキー) ----

NSString *L(NSString *key);

// ---- システムメニュー (SystemMenu.mm) ----

void InstallMenuIfReady();   // SDL のウィンドウができていればジェスチャ等を取り付ける
void OpenMenu();
void OpenSettings();
void OpenLicense();
void CloseMenu();
bool IsMenuOpen();
void SetEdgeSwipeEnabled(bool enabled);
void ShutdownMenu();

} // namespace iosconfig
