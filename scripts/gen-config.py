#!/usr/bin/env python3
"""ios-config.json から CMake 用の生成物を作る。

出力先 (OUT_DIR, 既定 ${PROJECT_DIR}/build/ios/generated):
  app.cmake        APP_* 変数 (バンドル ID / バージョン / 向き / graphics ...)
  myapp.cmake      TVP_PLUGIN_FOLDERS / TVP_PLUGINS / TVP_PLUGINS_STATIC
  assets/          assetPack.sources をマージした資材 (バンドル直下にコピーされる)
  Assets.xcassets  icon 指定時のみ (AppIcon)
  app.entitlements entitlements 指定時のみ

${VAR} 展開・相対パス解決・assetPack のセマンティクスは krkrz_android の
app/build.gradle と同一:
  - ${BUILD_SYSTEM_DIR} = このリポジトリ, ${PROJECT_DIR} = 案件フォルダ,
    それ以外は環境変数 (未定義は空文字)
  - 相対パスは PROJECT_DIR 基準 (assetPack.sources[].from は baseFolder 基準)
  - mirror / flatten, include / exclude (Ant 形式), 先勝ち, 差分コピー + 残骸削除
"""

import json
import os
import plistlib
import re
import shutil
import sys

BUILD_SYSTEM_DIR = os.path.realpath(os.path.join(os.path.dirname(__file__), ".."))
PROJECT_DIR = os.path.realpath(os.environ.get("PROJECT_DIR") or BUILD_SYSTEM_DIR)
# ${KRKRZ_BASE} の既定 = このリポジトリと同じ階層 (Makefile / CMakeLists.txt と同じ規則)
if not os.environ.get("KRKRZ_BASE"):
    os.environ["KRKRZ_BASE"] = os.path.dirname(BUILD_SYSTEM_DIR)


def log(msg):
    print(f"[gen-config] {msg}")


def warn(msg):
    print(f"[gen-config] WARNING: {msg}", file=sys.stderr)


def expand_env(s):
    if s is None:
        return None

    def repl(m):
        var = m.group(1)
        if var == "BUILD_SYSTEM_DIR":
            return BUILD_SYSTEM_DIR
        if var == "PROJECT_DIR":
            return PROJECT_DIR
        return os.environ.get(var, "")

    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", repl, s)


def resolve_path(s, base=PROJECT_DIR):
    e = expand_env(s)
    if not e:
        return None
    return os.path.normpath(e if os.path.isabs(e) else os.path.join(base, e))


def cmake_str(s):
    return '"' + str(s).replace("\\", "/").replace('"', '\\"') + '"'


# ----------------------------------------------------------------------
# Ant 形式パターン (gradle fileTree 互換)
# ----------------------------------------------------------------------

# gradle (Ant) のデフォルト除外
DEFAULT_EXCLUDES = [
    "**/.DS_Store", "**/._*", "**/.git", "**/.git/**", "**/.gitignore", "**/.gitattributes",
    "**/.gitmodules", "**/.svn", "**/.svn/**", "**/.hg", "**/.hg/**", "**/CVS", "**/CVS/**",
    "**/*~", "**/#*#", "**/.#*", "**/%*%",
]


def ant_to_regex(pat):
    pat = pat.replace("\\", "/")
    if pat.endswith("/"):
        pat += "**"
    out = ""
    i = 0
    while i < len(pat):
        if pat.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pat.startswith("**", i):
            out += ".*"
            i += 2
        elif pat[i] == "*":
            out += "[^/]*"
            i += 1
        elif pat[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pat[i])
            i += 1
    return re.compile("^" + out + "$")


def file_tree(root, includes, excludes):
    inc = [ant_to_regex(p) for p in includes]
    exc = [ant_to_regex(p) for p in excludes + DEFAULT_EXCLUDES]
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if any(r.match(rel) for r in inc) and not any(r.match(rel) for r in exc):
                yield full, rel


