#!/usr/bin/env python3
"""从 Swift 源码抽取可本地化字符串，产出键清单与规模报告。

为什么需要它：Xcode 的 `xcodebuild -exportLocalizations` 是权威抽取器，但它需要 Xcode。
本脚本做两件事——在没有 Xcode 时给出可信的规模与分布，以及为翻译/校对/Lint 提供机器可读清单。
两者在 Xcode 到位后应当对账：以 Xcode 为准，本脚本结果用于发现「Xcode 抽不到的东西」
（典型是 String 形参通路的界面文案，见 docs 里 P2 的说明）。

抽取的 API（SwiftUI 隐式 LocalizedStringKey）：
    Text / Button / Toggle / Label / Menu / Picker / TextField / SecureField
    .help / .navigationTitle / .accessibilityLabel / .accessibilityHint
以及显式 API：
    String(localized:) / NSLocalizedString
以及 AppKit 手工构建（这些**不会**被 Xcode 自动抽取，必须靠本脚本发现）：
    NSMenuItem(title:) / NSAlert 的 messageText / informativeText / addButton(withTitle:)
    panel.show(title:)

输出：
    l10n/keys.json     机器可读清单
    stdout             摘要

用法：
    scripts/l10n/extract.py [--src Compositor] [--out l10n/keys.json] [--quiet]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone

# SwiftUI 的隐式本地化入口：字面量会被当作 LocalizedStringKey。
SWIFTUI_APIS = (
    "Text", "Button", "Toggle", "Label", "Menu", "Picker", "TextField",
    "SecureField", "Stepper", "Link", "HelpLink",
)

# 修饰符形式：.help("…")、.accessibilityLabel("…") 等。
MODIFIER_APIS = (
    "help", "navigationTitle", "navigationSubtitle",
    "accessibilityLabel", "accessibilityHint", "accessibilityValue",
)

# 显式本地化入口。`String(...)` 不在此列：`String("x")` 与本地化无关，
# 只有 `String(localized:)` 才算，由 STRING_LOCALIZED 单独识别。
EXPLICIT_APIS = ("NSLocalizedString",)


@dataclass
class Site:
    file: str
    line: int
    api: str
    key: str
    interpolated: bool
    explicit: bool


@dataclass
class Report:
    sites: list[Site] = field(default_factory=list)

    def keys(self) -> dict[str, list[Site]]:
        grouped: dict[str, list[Site]] = {}
        for site in self.sites:
            grouped.setdefault(site.key, []).append(site)
        return grouped


def strip_comments_and_find_strings(source: str) -> list[tuple[int, int, str, bool]]:
    """扫描源码，返回 (起始偏移, 偏移所在行号, 字符串内容, 是否含插值)。

    用一个手写扫描器而不是正则，原因是注释里的示例代码、URL 字符串里的 `//`、
    多行字符串都会骗过逐行正则。
    """
    results: list[tuple[int, int, str, bool]] = []
    i, n = 0, len(source)
    line = 1
    while i < n:
        ch = source[i]

        if ch == "\n":
            line += 1
            i += 1
            continue

        # 行注释
        if ch == "/" and i + 1 < n and source[i + 1] == "/":
            while i < n and source[i] != "\n":
                i += 1
            continue

        # 块注释（可嵌套，Swift 允许）
        if ch == "/" and i + 1 < n and source[i + 1] == "*":
            depth, i = 1, i + 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif source.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    if source[i] == "\n":
                        line += 1
                    i += 1
            continue

        # 多行字符串 """
        if source.startswith('"""', i):
            start_line = line
            i += 3
            buf = []
            while i < n and not source.startswith('"""', i):
                if source[i] == "\n":
                    line += 1
                buf.append(source[i])
                i += 1
            i += 3
            text = "".join(buf)
            results.append((i, start_line, text, "\\(" in text))
            continue

        # 普通字符串
        if ch == '"':
            start_line = line
            i += 1
            buf = []
            while i < n:
                if source[i] == "\\" and i + 1 < n:
                    buf.append(source[i])
                    buf.append(source[i + 1])
                    i += 2
                    continue
                if source[i] == '"':
                    i += 1
                    break
                if source[i] == "\n":
                    line += 1
                buf.append(source[i])
                i += 1
            text = "".join(buf)
            results.append((i, start_line, text, "\\(" in text))
            continue

        i += 1
    return results


