#!/usr/bin/env python3
"""采集「权威键源」：Xcode 编译器实际抽取到的可本地化字符串。

为什么不用自己写的扫描器作准绳
------------------------------
`extract.py` 是手写的 Swift 词法扫描，够用来估算规模、找盲区，但它不是编译器：
带嵌套字符串字面量的插值（`\\(cond ? "a" : "b")`）会被提前截断，AppKit 调用点
也会被算成「已抽取」。真正的 key 集合只有一个权威来源——编译器吐出的 `.stringsdata`，
以及 Xcode 用它合成的那份 xcloc。

本脚本做三件事：
  1. 调 `xcodebuild -exportLocalizations` 拿 xcloc（可跳过，复用已有目录）；
  2. 从 xliff 读出权威 key（此时插值已规范化成 `%lld` / `%@` / `%1$lld`）；
  3. 从 DerivedData 的 `.stringsdata` 补出每个 key 的源码位置，供分组翻译用。

产出 `l10n/source-keys.json`，是 `make_catalog.py` 的唯一输入。

用法：
    python3 scripts/l10n/harvest.py                 # 重新导出并采集
    python3 scripts/l10n/harvest.py --xcloc /path/en.xcloc   # 跳过构建，复用已有 xcloc
"""

from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "l10n" / "source-keys.json"
XLIFF_NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}

# 导出时用的构建参数，与 build-zh.sh 保持一致：原因见 l10n/RELEASE.md §六。
BUILD_ARGS = [
    "CODE_SIGN_IDENTITY=-",
    "CODE_SIGN_STYLE=Manual",
    "ENABLE_HARDENED_RUNTIME=NO",
    "OTHER_SWIFT_FLAGS=-disable-sandbox",
]


def run_export(derived_data: Path, out_dir: Path) -> Path:
    cmd = [
        "xcodebuild", "-exportLocalizations",
        "-project", str(REPO / "Compositor.xcodeproj"),
        "-scheme", "Compositor",
        "-localizationPath", str(out_dir),
        "-derivedDataPath", str(derived_data),
        *BUILD_ARGS,
    ]
    print("▸ 导出可本地化字符串（会走一次构建，约 1 分钟）")
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout[-4000:] + proc.stderr[-4000:])
        raise SystemExit(f"❌ xcodebuild -exportLocalizations 失败（{proc.returncode}）")
    found = sorted(out_dir.glob("*.xcloc"))
    if not found:
        raise SystemExit("❌ 导出成功但没有产出 .xcloc")
    return found[0] / "Localized Contents" / f"{found[0].stem}.xliff"


def parse_xliff(path: Path) -> tuple[list[str], list[str]]:
    root = ET.parse(path).getroot()
    localizable: list[str] = []
    infoplist: list[str] = []
    for file_node in root.findall(".//x:file", XLIFF_NS):
        origin = file_node.get("original", "")
        bucket = infoplist if "InfoPlist" in origin else localizable
        for unit in file_node.findall("x:body/x:trans-unit", XLIFF_NS):
            src = unit.find("x:source", XLIFF_NS)
            text = (src.text or "") if src is not None else ""
            if text.strip():
                bucket.append(text)
    return sorted(set(localizable)), sorted(set(infoplist))


def parse_stringsdata(derived_data: Path) -> dict[str, list[dict]]:
    """key -> [{file, line}]。位置只用于分组与人读，缺了不影响构建。"""
    pattern = str(derived_data / "Build/Intermediates.noindex/Compositor.build/*/*.build/Objects-normal/*/*.stringsdata")
    sites: dict[str, list[dict]] = {}
    for path in sorted(glob.glob(pattern)):
        try:
            data = json.loads(Path(path).read_text())
        except (ValueError, OSError):
            continue
        source = data.get("source", "")
        rel = source.split("/Compositor/Compositor/", 1)[-1] if source else os.path.basename(path)
        for entries in (data.get("tables") or {}).values():
            for entry in entries:
                key = entry.get("key")
                if not key:
                    continue
                line = (entry.get("location") or {}).get("startingLine")
                sites.setdefault(key, []).append({"file": f"Compositor/{rel}", "line": line})
    for value in sites.values():
        value.sort(key=lambda s: (s["file"], s["line"] or 0))
    return sites


def main() -> int:
    ap = argparse.ArgumentParser(description="采集 Xcode 抽取到的权威本地化键")
    ap.add_argument("--xcloc", help="复用一个已导出的 .xcloc 目录，跳过构建")
    ap.add_argument("--derived-data", default=os.path.expanduser("~/Library/Caches/CompositorZH"))
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    derived_data = Path(args.derived_data)
    if args.xcloc:
        xcloc = Path(args.xcloc)
        xliff = xcloc / "Localized Contents" / f"{xcloc.stem}.xliff"
        if not xliff.exists():
            raise SystemExit(f"❌ {xcloc} 里找不到 Localized Contents/{xcloc.stem}.xliff")
    else:
        tmp = Path(tempfile.mkdtemp(prefix="zh-harvest-"))
        xliff = run_export(derived_data, tmp)

    keys, plist_keys = parse_xliff(xliff)
    sites = parse_stringsdata(derived_data)

    entries = [
        {"key": k, "sites": sites.get(k, [])}
        for k in keys
    ]
    payload = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "tool": "scripts/l10n/harvest.py",
        "note": "key 来自 Xcode 编译期抽取（xcloc），不是手写扫描器；插值已规范化为 printf 形式",
        "xliff": str(xliff),
        "infoPlistKeys": plist_keys,
        "keys": entries,
    }
    Path(args.out).write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n")

    with_sites = sum(1 for e in entries if e["sites"])
    absent = sorted({s["file"] for v in sites.values() for s in v} - {s["file"] for e in entries for s in e["sites"]})
    print(f"✅ 权威 key：{len(entries)} 条（其中 {with_sites} 条拿到了源码位置）")
    print(f"   InfoPlist：{len(plist_keys)} 条 —— {', '.join(plist_keys) if plist_keys else '(无)'}")
    print(f"   产出：{args.out}")
    if absent:
        print(f"   ⚠️ 有 {len(absent)} 个文件抽到过字符串却不在 xliff 里：{absent[:3]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
