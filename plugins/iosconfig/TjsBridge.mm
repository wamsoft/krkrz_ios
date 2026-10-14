// iosconfig - TJS 呼び出しキューと、ゲーム設定 / 仮想パッド設定の受け渡し。
//
// ゲーム設定は krkrz_android の androidconfig と同じ TJS グローバル関数を呼ぶ
// (ゲームスクリプトを両 OS で共通にするため名前も Android のまま):
//   KrkrzAndroidGetConfig()            -> Dictionary
//   KrkrzAndroidSetConfig(dict)        -> void
//   KrkrzAndroidGetVolume(key)         -> int (0-100)
//   KrkrzAndroidSetVolume(key, value)  -> void
// いずれも「定義されていれば呼ぶ」。契約の詳細は krkrz_android の
// app/src/main/cpp/androidconfig/manual.tjs。

#import "IosConfig.h"

#include "ncbind.hpp"

#include <vector>

static_assert(sizeof(tjs_char) == sizeof(unichar), "tjs_char must be UTF-16");

namespace iosconfig {

// ============================================================
// キュー
// ============================================================

static NSMutableArray *gQueue;

void Post(void (^block)(void)) {
    if (!block) return;
    if (!gQueue) gQueue = [NSMutableArray array];
    [gQueue addObject:[block copy]];
}

void Drain() {
    if (gQueue.count == 0) return;
    NSArray *local = gQueue;
    gQueue = [NSMutableArray array];
    for (void (^block)(void) in local) {
        try {
            block();
        } catch (...) {
            TVPAddLog(TJS_W("iosconfig: queued TJS call threw"));
        }
    }
}

void ShutdownQueue() {
    gQueue = nil;
}

// ============================================================
// 文字列
// ============================================================

NSString *ToNSString(const ttstr &s) {
    if (s.IsEmpty()) return @"";
    return [NSString stringWithCharacters:(const unichar *)s.c_str() length:s.length()];
}

ttstr ToTtstr(NSString *s) {
    if (s.length == 0) return ttstr();
    std::vector<unichar> buf(s.length);
    [s getCharacters:buf.data() range:NSMakeRange(0, s.length)];
    return ttstr((const tjs_char *)buf.data(), (int)buf.size());
}

// ============================================================
// TJS グローバル呼び出し
// ============================================================

static bool GetGlobalMember(iTJSDispatch2 *global, const tjs_char *name, tTJSVariant &out) {
    tjs_error e = global->PropGet(0, name, nullptr, &out, global);
    return TJS_SUCCEEDED(e) && out.Type() == tvtObject && out.AsObjectNoAddRef();
}

bool HasGlobal(const tjs_char *name) {
    iTJSDispatch2 *global = TVPGetScriptDispatch();
    if (!global) return false;
    bool ok = false;
    try {
        tTJSVariant v;
        ok = GetGlobalMember(global, name, v);
    } catch (...) {
        ok = false;
    }
    global->Release();
    return ok;
}

bool CallGlobal(const tjs_char *name, tjs_int numparams, tTJSVariant **params, tTJSVariant *result) {
    iTJSDispatch2 *global = TVPGetScriptDispatch();
    if (!global) return false;
    bool ok = false;
    try {
        tTJSVariant func;
        if (GetGlobalMember(global, name, func)) {
            tTJSVariantClosure clo = func.AsObjectClosureNoAddRef();
            ok = TJS_SUCCEEDED(clo.FuncCall(0, nullptr, nullptr, result, numparams, params, global));
        }
    } catch (...) {
        TVPAddLog(ttstr(TJS_W("iosconfig: TJS global threw: ")) + name);
        ok = false;
    }
    global->Release();
    return ok;
}

bool CallGlobalMethod(const tjs_char *objName, const tjs_char *method,
                      tjs_int numparams, tTJSVariant **params, tTJSVariant *result) {
    iTJSDispatch2 *global = TVPGetScriptDispatch();
    if (!global) return false;
    bool ok = false;
    try {
        tTJSVariant obj;
        if (GetGlobalMember(global, objName, obj)) {
            iTJSDispatch2 *o = obj.AsObjectNoAddRef();
            ok = TJS_SUCCEEDED(o->FuncCall(0, method, nullptr, result, numparams, params, o));
        }
    } catch (...) {
        TVPAddLog(ttstr(TJS_W("iosconfig: TJS method threw: ")) + objName + TJS_W(".") + method);
        ok = false;
    }
    global->Release();
    return ok;
}

// ============================================================
// 辞書 <-> NSDictionary
// ============================================================

static id VariantToObject(const tTJSVariant &v) {
    switch (v.Type()) {
    case tvtInteger: return @((long long)(tTVInteger)v);
    case tvtReal:    return @((double)(tTVReal)v);
    case tvtString:  return ToNSString(v.AsStringNoAddRef());
    default:         return nil;   // フラットな契約なので辞書 / 配列は来ない
    }
}

namespace {
class DictToNSCaller : public tTJSDispatch {
    NSMutableDictionary *mOut;
public:
    explicit DictToNSCaller(NSMutableDictionary *out) : mOut(out) {}
    tjs_error TJS_INTF_METHOD FuncCall(tjs_uint32, const tjs_char *, tjs_uint32 *,
                                       tTJSVariant *result, tjs_int numparams,
                                       tTJSVariant **param, iTJSDispatch2 *) override {
        // param[0]=name, param[1]=flags, param[2]=value
        if (numparams >= 3 && param[0] && param[2]) {
            tTVInteger flag = param[1] ? param[1]->AsInteger() : 0;
            if (!(flag & TJS_HIDDENMEMBER)) {
                id value = VariantToObject(*param[2]);
                if (value) mOut[ToNSString(ttstr(*param[0]))] = value;
            }
        }
        if (result) *result = true;
        return TJS_S_OK;
    }
};
} // namespace

static NSDictionary *DictToNS(iTJSDispatch2 *dict) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (!dict) return out;
    DictToNSCaller *caller = new DictToNSCaller(out);
    tTJSVariantClosure closure(caller);
    try {
        dict->EnumMembers(TJS_IGNOREPROP, &closure, dict);
    } catch (...) {
        TVPAddLog(TJS_W("iosconfig: EnumMembers threw"));
    }
    caller->Release();
    return out;
}

