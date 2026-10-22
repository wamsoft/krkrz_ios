// gamecenter プラグイン - Game Center (GameKit) の TJS バインディング。
//
// TJS の static クラス GameCenter は krkrz_android の PlayGames と同じメソッド名・
// 同じ callback 形式 (function cb(result, error)。成功時 error=void、失敗時 result=void)
// にしてある。ゲーム側は実績 ID の違いだけ吸収すれば同じコードで呼べる。
// API は manual.tjs を参照。
//
// スレッド: GameKit の完了ハンドラは任意のスレッドで呼ばれるので、メインスレッドへ
// 戻してからキューに積み、continuous event hook で TJS の callback を呼ぶ。

#import <GameKit/GameKit.h>
#import <UIKit/UIKit.h>

#include "tp_stub.h"
#include "ncbind.hpp"

#include <SDL3/SDL.h>

#include <vector>

static_assert(sizeof(tjs_char) == sizeof(unichar), "tjs_char must be UTF-16");

namespace {

// ============================================================
// 文字列 / 値
// ============================================================

NSString *ToNS(const ttstr &s) {
    if (s.IsEmpty()) return @"";
    return [NSString stringWithCharacters:(const unichar *)s.c_str() length:s.length()];
}

ttstr ToTt(NSString *s) {
    if (s.length == 0) return ttstr();
    std::vector<unichar> buf(s.length);
    [s getCharacters:buf.data() range:NSMakeRange(0, s.length)];
    return ttstr((const tjs_char *)buf.data(), (int)buf.size());
}

tTJSVariant ErrorVariant(NSError *err, NSString *fallback) {
    NSString *msg = err.localizedDescription ?: fallback;
    return tTJSVariant(ToTt(msg ?: @"unknown error"));
}

// ============================================================
// callback キュー
// ============================================================

NSMutableArray *gQueue;

// メインスレッドから呼ぶ
void Post(void (^block)(void)) {
    if (!gQueue) gQueue = [NSMutableArray array];
    [gQueue addObject:[block copy]];
}

// どのスレッドからでも呼べる
void PostFromAny(void (^block)(void)) {
    void (^b)(void) = [block copy];
    if (NSThread.isMainThread) {
        Post(b);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ Post(b); });
    }
}

void Drain() {
    if (gQueue.count == 0) return;
    NSArray *local = gQueue;
    gQueue = [NSMutableArray array];
    for (void (^block)(void) in local) {
        try {
            block();
        } catch (...) {
            TVPAddLog(TJS_W("gamecenter: callback threw"));
        }
    }
}

// TJS の callback。void (省略) なら何もしない (fire-and-forget)
struct Callback {
    tTJSVariant fn;
    explicit Callback(const tTJSVariant &v) : fn(v) {}
    bool empty() const { return fn.Type() != tvtObject || !fn.AsObjectNoAddRef(); }
    void operator()(const tTJSVariant &result, const tTJSVariant &error) const {
        if (empty()) return;
        tTJSVariant r = result, e = error;
        tTJSVariant *args[2] = { &r, &e };
        tTJSVariantClosure clo = fn.AsObjectClosureNoAddRef();
        clo.FuncCall(0, nullptr, nullptr, nullptr, 2, args, nullptr);
    }
};

// 成功 / 失敗を (メインスレッドへ戻して) 次の continuous event で返す
void Resolve(const Callback &cb, const tTJSVariant &result) {
    if (cb.empty()) return;
    Callback c = cb;
    tTJSVariant r = result;
    PostFromAny(^{ c(r, tTJSVariant()); });
}

void Reject(const Callback &cb, NSError *err, NSString *fallback) {
    if (cb.empty()) return;
    Callback c = cb;
    tTJSVariant e = ErrorVariant(err, fallback);
    PostFromAny(^{ c(tTJSVariant(), e); });
}

// ============================================================
// 画面
// ============================================================

