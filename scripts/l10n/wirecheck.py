#!/usr/bin/env python3
"""冻结工程的「线上格式」：枚举 rawValue 与 Codable 字段名。

为什么需要这个闸门
------------------
项目文件是 manifest.json（JSONEncoder 直出）。里面存的不是数字，是人能读的英文：

    "blendMode": "Multiply"
    "adjustment": { "kind": "Gaussian Blur", ... }

所以 rawValue 是**文件格式**，不是文案。汉化一旦顺手把 rawValue 改成「正片叠底」，
中文版存的工程英文版就打不开了，而且不会有任何报错——只会读失败或静默回落到默认值。

rawValue 还被当成别的东西用，这四条都在生产代码里：
  · 反向查找：LayerBlendMode(rawValue: menuItem.title)  ← 改成中文标题就永远匹配不上
  · 拖拽载荷：item.setString(uuid + ":" + kind.rawValue, ...)
  · 资源名：  image("style." + style.rawValue)
  · 偏好键：  ToolDefaults.set(preset.rawValue, "gridColor")

结论：rawValue 永久冻结。要给人看的字走 displayName（见 Compositor/L10n/）。

用法
----
    python3 scripts/l10n/wirecheck.py            # 校验（CI / 提交前）
    python3 scripts/l10n/wirecheck.py --update   # 认可当前状态，重写指纹
    python3 scripts/l10n/wirecheck.py --against main   # 与某个 git ref 比，看上游动没动

`--against` 的用途：并入上游后想知道「rawValue 的变化是上游带来的还是我手滑改的」。
上游带来的：跑 --update 接受，并在提交信息里写明。我手滑改的：改回去。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Compositor"
MANIFEST = ROOT / "l10n" / "wire-format.json"


# ---------------------------------------------------------------- 源码脱敏

def blank(src: str) -> str:
    """把注释与字符串字面量换成等长空格，好让括号配对照常工作。

    等长是关键：脱敏后的偏移量可以直接拿去原文取值。注释里的花括号、字符串里的
    引号都不会再把解析带偏。块注释的分隔符也要补齐两个字符，否则偏移会错位。
    """
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth += 1
                    out.append("  ")
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if src[i] == "\n" else " ")
                    i += 1
        elif c == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n:
                    if src[j] == "\\":
                        j += 2
                        continue
                    if src[j] == '"':
                        j += 1
                        break
                    j += 1
            out.append(" " * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


DECL = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*"
    r"(?:public |internal |private |fileprivate |nonisolated |final |indirect )*"
    r"(struct|enum|class|actor)\s+(\w+)\s*(?::([^{\n]*))?",
    re.M,
)
CASE_LINE = re.compile(r"^[ \t]*case[ \t]+([^\n]+)", re.M)
STORED = re.compile(r"^[ \t]*(?:var|let)[ \t]+(\w+)[ \t]*:[ \t]*([^=\n{]+)", re.M)
CODING_KEY = re.compile(r"^[ \t]*case[ \t]+([^\n]+)", re.M)


def body_of(src: str, start: int) -> tuple[str, int]:
    """返回 (花括号内的内容, 内容起点)。找不到返回 ("", -1)。"""
    open_at = src.find("{", start)
    if open_at < 0:
        return "", -1
    depth = 0
    for j in range(open_at, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[open_at + 1 : j], open_at + 1
    return src[open_at + 1 :], open_at + 1


def split_cases(text: str) -> list[tuple[str, str]]:
    """解析 case 列表，允许多个 case 同行、允许不写 rawValue。"""
    found: list[tuple[str, str]] = []
    for line in CASE_LINE.findall(text):
        for part in line.split(","):
            m = re.match(r'\s*(\w+)\s*=\s*"([^"]*)"', part)
            if m:
                found.append((m.group(1), m.group(2)))
                continue
            m = re.match(r"\s*(\w+)\s*$", part)
            if m:
                found.append((m.group(1), m.group(1)))
    return found


def scan(source: pathlib.Path, base: pathlib.Path | None = None) -> dict:
    """产出一张快照：{类型名: {...}}，字符串枚举按 rawValue 记账，Codable 结构按字段名记账。

    `base` 只用来算报告里的相对路径（--against 时源码在临时目录里）。
    """
    base = base or ROOT
    enums: dict[str, dict] = {}
    structs: dict[str, dict] = {}

    for path in sorted(source.rglob("*.swift")):
        raw = path.read_text(encoding="utf-8", errors="replace")
        if "enum " not in raw and "struct " not in raw:
            continue
        masked = blank(raw)
        decls = []
        for m in DECL.finditer(masked):
            body, body_start = body_of(masked, m.start())
            if body_start < 0:
                continue
            decls.append(
                {
                    "kind": m.group(1),
                    "name": m.group(2),
                    "inherit": (m.group(3) or "").strip(),
                    "start": body_start,
                    "end": body_start + len(body),
                    "body": body,
                    "raw_start": body_start,
                    "file": str(path.relative_to(base)),
                }
            )
        # 嵌套关系：落在别人体内的声明，名字前面挂上外层类型，避免 Axis / Preset / Section 撞名。
        for decl in decls:
            parents = [
                d
                for d in decls
                if d is not decl and d["start"] <= decl["start"] and decl["end"] <= d["end"]
            ]
            parents.sort(key=lambda d: d["start"])
            qualified = ".".join([p["name"] for p in parents] + [decl["name"]])
            decl["qualified"] = qualified

            # 取原文的同一段（偏移等长，可直接切）
            raw_body = raw[decl["raw_start"] : decl["raw_start"] + (decl["end"] - decl["start"])]

            if decl["kind"] == "enum" and re.search(r"\bString\b", decl["inherit"]):
                cases = split_cases(raw_body)
                if not cases:
                    continue  # 没有显式取值的枚举，rawValue 就是 case 名，改不了（编译期就锁住了）
                enums[qualified] = {
                    "file": decl["file"],
                    "rawValues": {case: wire for case, wire in cases},
                }
            elif decl["kind"] == "struct" and re.search(r"\bCodable\b|\bEncodable\b", decl["inherit"]):
                masked_body = masked[decl["start"] : decl["start"] + (decl["end"] - decl["start"])]
                fields = sorted({name for name, _ in STORED.findall(masked_body)})
                if fields:
                    structs[qualified] = {"file": decl["file"], "fields": fields}

    version = None
    store = base / "Compositor" / "IO" / "ProjectStore.swift"
    if store.exists():
        m = re.search(r"static let current\s*=\s*(\d+)", store.read_text(encoding="utf-8"))
        if m:
            version = int(m.group(1))

    return {
        "note": "工程文件格式的指纹。由 scripts/l10n/wirecheck.py 生成，不要手改。",
        "manifestVersion": version,
        "stringEnums": dict(sorted(enums.items())),
        "codableStructs": dict(sorted(structs.items())),
    }


def load(path: pathlib.Path) -> dict | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def from_git(ref: str) -> dict:
    """把某个 ref 的源码导到临时目录再扫，用来判断变化是谁带来的。"""
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        archive = subprocess.run(
            ["git", "archive", ref, "Compositor"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        )
        subprocess.run(["tar", "-x", "-C", tmp], input=archive.stdout, check=True)
        return scan(pathlib.Path(tmp) / "Compositor", pathlib.Path(tmp))


def diff(old: dict, new: dict) -> list[str]:
    problems: list[str] = []
    if old.get("manifestVersion") != new.get("manifestVersion"):
        problems.append(
            f"manifest 版本 {old.get('manifestVersion')} → {new.get('manifestVersion')}（读旧工程的文件要能兼容）"
        )

    old_e, new_e = old.get("stringEnums", {}), new.get("stringEnums", {})
    for name in sorted(set(old_e) | set(new_e)):
        if name not in new_e:
            problems.append(f"枚举消失：{name}")
            continue
        if name not in old_e:
            problems.append(f"新增枚举：{name}（确认它的 rawValue 是 wire 格式后跑 --update）")
            continue
        a, b = old_e[name]["rawValues"], new_e[name]["rawValues"]
        for case in sorted(set(a) | set(b)):
            if case not in b:
                problems.append(f"{name}.{case} 被删除（旧工程里的 {a[case]!r} 将无法解码）")
            elif case not in a:
                problems.append(f"{name}.{case} 新增 = {b[case]!r}")
            elif a[case] != b[case]:
                problems.append(f"{name}.{case} 变了：{a[case]!r} → {b[case]!r}  ← 这会读不了旧工程")

    old_s, new_s = old.get("codableStructs", {}), new.get("codableStructs", {})
    for name in sorted(set(old_s) | set(new_s)):
        if name not in new_s:
            problems.append(f"Codable 结构消失：{name}")
            continue
        if name not in old_s:
            problems.append(f"新增 Codable 结构：{name}")
            continue
        a, b = set(old_s[name]["fields"]), set(new_s[name]["fields"])
        for field in sorted(a - b):
            problems.append(f"{name}.{field} 字段被删（旧工程里的这个键会被丢弃）")
        for field in sorted(b - a):
            problems.append(f"{name}.{field} 字段新增（旧工程没有它，须有默认值）")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="冻结工程文件的线上格式")
    parser.add_argument("--update", action="store_true", help="重写指纹（认可当前状态）")
    parser.add_argument("--against", metavar="REF", help="与某个 git ref 比较，而不是与指纹比较")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    current = scan(SOURCE, ROOT)

    if args.against:
        try:
            old = from_git(args.against)
        except subprocess.CalledProcessError as error:
            print(f"拿不到 {args.against}：{error}", file=sys.stderr)
            return 2
        problems = diff(old, current)
        label = f"与 {args.against} 相比"
    else:
        old = load(MANIFEST)
        if old is None:
            if args.update:
                old = {"stringEnums": {}, "codableStructs": {}, "manifestVersion": current["manifestVersion"]}
            else:
                print(f"没有指纹文件 {MANIFEST.relative_to(ROOT)}，先跑 --update", file=sys.stderr)
                return 2
        problems = diff(old, current)
        label = "与指纹相比"

    if args.update:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(json.dumps(current, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        enums = len(current["stringEnums"])
        values = sum(len(e["rawValues"]) for e in current["stringEnums"].values())
        print(f"✅ 指纹已写入 {MANIFEST.relative_to(ROOT)}：{enums} 个枚举 / {values} 个取值"
              f" / {len(current['codableStructs'])} 个 Codable 结构 / manifest v{current['manifestVersion']}")
        if problems and not args.quiet:
            print(f"   （本次相对旧指纹有 {len(problems)} 处变化，已一并接受）")
        return 0

    if problems:
        print(f"❌ {label}，线上格式有 {len(problems)} 处变化：")
        for problem in problems:
            print(f"   · {problem}")
        print("\nrawValue 是文件格式，不是文案。要显示给人看，走 displayName（Compositor/L10n/）。")
        print("确实是上游带来的变化：跑 --update 接受，并在提交信息里写明。")
        return 1

    if not args.quiet:
        enums = len(current["stringEnums"])
        values = sum(len(e["rawValues"]) for e in current["stringEnums"].values())
        print(f"✅ 线上格式未变：{enums} 个枚举 / {values} 个取值 / "
              f"{len(current['codableStructs'])} 个 Codable 结构 / manifest v{current['manifestVersion']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