static tTJSVariant ObjectToVariant(id obj) {
    if ([obj isKindOfClass:[NSString class]]) return tTJSVariant(ToTtstr(obj));
    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *n = obj;
        const char *t = n.objCType;
        if (t[0] == 'f' || t[0] == 'd') return tTJSVariant((tTVReal)n.doubleValue);
        return tTJSVariant((tTVInteger)n.longLongValue);
    }
    return tTJSVariant();
}

static iTJSDispatch2 *NSToDict(NSDictionary *src) {
    iTJSDispatch2 *dsp = TJSCreateDictionaryObject();
    ncbPropAccessor acc(dsp);
    for (NSString *key in src) {
        tTJSVariant v = ObjectToVariant(src[key]);
        acc.SetValue(ToTtstr(key).c_str(), v);
    }
    return dsp;
}

// ============================================================
// ゲーム設定
// ============================================================

static NSArray<NSString *> *BaseVolumeKeys() {
    return @[ @"master", @"bgm", @"se", @"systemSe", @"voice", @"systemVoice" ];
}

static int GetVolume(NSString *key) {
    tTJSVariant keyv(ToTtstr(key));
    tTJSVariant *param[1] = { &keyv };
    tTJSVariant result;
    if (!CallGlobal(TJS_W("KrkrzAndroidGetVolume"), 1, param, &result)) return -1;
    if (result.Type() == tvtVoid) return -1;
    return (int)(tTVInteger)result;
}