UIViewController *FindPresenter() {
    // iosconfig プラグインがあればそれに合わせる (無くても動く)
    Class menu = NSClassFromString(@"KrkrzSystemMenu");
    SEL sel = @selector(presentingViewController);
    if ([menu respondsToSelector:sel]) {
        using GetFn = UIViewController *(*)(id, SEL);
        UIViewController *vc = ((GetFn)[menu methodForSelector:sel])(menu, sel);
        if (vc) return vc;
    }
    UIViewController *vc = nil;
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    if (windows) {
        for (int i = 0; i < count && !vc; ++i) {
            UIWindow *w = (__bridge UIWindow *)SDL_GetPointerProperty(
                SDL_GetWindowProperties(windows[i]), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
            vc = w.rootViewController;
        }
        SDL_free(windows);
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

} // namespace

@interface KrkrzGameCenterDismisser : NSObject <GKGameCenterControllerDelegate>
@end
@implementation KrkrzGameCenterDismisser
- (void)gameCenterViewControllerDidFinish:(GKGameCenterViewController *)vc {
    [vc dismissViewControllerAnimated:YES completion:nil];
}
@end

namespace {

KrkrzGameCenterDismisser *gDismisser;

bool ShowGameCenterUI(GKGameCenterViewControllerState state) {
    UIViewController *presenter = FindPresenter();
    if (!presenter) return false;
    if (!gDismisser) gDismisser = [[KrkrzGameCenterDismisser alloc] init];
    GKGameCenterViewController *vc = [[GKGameCenterViewController alloc] initWithState:state];
    vc.gameCenterDelegate = gDismisser;
    [presenter presentViewController:vc animated:YES completion:nil];
    return true;
}

// ============================================================
// 認証
// ============================================================
//
// 起動直後に authenticateHandler を設定すると GameKit が自動でサインインを試みる
// (Play Games v2 の自動 silent sign-in に相当)。サインイン画面が必要な場合は
// handler に viewController が渡るので、signIn() が呼ばれたときに表示する。

bool gAuthStarted = false;
bool gAuthDone = false;            // handler が一度でも呼ばれた
UIViewController *gAuthVC;         // 表示待ちのサインイン画面
NSError *gAuthError;
std::vector<Callback> gWaitAuthenticated;   // isAuthenticated の結果待ち
std::vector<Callback> gWaitSignIn;          // signIn の結果待ち
bool gSignInRequested = false;
constexpr double kAuthWaitSec = 10.0;

bool IsAuthenticated() {
    return GKLocalPlayer.localPlayer.isAuthenticated;
}

void PresentAuthVC() {
    UIViewController *presenter = FindPresenter();
    if (!gAuthVC || !presenter) return;
    UIViewController *vc = gAuthVC;
    gAuthVC = nil;
    [presenter presentViewController:vc animated:YES completion:nil];
}

// 認証の結果を callback へ返す。端末で Game Center にサインインしていても、アプリが
// Game Center に登録されていない (App Store Connect で未設定など) と handler にエラーが来て
// 実績などは使えない。そのときは false ではなくエラーとして返し、原因が分かるようにする
void ResolveAuthState(const Callback &cb) {
    if (gAuthError && gAuthError.code == GKErrorGameUnrecognized)
        Reject(cb, gAuthError, @"This app is not recognized by Game Center");
    else
        Resolve(cb, tTJSVariant((tjs_int)(IsAuthenticated() ? 1 : 0)));
}

void FlushAuthWaiters() {
    for (auto &cb : gWaitAuthenticated) ResolveAuthState(cb);
    gWaitAuthenticated.clear();
}

void FlushSignInWaiters() {
    bool ok = IsAuthenticated();
    for (auto &cb : gWaitSignIn) {
        if (ok) Resolve(cb, tTJSVariant((tjs_int)1));
        else Reject(cb, gAuthError, @"Game Center sign-in failed");
    }
    gWaitSignIn.clear();
    gSignInRequested = false;
}

void StartAuthentication() {
    if (gAuthStarted) return;
    gAuthStarted = true;
    GKLocalPlayer.localPlayer.authenticateHandler = ^(UIViewController *vc, NSError *error) {
        // メインスレッドで呼ばれる
        gAuthDone = true;
        gAuthError = error;
        if (vc) {
            gAuthVC = vc;
            if (gSignInRequested) PresentAuthVC();
        } else {
            gAuthVC = nil;
            FlushSignInWaiters();
        }
        if (error) TVPAddLog(ttstr(TJS_W("gamecenter: auth: ")) + ToTt(error.localizedDescription));
        FlushAuthWaiters();
    };
}

// ============================================================
// 実績
// ============================================================

// identifier -> GKAchievement (報告済みのもの)
void LoadReported(void (^done)(NSDictionary<NSString *, GKAchievement *> *, NSError *)) {
    [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray<GKAchievement *> *list, NSError *err) {
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (GKAchievement *a in list) map[a.identifier] = a;
        done(map, err);
    }];
}

void ReportPercent(const Callback &cb, NSString *ident, double percent) {
    if (percent > 100) percent = 100;
    if (percent < 0) percent = 0;
    GKAchievement *a = [[GKAchievement alloc] initWithIdentifier:ident];
    a.percentComplete = percent;
    a.showsCompletionBanner = YES;
    Callback c = cb;
    [GKAchievement reportAchievements:@[ a ] withCompletionHandler:^(NSError *err) {
        if (err) Reject(c, err, nil);
        else Resolve(c, tTJSVariant((tjs_int)(percent >= 100 ? 1 : 0)));
    }];
}

tTJSVariant MakeAchievementDict(GKAchievementDescription *d, GKAchievement *a) {
    iTJSDispatch2 *dsp = TJSCreateDictionaryObject();
    ncbPropAccessor acc(dsp);
    bool completed = a.completed;
    double percent = a ? a.percentComplete : 0;
    // state は PlayGames と同じ 0=unlocked, 1=revealed, 2=hidden
    tjs_int state = completed ? 0 : ((d.hidden && percent <= 0) ? 2 : 1);
    acc.SetValue(TJS_W("achievementId"), ToTt(d.identifier));
    acc.SetValue(TJS_W("name"), ToTt(d.title));
    acc.SetValue(TJS_W("description"), ToTt(completed ? d.achievedDescription : d.unachievedDescription));
    acc.SetValue(TJS_W("state"), state);
    acc.SetValue(TJS_W("type"), (tjs_int)0);   // Game Center に段階型は無い (達成率で表す)
    acc.SetValue(TJS_W("xp"), (tjs_int)d.maximumPoints);
    acc.SetValue(TJS_W("percentComplete"), (tTVReal)percent);   // Game Center のみ
    if (completed && a.lastReportedDate) {
        acc.SetValue(TJS_W("unlockedTimestamp"),
                     (tTVInteger)(a.lastReportedDate.timeIntervalSince1970 * 1000.0));
    }
    tTJSVariant v(dsp, dsp);
    dsp->Release();
    return v;
}

void LoadAchievements(const Callback &cb) {
    Callback c = cb;
    [GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:
        ^(NSArray<GKAchievementDescription *> *descs, NSError *err) {
        if (err) {
            Reject(c, err, nil);
            return;
        }
        LoadReported(^(NSDictionary<NSString *, GKAchievement *> *reported, NSError *err2) {
            if (err2) {
                Reject(c, err2, nil);
                return;
            }
            NSArray *descCopy = [descs copy];
            NSDictionary *repCopy = [reported copy];
            PostFromAny(^{
                // TJS オブジェクトはメインスレッド (drain 中) で作る
                iTJSDispatch2 *arr = TJSCreateArrayObject();
                ncbPropAccessor acc(arr);
                tjs_int i = 0;
                for (GKAchievementDescription *d in descCopy) {
                    acc.SetValue(i++, MakeAchievementDict(d, repCopy[d.identifier]));
                }
                tTJSVariant list(arr, arr);
                arr->Release();
                c(list, tTJSVariant());
            });
        });
    }];
}

// ============================================================
// TJS クラス
// ============================================================

tjs_error NotSupported(tTJSVariant *result, tjs_int numparams, tTJSVariant **param) {
    if (numparams >= 1 && param[0]) {
        Reject(Callback(*param[0]), nil, @"not supported on Game Center");
    }
    if (result) *result = false;
    return TJS_S_OK;
}

class GameCenter {
public:
    static tjs_error Factory(GameCenter ** /*obj*/, tjs_int /*np*/,
                             tTJSVariant ** /*p*/, iTJSDispatch2 * /*objthis*/) {
        TVPThrowExceptionMessage(TJSGetMessageMapMessage(TJS_W("TVPCannotCreateInstance")).c_str());
        return TJS_E_FAIL;
    }

    // ---- 認証 ----

    static void isAuthenticated(tTJSVariant cb) {
        StartAuthentication();
        Callback c(cb);
        if (gAuthDone) {
            ResolveAuthState(c);
            return;
        }
        gWaitAuthenticated.push_back(c);
        // GameKit が handler を呼ばないまま止まることがある (Game Center に繋がらない環境など)。
        // 待たせ続けないよう、一定時間で現在の状態を返す
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAuthWaitSec * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ FlushAuthWaiters(); });
    }

    static void signIn(tTJSVariant cb) {
        StartAuthentication();
        Callback c(cb);
        if (gAuthDone && gAuthError && gAuthError.code == GKErrorGameUnrecognized) {
            ResolveAuthState(c);
            return;
        }
        if (IsAuthenticated()) {
            Resolve(c, tTJSVariant((tjs_int)1));
            return;
        }
        if (gAuthDone && !gAuthVC) {
            // サインイン画面が出せない (取り消し済み / 無効)。設定アプリからのサインインが必要
            Reject(c, gAuthError, @"Game Center is unavailable. Sign in from the Settings app.");
            return;
        }
        gWaitSignIn.push_back(c);
        gSignInRequested = true;
        if (gAuthVC) PresentAuthVC();
    }

    static void getCurrentPlayer(tTJSVariant cb) {
        Callback c(cb);
        GKLocalPlayer *p = GKLocalPlayer.localPlayer;
        if (!p.isAuthenticated) {
            Reject(c, nil, @"not authenticated");
            return;
        }
        iTJSDispatch2 *dsp = TJSCreateDictionaryObject();
        ncbPropAccessor acc(dsp);
        acc.SetValue(TJS_W("playerId"), ToTt(p.gamePlayerID));
        acc.SetValue(TJS_W("displayName"), ToTt(p.displayName));
        acc.SetValue(TJS_W("title"), ToTt(p.alias));
        tTJSVariant v(dsp, dsp);
        dsp->Release();
        Resolve(c, v);
    }

    // ---- 実績 ----

    // loadAchievements(cb, forceReload=false)。Game Center は常にサーバーから取る
    static tjs_error TJS_INTF_METHOD loadAchievements(tTJSVariant *result, tjs_int numparams,
                                                      tTJSVariant **param, iTJSDispatch2 *) {
        if (numparams < 1) return TJS_E_BADPARAMCOUNT;
        LoadAchievements(Callback(*param[0]));
        if (result) *result = true;
        return TJS_S_OK;
    }

    // unlockAchievement(cb, achievementId)。cb が void なら fire-and-forget
    static void unlockAchievement(tTJSVariant cb, ttstr achievementId) {
        ReportPercent(Callback(cb), ToNS(achievementId), 100);
    }

    // incrementAchievement(cb, achievementId, numSteps, totalSteps=100)
    // Game Center は達成率 (0-100%) なので numSteps / totalSteps を達成率に換算して加算する
    static tjs_error TJS_INTF_METHOD incrementAchievement(tTJSVariant *result, tjs_int numparams,
                                                          tTJSVariant **param, iTJSDispatch2 *) {
        if (numparams < 3) return TJS_E_BADPARAMCOUNT;
        Callback c(*param[0]);
        NSString *ident = ToNS(ttstr(*param[1]));
        double steps = (tTVReal)*param[2];
        double total = (numparams >= 4 && param[3]->Type() != tvtVoid) ? (tTVReal)*param[3] : 100.0;
        if (total <= 0) total = 100.0;
        LoadReported(^(NSDictionary<NSString *, GKAchievement *> *reported, NSError *err) {
            if (err) {
                Reject(c, err, nil);
                return;
            }
            double cur = reported[ident].percentComplete;
            dispatch_async(dispatch_get_main_queue(), ^{
                ReportPercent(c, ident, cur + steps * 100.0 / total);
            });
        });
        if (result) *result = true;
        return TJS_S_OK;
    }

    // setStepsAchievement(cb, achievementId, numSteps, totalSteps=100)
    static tjs_error TJS_INTF_METHOD setStepsAchievement(tTJSVariant *result, tjs_int numparams,
                                                         tTJSVariant **param, iTJSDispatch2 *) {
        if (numparams < 3) return TJS_E_BADPARAMCOUNT;
        double steps = (tTVReal)*param[2];
        double total = (numparams >= 4 && param[3]->Type() != tvtVoid) ? (tTVReal)*param[3] : 100.0;
        if (total <= 0) total = 100.0;
        ReportPercent(Callback(*param[0]), ToNS(ttstr(*param[1])), steps * 100.0 / total);
        if (result) *result = true;
        return TJS_S_OK;
    }

    static void showAchievementsUI(tTJSVariant cb) {
        Callback c(cb);
        if (ShowGameCenterUI(GKGameCenterViewControllerStateAchievements)) Resolve(c, tTJSVariant((tjs_int)1));
        else Reject(c, nil, @"cannot present Game Center UI");
    }

    // Game Center のダッシュボード (Game Center のみ)
    static void showDashboard(tTJSVariant cb) {
        Callback c(cb);
        if (ShowGameCenterUI(GKGameCenterViewControllerStateDefault)) Resolve(c, tTJSVariant((tjs_int)1));
        else Reject(c, nil, @"cannot present Game Center UI");
    }

    // 実績の進捗をすべて消す (開発用)
    static void resetAchievements(tTJSVariant cb) {
        Callback c(cb);
        [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *err) {
            if (err) Reject(c, err, nil);
            else Resolve(c, tTJSVariant((tjs_int)1));
        }];
    }

    // ---- セーブゲーム: 未対応 (PlayGames と同じ名前で、callback にエラーを返す) ----

    static tjs_error TJS_INTF_METHOD listSnapshots(tTJSVariant *r, tjs_int n, tTJSVariant **p, iTJSDispatch2 *) { return NotSupported(r, n, p); }
    static tjs_error TJS_INTF_METHOD readSnapshot(tTJSVariant *r, tjs_int n, tTJSVariant **p, iTJSDispatch2 *) { return NotSupported(r, n, p); }
    static tjs_error TJS_INTF_METHOD writeSnapshot(tTJSVariant *r, tjs_int n, tTJSVariant **p, iTJSDispatch2 *) { return NotSupported(r, n, p); }
    static tjs_error TJS_INTF_METHOD deleteSnapshot(tTJSVariant *r, tjs_int n, tTJSVariant **p, iTJSDispatch2 *) { return NotSupported(r, n, p); }
    static tjs_error TJS_INTF_METHOD showSnapshotsUI(tTJSVariant *r, tjs_int n, tTJSVariant **p, iTJSDispatch2 *) { return NotSupported(r, n, p); }
};