# 在字符串之前的窗口里找「这是哪个 API 在调用它」。
CALL_BEFORE = re.compile(
    r"(" + "|".join(SWIFTUI_APIS + MODIFIER_APIS + EXPLICIT_APIS) + r")\s*\(\s*$"
)
MODIFIER_BEFORE = re.compile(r"\.(" + "|".join(MODIFIER_APIS) + r")\s*\(\s*$")
STRING_LOCALIZED = re.compile(r"String\s*\(\s*localized\s*:\s*$")
NSMENU_TITLE = re.compile(r"NSMenuItem\s*\(\s*title\s*:\s*$")
PANEL_TITLE = re.compile(r"show\s*\(\s*title\s*:\s*$")
ALERT_PROPERTY = re.compile(r"(messageText|informativeText)\s*=\s*$")
ALERT_BUTTON = re.compile(r"addButton\s*\(\s*withTitle\s*:\s*$")
SUPPRESSION = re.compile(r"suppressionButton\?\.title\s*=\s*$")


def api_before(source: str, offset: int) -> tuple[str, bool] | None:
    """看字符串字面量前面紧邻的代码，判断它属于哪个本地化入口。"""
    window = source[max(0, offset - 200):offset]
    if STRING_LOCALIZED.search(window):
        return ("String(localized:)", True)
    if NSMENU_TITLE.search(window):
        return ("NSMenuItem(title:)", True)
    if PANEL_TITLE.search(window):
        return ("panel.show(title:)", True)
    if ALERT_PROPERTY.search(window):
        return ("NSAlert.text", True)
    if ALERT_BUTTON.search(window):
        return ("NSAlert.addButton", True)
    if SUPPRESSION.search(window):
        return ("NSAlert.suppressionButton", True)
    m = MODIFIER_BEFORE.search(window)
    if m:
        return ("." + m.group(1), False)
    m = CALL_BEFORE.search(window)
    if m:
        name = m.group(1)
        if name in EXPLICIT_APIS:
            return (name, True)
        return (name + "(\"…\")", False)
    return None


# 明显不是界面文案的字符串：符号名、格式化串、资源名、字体、快捷键等。
NON_UI = re.compile(
    r"^(?:"
    r"[a-z0-9._-]+"                       # 小写标识符 / 资源名 / 域名
    r"|[A-Za-z0-9+._-]+\.[a-z]{2,4}"      # 文件名
    r"|[\W_]+"                             # 纯符号
    r")$"
)


def looks_like_ui_text(text: str) -> bool:
    if not text.strip():
        return False
    if "\n" in text and len(text) > 300:
        return False
    if NON_UI.match(text) and " " not in text:
        return False
    # 至少有字母，且不是纯标识符/路径
    if not re.search(r"[A-Za-z]", text):
        return False
    if text.startswith("/") or text.startswith("http"):
        return False
    if "\\u{" in text:  # 快捷键控制字符
        return False
    return True


def relative(path: str, root: str) -> str:
    return os.path.relpath(path, root)


def scan(root: str, src_dir: str) -> Report:
    report = Report()
    for dirpath, _dirnames, filenames in os.walk(src_dir):
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="ignore") as handle:
                source = handle.read()
            for offset, line, text, interpolated in strip_comments_and_find_strings(source):
                hit = api_before(source, offset - len(text) - 2)
                if hit is None:
                    continue
                api, explicit = hit
                if not looks_like_ui_text(text):
                    continue
                report.sites.append(Site(
                    file=relative(path, root), line=line, api=api,
                    key=text, interpolated=interpolated, explicit=explicit,
                ))
    return report


