#!/usr/bin/env python3
"""汉化质量闸门：把「翻译对不对」变成可执行的检查。

设计立场：翻译错误和代码错误一样，应该被 CI 拦住，而不是靠人眼在 760 条里找。
因此本脚本可被 XCTest 调用，也可独立跑在 CI 上。

检查项（ERROR 会阻断，WARN 只提示）：
    E1 覆盖率      source-keys.json 里的每个 key 都必须在 TM 中有非空译文
    E2 占位符      译文与原文的占位符数量一致；原文含 \\( 插值时按插值个数核对
    E3 术语        与 glossary.json 完全匹配的 key，译文必须等于术语表取值
                   （glossary.termOverrides 可登记一词多义，如 Type＝文字/类型）
    E4 禁用译法    hard 表命中即 ERROR，soft 表命中记 WARN
    E5 省略号      原文以 … 结尾的，译文也须以 … 结尾
    E6 不译名      原文出现的 PNG/JPEG/Camera Raw 等在译文中必须保留
    E7 状态         status=translated 但译文为空，或译文等于英文原文（未译却标已译）
    W1 空白        首尾空白与原文不一致（仅提示，常见于刻意的排版）
    W2 长度        超过 glossary.rules.menuLength 的菜单项（仅提示）

关于 E4 为什么分两档：早期的单表把「透明度」也算错，于是 Preserve Transparency
（导出选项，PS 简中版正是「保留透明度」）被误判；把灰度规则硬套到所有语境，
闸门就会天天喊狼来了，最后没人看。现在分 hard（蒙板、撤销操作这类任何语境都错）
与 soft（透明度、设置这类看语境），soft 只提示，人裁定后写进 glossary.reviewed。

关于占位符正则为什么不允许 `%` 与空格：`(300% and above)` 里的 `% a` 会被
`%[-+ 0#]*…a` 匹成「带空格标志的 %a」，把普通百分号当成格式符——这条曾让四条
正常译文被判 E2。

用法：
    scripts/l10n/lint.py                      # 全量检查
    scripts/l10n/lint.py --only coverage      # 只查某一项
    scripts/l10n/lint.py --report l10n/report.md

退出码：0 全部通过；1 有 ERROR；2 输入缺失。
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from collections import Counter, defaultdict

PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+0#]*[\d.]*(?:hh|h|ll|l|L|z|j|t)?[@dDfFuUxXoOsScCpaAeEgG%]")
SWIFT_INTERPOLATION = re.compile(r"\\\(")


def load_json(path: str):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_tm(path: str) -> dict[str, dict[str, str]]:
    with open(path, encoding="utf-8", newline="") as handle:
        return {row["key"]: row for row in csv.DictReader(handle)}


class Findings:
    def __init__(self) -> None:
        self.items: list[tuple[str, str, str, str]] = []  # (level, code, key, message)

    def error(self, code: str, key: str, message: str) -> None:
        self.items.append(("ERROR", code, key, message))

    def warn(self, code: str, key: str, message: str) -> None:
        self.items.append(("WARN", code, key, message))

    @property
    def errors(self) -> list[tuple[str, str, str, str]]:
        return [item for item in self.items if item[0] == "ERROR"]

    @property
    def warnings(self) -> list[tuple[str, str, str, str]]:
        return [item for item in self.items if item[0] == "WARN"]

    def by_code(self) -> dict[str, int]:
        return dict(Counter(code for _l, code, _k, _m in self.items))


def check(key: str, zh: str, status: str, glossary: dict, findings: Findings,
          menu_length: int, is_menu: bool = False) -> None:
    english = key
    interpolations = len(SWIFT_INTERPOLATION.findall(english))
    english_placeholders = len(PLACEHOLDER.findall(english.replace("%%", "")))

    # E1 覆盖率
    if status == "new" or not zh.strip():
        findings.error("E1", key, "缺少译文")
        return

    # E7 状态一致性（verbatim 是「专名不翻」的显式声明，与原文相同是正确结果）
    if status == "translated" and zh.strip() == english.strip() and interpolations == 0:
        findings.error("E7", key, "译文与英文原文完全相同，疑似未译却标为 translated")

    # E2 占位符
    zh_placeholders = len(PLACEHOLDER.findall(zh.replace("%%", "")))
    expected = interpolations + english_placeholders
    if zh_placeholders != expected:
        findings.error("E2", key,
                       f"占位符数量不符：原文 {expected}（插值 {interpolations} + 显式 {english_placeholders}），"
                       f"译文 {zh_placeholders}")

    # E3 术语（termOverrides 里登记过的多义词按 allow 列表放行）
    terms = glossary.get("terms", {})
    overrides = glossary.get("termOverrides", {})
    if english in terms and zh.strip() != terms[english]:
        allowed = overrides.get(english, {}).get("allow", [])
        if zh.strip() not in allowed:
            findings.error("E3", key, f"与术语表不一致：应为「{terms[english]}」")

    # E4 禁用译法。先剔除正确写法：否则「不透明度」会被「透明度」规则误判，
    # 「色调对比度」会被「色调对比」规则误判。
    forbidden = glossary.get("forbidden", {})
    hard = forbidden.get("hard", {})
    soft = forbidden.get("soft", {}) if isinstance(forbidden.get("soft"), dict) else {}
    residue = zh
    for right in list(hard.values()) + list(soft.values()):
        if right in residue:
            residue = residue.replace(right, "\u0000")
    for wrong, right in hard.items():
        if wrong in residue and wrong != right:
            findings.error("E4", key, f"出现禁用译法「{wrong}」，应为「{right}」")
    for wrong, right in soft.items():
        if wrong in residue and wrong != right:
            findings.warn("E4", key, f"「{wrong}」在此语境可能需要改作「{right}」")

    # E5 省略号
    if english.rstrip().endswith("…") and not zh.rstrip().endswith("…"):
        findings.error("E5", key, "原文以 … 结尾，译文未以 … 结尾")

    # E6 不译名
    for token in glossary.get("rules", {}).get("doNotTranslate", []):
        if token in english and token not in zh:
            findings.error("E6", key, f"译文丢失不译名「{token}」")

    # W1 首尾空白
    if english[:1].isspace() != zh[:1].isspace() or english[-1:].isspace() != zh[-1:].isspace():
        findings.warn("W1", key, "首尾空白与原文不一致")

    # W2 长度（只查菜单项；状态栏读数、对话框说明不受 12 字限制）
    if is_menu and len(zh) > menu_length:
        findings.warn("W2", key, f"译文 {len(zh)} 字，超过菜单建议长度 {menu_length}")


def main() -> int:
    parser = argparse.ArgumentParser(description="汉化质量闸门")
    parser.add_argument("--keys", default="l10n/source-keys.json")
    parser.add_argument("--tm", default="l10n/translations.csv")
    parser.add_argument("--glossary", default="l10n/glossary.json")
    parser.add_argument("--report", default=None, help="把结果写成 Markdown")
    parser.add_argument("--only", default=None, help="只跑某一类检查，如 coverage / E2")
    parser.add_argument("--max-print", type=int, default=25, help="每类最多打印多少条")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    def resolve(path: str) -> str:
        return path if os.path.isabs(path) else os.path.join(root, path)

    for path in (args.keys, args.tm, args.glossary):
        if not os.path.exists(resolve(path)):
            print(f"缺少输入文件：{resolve(path)}\n先跑 scripts/l10n/harvest.py", file=sys.stderr)
            return 2

    keys = load_json(resolve(args.keys))
    tm = load_tm(resolve(args.tm))
    glossary = load_json(resolve(args.glossary))
    menu_length = int(re.search(r"(\d+)", glossary.get("rules", {}).get("menuLength", "12")).group(1))

    findings = Findings()
    for key in keys["keys"]:
        text = key["key"]
        row = tm.get(text, {"zh-Hans": "", "status": "new"})
        sites = key.get("sites") or []
        is_menu = any("/CompositorApp.swift" in (site.get("file") or "") for site in sites)
        check(text, row["zh-Hans"], row.get("status", "new"), glossary, findings, menu_length, is_menu)

    # 人工裁定过的条目：只压 WARN，压不住 ERROR。清单本身写在 glossary.reviewed 里，
    # 附理由——「我确认过了」必须留下痕迹，否则下次有人改回去也没人知道。
    reviewed = glossary.get("reviewed", {})
    if reviewed:
        findings.items = [
            item for item in findings.items
            if not (item[0] == "WARN" and item[2] in reviewed)
        ]

    wanted_keys = [entry["key"] for entry in keys["keys"]]
    translated = sum(1 for k in wanted_keys if tm.get(k, {}).get("status") in ("translated", "verbatim"))
    total = len(keys["keys"])

    if args.only:
        wanted = args.only.lower()
        selected = [item for item in findings.items
                    if item[1].lower() == wanted or (wanted == "coverage" and item[1] == "E1")]
        findings.items = selected

    errors, warnings = findings.errors, findings.warnings
    print(f"键总数 {total}｜已译 {translated}（{translated * 100 // max(1, total)}%）")
    print(f"ERROR {len(errors)} 条，WARN {len(warnings)} 条")

    grouped: dict[str, list] = defaultdict(list)
    for item in findings.items:
        grouped[item[1]].append(item)

    for code in sorted(grouped):
        items = grouped[code]
        level = items[0][0]
        print(f"\n[{level}] {code} — {len(items)} 条")
        seen = set()
        shown = 0
        for _lvl, _code, key, message in items:
            if key in seen:
                continue
            seen.add(key)
            print(f"  {message}\n    key: {key[:96]!r}")
            shown += 1
            if shown >= args.max_print:
                print(f"  … 其余 {len(items) - shown} 条省略")
                break

    if args.report:
        with open(resolve(args.report), "w", encoding="utf-8") as handle:
            handle.write("# 汉化质量报告\n\n")
            handle.write(f"- 键总数：{total}\n- 已译：{translated}（{translated * 100 // max(1, total)}%）\n")
            handle.write(f"- ERROR：{len(errors)}\n- WARN：{len(warnings)}\n\n")
            for code in sorted(grouped):
                handle.write(f"## {code}（{len(grouped[code])}）\n\n")
                for _lvl, _code, key, message in grouped[code]:
                    handle.write(f"- {message}\n  - `{key}`\n")
                handle.write("\n")
        print(f"\n报告已写入 {resolve(args.report)}")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
