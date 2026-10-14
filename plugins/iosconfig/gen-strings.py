#!/usr/bin/env python3
"""krkrz_android の strings.xml からシステムメニュー / 設定画面の文言表 (Strings.inc) を作る。

使い方: python3 gen-strings.py [krkrz_android の res フォルダ]
既定は ../../../krkrz_android/app/src/main/res (krkrz_ios と同じ階層の krkrz_android)。
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
RES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, "..", "..", "..", "krkrz_android", "app", "src", "main", "res")

LANGS = [("en", "values"), ("ja", "values-ja"),
         ("zh-Hans", "values-zh-rCN"), ("zh-Hant", "values-zh-rTW")]
KEY_RE = re.compile(r"(drawer_header_subtitle|menu_settings|menu_license|settings_|license_placeholder)")

# Android に無い iOS 専用の文言
EXTRA = {
    "close": {"en": "Close", "ja": "閉じる", "zh-Hans": "关闭", "zh-Hant": "關閉"},
}


def unescape(s):
    return s.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n")


def objc(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return '@"' + s + '"'


def main():
    tables = {}
    for code, folder in LANGS:
        t = {}
        for e in ET.parse(os.path.join(RES, folder, "strings.xml")).getroot().iter("string"):
            name = e.get("name")
            if KEY_RE.match(name):
                t[name] = unescape("".join(e.itertext()))
        for key, m in EXTRA.items():
            t[key] = m[code]
        tables[code] = t

    out = [
        "// Android 版 (krkrz_android app/src/main/res/values*/strings.xml) から生成した文言表。",
        "// Android 側の文言を直したら gen-strings.py で作り直すこと。",
        "",
        "static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *IosConfigStringTable() {",
        "    return @{",
    ]
    for code, _ in LANGS:
        out.append(f'        @"{code}": @{{')
        for k in sorted(tables[code]):
            out.append(f"            {objc(k)}: {objc(tables[code][k])},")
        out.append("        },")
    out += ["    };", "}", ""]
    with open(os.path.join(HERE, "Strings.inc"), "w", encoding="utf-8") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