// ============================================================
// プラグイン登録
// ============================================================

class GameCenterHook : public tTVPContinuousEventCallbackIntf {
    bool mMenuAdded = false;
public:
    void TJS_INTF_METHOD OnContinuousCallback(tjs_uint64 /*tick*/) override {
        StartAuthentication();
        if (!mMenuAdded) {
            // iosconfig のシステムメニューがあれば「Game Center」を足す
            mMenuAdded = true;
            Class menu = NSClassFromString(@"KrkrzSystemMenu");
            SEL sel = @selector(addItemWithIdentifier:title:action:);
            if ([menu respondsToSelector:sel]) {
                void (^action)(void) = ^{ ShowGameCenterUI(GKGameCenterViewControllerStateDefault); };
                using AddFn = void (*)(id, SEL, NSString *, NSString *, void (^)(void));
                ((AddFn)[menu methodForSelector:sel])(menu, sel, @"gamecenter", @"Game Center", action);
            }
        }
        Drain();
    }
};
GameCenterHook *gHook = nullptr;

void registerPlugin() {
    if (!gHook) {
        gHook = new GameCenterHook();
        TVPAddContinuousEventHook(gHook);
    }
}

void unregisterPlugin() {
    if (gHook) {
        TVPRemoveContinuousEventHook(gHook);
        delete gHook;
        gHook = nullptr;
    }
    gQueue = nil;
    gWaitAuthenticated.clear();
    gWaitSignIn.clear();
}

} // namespace

