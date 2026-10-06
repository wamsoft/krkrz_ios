#!/usr/bin/env python3
"""書き出された ipa を <baseName>-<version>-<build>[-<method>].ipa にリネームする。

usage: rename-ipa.py <ipa_dir> <app.cmake> <method>
baseName は ios-config.json の ipa.baseName (未指定ならリネームしない)。
"""
import glob
import os
import re
import sys

ipa_dir, app_cmake, method = sys.argv[1], sys.argv[2], sys.argv[3]
vars_ = dict(re.findall(r'set\((\w+) "([^"]*)"\)', open(app_cmake, encoding="utf-8").read()))
base = vars_.get("APP_IPA_BASENAME", "")
ipas = glob.glob(os.path.join(ipa_dir, "*.ipa"))
if not ipas:
    raise SystemExit(f"[rename-ipa] no ipa in {ipa_dir}")
src = ipas[0]
if base:
    suffix = "" if method == "app-store-connect" else f"-{method}"
    dst = os.path.join(ipa_dir, f"{base}-{vars_.get('APP_VERSION', '')}-{vars_.get('APP_BUILD', '')}{suffix}.ipa")
    os.replace(src, dst)
    src = dst
print(f"[rename-ipa] {src}")