void FetchConfig(void (^done)(NSDictionary<NSString *, id> *, NSDictionary<NSString *, NSNumber *> *)) {
    void (^cb)(NSDictionary *, NSDictionary *) = [done copy];
    Post(^{
        tTJSVariant cfg;
        if (!CallGlobal(TJS_W("KrkrzAndroidGetConfig"), 0, nullptr, &cfg) || cfg.Type() != tvtObject) {
            cb(nil, nil);
            return;
        }
        NSDictionary *config = DictToNS(cfg.AsObjectNoAddRef());
        NSMutableDictionary *volumes = [NSMutableDictionary dictionary];
        for (NSString *k in BaseVolumeKeys()) {
            int v = GetVolume(k);
            if (v >= 0) volumes[k] = @(v);
        }
        id names = config[@"charVoiceNames"];
        if ([names isKindOfClass:[NSString class]]) {
            for (NSString *raw in [names componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                NSString *name = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if (name.length == 0) continue;
                NSString *key = [@"charVoice:" stringByAppendingString:name];
                int v = GetVolume(key);
                if (v >= 0) volumes[key] = @(v);
            }
        }
        cb(config, volumes);
    });
}

void ApplyConfig(NSDictionary<NSString *, id> *edited) {
    NSDictionary *copy = [edited copy];
    Post(^{
        iTJSDispatch2 *dict = NSToDict(copy);
        tTJSVariant dv(dict, dict);
        dict->Release();
        tTJSVariant *param[1] = { &dv };
        tTJSVariant result;
        CallGlobal(TJS_W("KrkrzAndroidSetConfig"), 1, param, &result);
    });
}

void SetVolume(NSString *key, int value) {
    NSString *k = [key copy];
    Post(^{
        tTJSVariant keyv(ToTtstr(k));
        tTJSVariant valv((tjs_int)value);
        tTJSVariant *param[2] = { &keyv, &valv };
        tTJSVariant result;
        CallGlobal(TJS_W("KrkrzAndroidSetVolume"), 2, param, &result);
    });
}

// ============================================================
// 仮想パッド設定 (Android の VirtualPadPrefs 相当)
// ============================================================

static NSString *const kPadEnabledKey = @"virtualpad.enabled";
static NSString *const kPadOpacityKey = @"virtualpad.opacity_pct";

static int ClampOpacity(int pct) {
    return pct < kPadOpacityMin ? kPadOpacityMin : (pct > kPadOpacityMax ? kPadOpacityMax : pct);
}

bool PadAvailable() {
    return HasGlobal(TJS_W("VirtualPad"));
}

bool PadEnabled() {
    return [NSUserDefaults.standardUserDefaults boolForKey:kPadEnabledKey];   // 既定 OFF
}

int PadOpacityPercent() {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d objectForKey:kPadOpacityKey]) return kPadOpacityDefault;
    return ClampOpacity((int)[d integerForKey:kPadOpacityKey]);
}

static void SendPadEnabled(bool enabled) {
    Post(^{
        tTJSVariant v((tjs_int)(enabled ? 1 : 0));
        tTJSVariant *param[1] = { &v };
        CallGlobalMethod(TJS_W("VirtualPad"), TJS_W("setEnabled"), 1, param, nullptr);
    });
}

static void SendPadOpacity(int pct) {
    Post(^{
        tTJSVariant v((tTVReal)(pct / 100.0));
        tTJSVariant *param[1] = { &v };
        CallGlobalMethod(TJS_W("VirtualPad"), TJS_W("setOpacity"), 1, param, nullptr);
    });
}

void SetPadEnabled(bool enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kPadEnabledKey];
    SendPadEnabled(enabled);
}

void SetPadOpacityPercent(int pct) {
    pct = ClampOpacity(pct);
    [NSUserDefaults.standardUserDefaults setInteger:pct forKey:kPadOpacityKey];
    SendPadOpacity(pct);
}

void ApplyPadPrefs() {
    SendPadEnabled(PadEnabled());
    SendPadOpacity(PadOpacityPercent());
}

} // namespace iosconfig