NCB_REGISTER_CLASS(GameCenter) {
    Factory(&Class::Factory);
    NCB_METHOD(isAuthenticated);
    NCB_METHOD(signIn);
    NCB_METHOD(getCurrentPlayer);

    RawCallback("loadAchievements",     &Class::loadAchievements,     TJS_STATICMEMBER);
    NCB_METHOD(unlockAchievement);
    RawCallback("incrementAchievement", &Class::incrementAchievement, TJS_STATICMEMBER);
    RawCallback("setStepsAchievement",  &Class::setStepsAchievement,  TJS_STATICMEMBER);
    NCB_METHOD(showAchievementsUI);
    NCB_METHOD(showDashboard);
    NCB_METHOD(resetAchievements);

    RawCallback("listSnapshots",        &Class::listSnapshots,        TJS_STATICMEMBER);
    RawCallback("readSnapshot",         &Class::readSnapshot,         TJS_STATICMEMBER);
    RawCallback("writeSnapshot",        &Class::writeSnapshot,        TJS_STATICMEMBER);
    RawCallback("deleteSnapshot",       &Class::deleteSnapshot,       TJS_STATICMEMBER);
    RawCallback("showSnapshotsUI",      &Class::showSnapshotsUI,      TJS_STATICMEMBER);
}

NCB_REGISTER_CALLBACK(PreRegist,  registerPlugin,   0, registerGameCenter_0);
NCB_REGISTER_CALLBACK(PostRegist, 0, unregisterPlugin, unregisterGameCenter_0);
