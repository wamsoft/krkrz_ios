#!/usr/bin/env python3
"""xcodebuild -exportArchive 用の ExportOptions.plist を作る。

usage: export-options.py <method> <teamID> <out.plist>
  method: development | release-testing (Ad Hoc) | app-store-connect | enterprise
"""
import plistlib
import sys

METHODS = ("development", "release-testing", "app-store-connect", "enterprise", "debugging")

method, team, out = sys.argv[1], sys.argv[2], sys.argv[3]
if method not in METHODS:
    raise SystemExit(f"EXPORT_METHOD must be one of {METHODS}: {method}")
opts = {
    "method": method,
    "teamID": team,
    "signingStyle": "automatic",
    "compileBitcode": False,
    "stripSwiftSymbols": True,
}
if method == "app-store-connect":
    # アップロードは別手順 (Transporter / altool / Xcode Organizer)。ここでは ipa を作るだけ
    opts["destination"] = "export"
    opts["uploadSymbols"] = True
with open(out, "wb") as f:
    plistlib.dump(opts, f)
print(f"[export-options] {out}: method={method} team={team}")
