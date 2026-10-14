// iosconfig - 設定画面 / 権利情報画面 (UIKit)。

#pragma once

#import <UIKit/UIKit.h>

// 機能設定画面 (krkrz_android の SettingsActivity 相当)。
// 前半は仮想パッド (virtualpad プラグインがあるときだけ)、後半は TJS
// (KrkrzAndroidGetConfig) から取得した項目を動的に並べる。音量はスライダー操作の
// たびに即時反映、それ以外は画面を閉じるときに KrkrzAndroidSetConfig でまとめて渡す。
@interface KrkrzSettingsViewController : UIViewController
@end

// 権利情報画面 (krkrz_android の LicenseActivity 相当)。TVPGetLicenseString() を表示する。
@interface KrkrzLicenseViewController : UIViewController
@end
