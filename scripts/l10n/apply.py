#!/usr/bin/env python3
"""把译文写进翻译记忆库（`l10n/translations.csv`）——唯一的译文存放处。

为什么要一个专门的写入工具，而不是手改 CSV：
  · CSV 里会有引号、逗号、全角标点，手改十次错三次；
  · 批量翻译时必须能一次落 100 条并立刻看到「哪条键不存在」（拼错 key 是最常见的浪费）；
  · `--init` 让 CSV 的键列始终与 `source-keys.json`（Xcode 权威抽取）对齐，
    上游改一句英文就自动多出一行 `new`，不需要人去数。

输入格式（JSON，UTF-8）：
    { "Cancel": "取消", "OK": "确定" }

用法：
    python3 scripts/l10n/apply.py --init                 # 对齐键列，保留已有译文
    python3 scripts/l10n/apply.py batch.json             # 写入/覆盖译文
    python3 scripts/l10n/apply.py batch.json --status verbatim   # 标记「保持原文」
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
FIELDS = ["key", "zh-Hans", "status", "note"]


def load_tm() -> dict[str, dict[str, str]]:
    if not TM.exists():
        return {}
    with TM.open(encoding="utf-8", newline="") as handle:
        return {row["key"]: row for row in csv.DictReader(handle)}


def save_tm(rows: dict[str, dict[str, str]]) -> None:
    with TM.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        for key in sorted(rows):
            writer.writerow({field: rows[key].get(field, "") for field in FIELDS})


def ordered_keys() -> list[str]:
    """Localizable 与 InfoPlist 两类键一起进 TM：Info.plist 里也有会显示给用户的字符串
    （Finder 的「种类」列：Compositor 项目 / Adobe Photoshop 文档），漏掉就永远是英文。"""
    data = json.loads(KEYS.read_text(encoding="utf-8"))
    keys = {entry["key"] for entry in data["keys"]}
    keys.update(data.get("infoPlistKeys", []))
    return sorted(keys)


def main() -> int:
    ap = argparse.ArgumentParser(description="把译文写入翻译记忆库")
    ap.add_argument("batch", nargs="?", help="JSON 文件：{英文: 中文}")
    ap.add_argument("--init", action="store_true", help="按 source-keys.json 对齐键列")
    ap.add_argument("--status", default="translated", choices=["translated", "verbatim", "review"])
    ap.add_argument("--note", default="")
    args = ap.parse_args()

    if not KEYS.exists():
        print(f"缺少 {KEYS}，先跑 scripts/l10n/harvest.py", file=sys.stderr)
        return 2

    rows = load_tm()
    known = set(ordered_keys())

    if args.init or not args.batch:
        for key in known:
            rows.setdefault(key, {"key": key, "zh-Hans": "", "status": "new", "note": ""})
        # 上游把英文句子改了之后，旧 key 就成了孤儿。有译文的留着（下次做模糊匹配比重新翻便宜），
        # 空行直接丢掉——空行不是资产，只是噪音。
        orphans = [k for k in rows if k not in known]
        kept = 0
        for key in orphans:
            if (rows[key].get("zh-Hans") or "").strip():
                rows[key]["status"] = "orphan"
                kept += 1
            else:
                del rows[key]
        save_tm(rows)
        print(f"✅ 键列已对齐：{len(known)} 条（保留已有译文 {sum(1 for r in rows.values() if r['status'] != 'new')} 条）")
        if orphans:
            print(f"   孤儿 {len(orphans)} 条：保留有译文的 {kept} 条，丢弃空行 {len(orphans) - kept} 条")

    if args.batch:
        batch = json.loads(Path(args.batch).read_text(encoding="utf-8"))
        unknown = [k for k in batch if k not in known]
        applied = 0
        for key, value in batch.items():
            if key not in known:
                continue
            row = rows.setdefault(key, {"key": key, "zh-Hans": "", "status": "new", "note": ""})
            row["zh-Hans"] = value
            row["status"] = args.status
            if args.note:
                row["note"] = args.note
            applied += 1
        save_tm(rows)
        print(f"✅ 写入 {applied} 条（status={args.status}）")
        if unknown:
            print(f"⚠️ 有 {len(unknown)} 条 key 不在权威键表里，已忽略（多半是英文句子已被上游改动）：")
            for key in unknown[:10]:
                print(f"   {key[:96]!r}")
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
