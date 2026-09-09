#!/usr/bin/env python3
"""Derives Tappy/Info-Debug.plist from the generated Tappy/Info.plist.

The only difference is NSAllowsArbitraryLoads, which lets a debug build reach the hub by raw
IP over plain HTTP. Keeping it in a separate, Debug-only plist means a Release build cannot
carry it no matter what anyone forgets.

Run after `xcodegen generate` if Info.plist changed.
"""
import plistlib
import pathlib

here = pathlib.Path(__file__).resolve().parent.parent
release = plistlib.loads((here / "Tappy/Info.plist").read_bytes())
release.setdefault("NSAppTransportSecurity", {})["NSAllowsArbitraryLoads"] = True
(here / "Tappy/Info-Debug.plist").write_bytes(plistlib.dumps(release))
print("wrote Tappy/Info-Debug.plist (Debug only)")