def summarize(report: Report, out_path: str) -> None:
    grouped = report.keys()
    interpolated = [k for k, sites in grouped.items() if any(s.interpolated for s in sites)]
    explicit = [k for k, sites in grouped.items() if any(s.explicit for s in sites)]

    by_api: dict[str, int] = {}
    for site in report.sites:
        by_api[site.api] = by_api.get(site.api, 0) + 1

    by_file: dict[str, int] = {}
    for site in report.sites:
        by_file[site.file] = by_file.get(site.file, 0) + 1

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tool": "scripts/l10n/extract.py",
        "note": "启发式清单。Xcode 的 xcodebuild -exportLocalizations 为权威来源，两者需对账。",
        "sites": len(report.sites),
        "uniqueKeys": len(grouped),
        "interpolatedKeys": len(interpolated),
        "explicitAPISites": sum(1 for s in report.sites if s.explicit),
        "byAPI": dict(sorted(by_api.items(), key=lambda kv: -kv[1])),
        "byFile": dict(sorted(by_file.items(), key=lambda kv: -kv[1])),
        "keys": [
            {
                "key": key,
                "interpolated": any(s.interpolated for s in sites),
                "explicit": any(s.explicit for s in sites),
                "sites": [{"file": s.file, "line": s.line, "api": s.api} for s in sites],
            }
            for key, sites in sorted(grouped.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        ],
    }

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"调用点 {len(report.sites)} 处，不重复 key {len(grouped)} 条")
    print(f"其中含插值 {len(interpolated)} 条，显式 API（String(localized:) 等）{payload['explicitAPISites']} 处")
    print("\n按 API 分布：")
    for api, count in list(by_api.items())[:14]:
        print(f"  {count:5d}  {api}")
    print(f"\n清单已写入 {out_path}")


def write_tm(report: Report, csv_path: str) -> None:
    """生成/更新翻译记忆库（TM）。已存在的条目保留译文，只追加新出现的 key。

    这是「跟随上游」的关键资产：上游改了文案，旧条目变成孤儿、新 key 变成待译，
    但已完成的译文不会因为代码变动而丢失。
    """
    import csv

    grouped = report.keys()
    existing: dict[str, dict[str, str]] = {}
    if os.path.exists(csv_path):
        with open(csv_path, encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                existing[row["key"]] = row

    os.makedirs(os.path.dirname(csv_path) or ".", exist_ok=True)
    added = 0
    with open(csv_path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["key", "zh-Hans", "status", "note"])
        for key, sites in sorted(grouped.items()):
            row = existing.get(key)
            if row is None:
                added += 1
                note = "含插值，需人工核对占位符" if any(s.interpolated for s in sites) else ""
                writer.writerow([key, "", "new", note])
            else:
                writer.writerow([key, row.get("zh-Hans", ""), row.get("status", "new"), row.get("note", "")])

    orphans = len(set(existing) - set(grouped))
    print(f"TM 已更新 {csv_path}：新增 {added} 条，遗留 {orphans} 条孤儿（上游已删除或改文案）")


def main() -> int:
    parser = argparse.ArgumentParser(description="抽取 Swift 源码中的可本地化字符串")
    parser.add_argument("--src", default="Compositor", help="源码目录（默认 Compositor）")
    parser.add_argument("--out", default="l10n/keys.json", help="输出清单路径")
    parser.add_argument("--quiet", action="store_true", help="只写文件，不打印摘要")
    parser.add_argument("--csv", default=None,
                        help="同时生成/更新翻译记忆库 CSV（默认 l10n/translations.csv）")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    src_dir = args.src if os.path.isabs(args.src) else os.path.join(root, args.src)
    out_path = args.out if os.path.isabs(args.out) else os.path.join(root, args.out)

    if not os.path.isdir(src_dir):
        print(f"找不到源码目录：{src_dir}", file=sys.stderr)
        return 2

    report = scan(root, src_dir)
    if args.quiet:
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        grouped = report.keys()
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump({"sites": len(report.sites), "uniqueKeys": len(grouped),
                       "keys": list(grouped)}, handle, ensure_ascii=False, indent=2)
    else:
        summarize(report, out_path)

    if args.csv is not None:
        csv_path = args.csv or os.path.join(root, "l10n", "translations.csv")
        if not os.path.isabs(csv_path):
            csv_path = os.path.join(root, csv_path)
        write_tm(report, csv_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
