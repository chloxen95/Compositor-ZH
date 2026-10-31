#!/usr/bin/env python3
"""翻译记忆库 → String Catalog（`Compositor/Localizable.xcstrings`）。

为什么要生成而不是手写
----------------------
String Catalog 是 JSON，但它是「产品数据」而不是「源码」：一条译文要落在
`strings[key].localizations["zh-Hans"].stringUnit.value`。手写 600 多条意味着
600 次 JSON 语法风险，而且上游改一句英文就得手工改 key——那就违反了「随时并入上游」。

所以分工是：
    L10n/translations.csv   人只改这里（两列，可 diff、可评审、可模糊匹配）
    L10n/source-keys.json   Xcode 说有哪些 key（权威，别手改）
    Localizable.xcstrings   本脚本生成，提交进仓库（Xcode 需要它才能变中文）

没有译文的 key 不写进 catalog：运行时自然回落到英文 key，不会出现空白界面。
`status=verbatim` 的 key 写成 `shouldTranslate: false`——这是 Xcode 表达
「这是专名，别翻」的标准方式，比写一条和原文一样的译文更准确。

用法：
    python3 scripts/l10n/make_catalog.py            # 生成
    python3 scripts/l10n/make_catalog.py --check    # 只校验 catalog 是否与 CSV 同步
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TM = REPO / "l10n" / "translations.csv"
KEYS = REPO / "l10n" / "source-keys.json"
CATALOG = REPO / "Compositor" / "Localizable.xcstrings"
INFO_CATALOG = REPO / "Compositor" / "InfoPlist.xcstrings"


def load_tm() -> dict[str, dict[str, str]]:
    with TM.open(encoding="utf-8", newline="") as handle:
        return {row["key"]: row for row in csv.DictReader(handle)}


def build(strings: dict[str, dict], language: str = "zh-Hans") -> dict:
    catalog: dict[str, dict] = {}
    for key in sorted(strings):
        row = strings[key]
        status = row.get("status", "new")
        value = (row.get(language) or "").strip()
        if status == "verbatim":
            # 专名：显式声明「不翻」，Xcode 与译者在界面上都会看到这个标记。
            catalog[key] = {"shouldTranslate": False}
            continue
        if status == "new" or not value:
            continue
        unit: dict[str, str] = {"state": "translated" if status == "translated" else status, "value": value}
        catalog[key] = {"localizations": {language: {"stringUnit": unit}}}
    return {
        "sourceLanguage": "en",
        "strings": catalog,
        "version": "1.0",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="由 CSV 生成 String Catalog")
    ap.add_argument("--language", default="zh-Hans")
    ap.add_argument("--check", action="store_true", help="只检查，不写盘")
    args = ap.parse_args()

    if not KEYS.exists() or not TM.exists():
        print("缺少 l10n/source-keys.json 或 l10n/translations.csv", file=sys.stderr)
        return 2

    keys_data = json.loads(KEYS.read_text(encoding="utf-8"))
    tm = load_tm()
    source_keys = [entry["key"] for entry in keys_data["keys"]]
    plist_keys = keys_data.get("infoPlistKeys", [])

    main_catalog = build({k: tm.get(k, {"status": "new"}) for k in source_keys}, args.language)
    info_catalog = build({k: tm.get(k, {"status": "new"}) for k in plist_keys}, args.language)

    rendered = json.dumps(main_catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    info_rendered = json.dumps(info_catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    translated = len(main_catalog["strings"])
    verbatim = sum(1 for v in main_catalog["strings"].values() if v.get("shouldTranslate") is False)
    missing = len(source_keys) - translated
    print(f"键 {len(source_keys)}｜写入 catalog {translated}（其中不译 {verbatim}）｜仍缺 {missing}")

    if args.check:
        stale = []
        for path, text in ((CATALOG, rendered), (INFO_CATALOG, info_rendered)):
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(path.relative_to(REPO))
        if stale:
            print("❌ catalog 与 CSV 不同步：" + "、".join(str(p) for p in stale))
            print("   跑 python3 scripts/l10n/make_catalog.py")
            return 1
        print("✅ catalog 与 CSV 一致")
        return 0

    CATALOG.write_text(rendered, encoding="utf-8")
    INFO_CATALOG.write_text(info_rendered, encoding="utf-8")
    print(f"✅ 已写入 {CATALOG.relative_to(REPO)}、{INFO_CATALOG.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