def run_copy_rules(sources, out_dir, base_folder, label):
    os.makedirs(out_dir, exist_ok=True)
    expected = {}
    for src in sources:
        typ = src.get("type")
        if typ not in ("mirror", "flatten"):
            raise SystemExit(f"[{label}] unknown type '{typ}' (must be 'mirror' or 'flatten')")
        raw_from = src.get("from")
        if not raw_from:
            raise SystemExit(f"[{label}] 'from' is required")
        expanded = expand_env(raw_from)
        from_is_abs = os.path.isabs(expanded)
        if not from_is_abs and base_folder is None:
            raise SystemExit(f"[{label}] 'from' is relative ('{raw_from}') but 'baseFolder' is not set")
        from_dir = os.path.normpath(expanded if from_is_abs else os.path.join(base_folder, expanded))

        if "to" in src:
            to_path = src.get("to") or ""
        elif typ == "mirror":
            to_path = os.path.basename(from_dir) if from_is_abs else raw_from
        else:
            to_path = ""

        if not os.path.isdir(from_dir):
            warn(f"[{label}] source folder not found, skipped: {from_dir}")
            continue

        for full, rel in file_tree(from_dir, src.get("include") or ["**/*"], src.get("exclude") or []):
            name = rel if typ == "mirror" else os.path.basename(rel)
            dest = f"{to_path}/{name}" if to_path else name
            dest = dest.lstrip("/")
            if dest in expected:
                warn(f"[{label}] duplicate skipped (first wins): {dest}\n    kept   : {expected[dest]}\n    skipped: {full}")
                continue
            expected[dest] = full

    removed = 0
    for dirpath, _, filenames in os.walk(out_dir):
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, out_dir).replace(os.sep, "/")
            if rel not in expected:
                os.remove(full)
                removed += 1
    for dirpath, _, _ in sorted(os.walk(out_dir), key=lambda t: -len(t[0])):
        if dirpath != out_dir and not os.listdir(dirpath):
            os.rmdir(dirpath)

    copied = unchanged = 0
    for dest, srcf in expected.items():
        destf = os.path.join(out_dir, dest)
        st = os.stat(srcf)
        if os.path.exists(destf):
            dt = os.stat(destf)
            if dt.st_size == st.st_size and int(dt.st_mtime) == int(st.st_mtime):
                unchanged += 1
                continue
            os.remove(destf)
        os.makedirs(os.path.dirname(destf), exist_ok=True)
        shutil.copy2(srcf, destf)
        copied += 1
    log(f"[{label}] {len(expected)} file(s) total: {copied} copied, {unchanged} unchanged, {removed} removed")


# ----------------------------------------------------------------------

ORIENTATIONS = {
    "portrait": "UIInterfaceOrientationPortrait",
    "portraitUpsideDown": "UIInterfaceOrientationPortraitUpsideDown",
    "landscapeLeft": "UIInterfaceOrientationLandscapeLeft",
    "landscapeRight": "UIInterfaceOrientationLandscapeRight",
}
DEVICES = {"iphone": "1", "ipad": "2"}


def plist_inner(d):
    """dict を Info.plist の <dict> 内に差し込める XML 断片にする"""
    if not d:
        return ""
    xml = plistlib.dumps(d, sort_keys=False).decode()
    body = xml.split("<dict>", 1)[1].rsplit("</dict>", 1)[0]
    return body.strip("\n") + "\n"


def write_if_changed(path, text):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    log(f"wrote {path}")


