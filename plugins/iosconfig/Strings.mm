// iosconfig - 文言。Android 版と同じキー・同じ訳 (Strings.inc は gen-strings.py で生成)。
// 端末の優先言語から ja / zh-Hans / zh-Hant / en を選ぶ (それ以外は en)。

#import "IosConfig.h"

#include "Strings.inc"

namespace iosconfig {

static NSDictionary<NSString *, NSString *> *CurrentTable() {
    static NSDictionary<NSString *, NSString *> *table;
    if (table) return table;
    NSDictionary *all = IosConfigStringTable();
    NSString *lang = @"en";
    NSString *pref = NSLocale.preferredLanguages.firstObject ?: @"en";
    if ([pref hasPrefix:@"ja"]) {
        lang = @"ja";
    } else if ([pref hasPrefix:@"zh"]) {
        // zh-Hant / zh-TW / zh-HK / zh-MO は繁体字、それ以外の zh は簡体字
        BOOL hant = [pref hasPrefix:@"zh-Hant"] || [pref hasPrefix:@"zh-TW"] ||
                    [pref hasPrefix:@"zh-HK"] || [pref hasPrefix:@"zh-MO"];
        lang = hant ? @"zh-Hant" : @"zh-Hans";
    }
    table = all[lang];
    return table;
}

NSString *L(NSString *key) {
    NSString *s = CurrentTable()[key];
    if (!s) s = IosConfigStringTable()[@"en"][key];
    return s ?: key;
}

} // namespace iosconfig