def gen_icon(icon_path, out_dir):
    xc = os.path.join(out_dir, "Assets.xcassets")
    if not icon_path:
        if os.path.isdir(xc):
            shutil.rmtree(xc)
        return
    if not os.path.isfile(icon_path):
        raise SystemExit(f"icon not found: {icon_path}")
    iconset = os.path.join(xc, "AppIcon.appiconset")
    os.makedirs(iconset, exist_ok=True)
    write_if_changed(os.path.join(xc, "Contents.json"),
                     json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    dst = os.path.join(iconset, "AppIcon-1024.png")
    if not os.path.exists(dst) or os.path.getmtime(dst) != os.path.getmtime(icon_path):
        shutil.copy2(icon_path, dst)
    # Xcode 14+ の単一サイズ (1024px) アイコン
    contents = {
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    write_if_changed(os.path.join(iconset, "Contents.json"), json.dumps(contents, indent=2) + "\n")


def main():
    config_file = os.environ.get("APP_CONFIG_FILE") or os.path.join(PROJECT_DIR, "ios-config.json")
    config_file = resolve_path(config_file)
    out_dir = os.environ.get("OUT_DIR") or os.path.join(PROJECT_DIR, "build", "ios", "generated")
    os.makedirs(out_dir, exist_ok=True)
    log(f"BUILD_SYSTEM_DIR={BUILD_SYSTEM_DIR}")
    log(f"PROJECT_DIR={PROJECT_DIR}")
    log(f"config={config_file}")

    with open(config_file, encoding="utf-8") as f:
        cfg = json.load(f)

    # --- app.cmake
    orient = cfg.get("orientations") or ["landscapeLeft", "landscapeRight"]
    for o in orient:
        if o not in ORIENTATIONS:
            raise SystemExit(f"unknown orientation '{o}' (must be one of {list(ORIENTATIONS)})")
    orient_plist = "".join(f"\t\t<string>{ORIENTATIONS[o]}</string>\n" for o in orient)
    devices = cfg.get("devices") or ["iphone", "ipad"]
    graphics = cfg.get("graphics", "metal")
    if graphics not in ("metal", "gles"):
        raise SystemExit(f"unknown graphics '{graphics}' (must be 'metal' or 'gles')")

    entitlements = ""
    if cfg.get("entitlements"):
        entitlements = os.path.join(out_dir, "app.entitlements")
        write_if_changed(entitlements, plistlib.dumps(cfg["entitlements"]).decode())

    team = os.environ.get("DEVELOPMENT_TEAM") or cfg.get("developmentTeam", "")

    info_plist = dict(cfg.get("infoPlist") or {})
    if cfg.get("repl", True):
        # REPL (-replweb) の待受は iOS のローカルネットワーク権限の対象
        info_plist.setdefault("NSLocalNetworkUsageDescription",
                              "開発用 REPL (デバッグ接続) に使用します。")

    app_vars = {
        "APP_BUNDLE_ID": cfg["bundleId"],
        "APP_DISPLAY_NAME": cfg.get("displayName", "krkrz"),
        "APP_VERSION": cfg.get("version", "1.0"),
        "APP_BUILD": str(cfg.get("build", 1)),
        "APP_DEPLOYMENT_TARGET": cfg.get("deploymentTarget", "16.0"),
        "APP_DEVICE_FAMILY": ",".join(DEVICES[d] for d in devices),
        "APP_GRAPHICS": graphics,
        "APP_REPL": "ON" if cfg.get("repl", True) else "OFF",
        "APP_DEVELOPMENT_TEAM": team,
        "APP_ENTITLEMENTS": entitlements,
        "APP_ORIENTATIONS_PLIST": orient_plist,
        "APP_INFOPLIST_EXTRA": plist_inner(info_plist),
    }
    text = "# generated by scripts/gen-config.py - DO NOT EDIT\n"
    text += "".join(f"set({k} {cmake_str(v)})\n" for k, v in app_vars.items())
    write_if_changed(os.path.join(out_dir, "app.cmake"), text)

    # --- myapp.cmake (krkrz_android の generateMyappCmake と同じ出力)
    cm = cfg.get("cmake") or {}
    folders = [resolve_path(p) for p in cm.get("pluginFolders", [])]
    plugins = cm.get("plugins", [])
    statics = cm.get("staticPlugins", plugins)
    text = "# generated by scripts/gen-config.py - DO NOT EDIT\n"
    if folders:
        text += "LIST(APPEND TVP_PLUGIN_FOLDERS\n" + "".join(f"    {cmake_str(p)}\n" for p in folders if p) + ")\n"
    if plugins:
        text += "LIST(APPEND TVP_PLUGINS\n" + "".join(f"    {p}\n" for p in plugins) + ")\n"
    if statics:
        text += "LIST(APPEND TVP_PLUGINS_STATIC\n" + "".join(f"    {p}\n" for p in statics) + ")\n"
    write_if_changed(os.path.join(out_dir, "myapp.cmake"), text)

    # --- icon
    gen_icon(resolve_path(cfg["icon"]) if cfg.get("icon") else None, out_dir)

    # --- assets
    ap = cfg.get("assetPack") or {}
    base = resolve_path(ap["baseFolder"]) if ap.get("baseFolder") else None
    run_copy_rules(ap.get("sources", []), os.path.join(out_dir, "assets"), base, "assetPack")


if __name__ == "__main__":
    main()
