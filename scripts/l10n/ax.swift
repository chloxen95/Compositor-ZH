#!/usr/bin/env swift
// 读界面、按控件。屏幕录制只能"看"，这个能"点"。
//
//   ./ax.swift menu   <pid>                  打印菜单栏结构（菜单 → 菜单项 → 快捷键 → 启用状态）
//   ./ax.swift tree   <pid> [深度]           打印窗口控件树（角色 / 文字 / 无障碍标识符）
//   ./ax.swift button <pid> <标题>           按标题点按钮
//   ./ax.swift press  <pid> <菜单> <项>…     按标题路径点菜单项（支持多级子菜单）
//   ./ax.swift popup  <pid> <标题>           列出一个弹出框的菜单项（SwiftUI 的 NSPopUpButton 常常取不到，见下）
//
// 权限：只需要「辅助功能」（AXIsProcessTrusted）。不要用 System Events——那要「自动化」
// 权限，是另一项 TCC，没给就报 −10004，看起来像辅助功能没生效，其实不是。
//
// 两个坑：
// 1. `kAXWindowsAttribute` 偶尔为空（窗口刚建或在替换），退回扫 app 子元素，否则误报「没有窗口」。
// 2. SwiftUI 里 NSPopUpButton 弹出的菜单是**独立窗口**（CGWindowList 里 layer=101），
//    不进 AX 树。要读它：先按开，再用 CGWindowList 找到那个窗口，`shot.swift capture` 截图；
//    要选项就用 CGEvent 发方向键 + 回车（`key.swift`）。
//
import ApplicationServices
import AppKit

func fail(_ m: String) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(1)
}

func attr(_ el: AXUIElement, _ key: String) -> Any? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, key as CFString, &value) == .success else { return nil }
    return value
}

func str(_ el: AXUIElement, _ key: String) -> String {
    if let s = attr(el, key) as? String { return s }
    return ""
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func role(_ el: AXUIElement) -> String { str(el, kAXRoleAttribute) }
func title(_ el: AXUIElement) -> String {
    // 菜单项的文字在 Title，按钮在 Title 或 Description，某些控件只有 Value
    let t = str(el, kAXTitleAttribute)
    if !t.isEmpty { return t }
    let d = str(el, kAXDescriptionAttribute)
    if !d.isEmpty { return d }
    let v = str(el, kAXValueAttribute)
    return v
}

func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

func walk(_ el: AXUIElement, depth: Int, max: Int, indent: String = "") {
    let r = role(el)
    let t = title(el)
    let id = str(el, kAXIdentifierAttribute)
    var line = "\(indent)\(r)"
    if !t.isEmpty { line += "  「\(t)」" }
    if !id.isEmpty { line += "  #\(id)" }
    print(line)
    guard depth < max else { return }
    for c in children(el) { walk(c, depth: depth + 1, max: max, indent: indent + "  ") }
}

func menuBar(_ pid: pid_t) -> AXUIElement {
    guard let value = attr(app(pid), kAXMenuBarAttribute) else { fail("拿不到菜单栏") }
    return value as! AXUIElement
}

func press(_ el: AXUIElement) -> Bool {
    AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
}

func dumpMenu(_ pid: pid_t) {
    for top in children(menuBar(pid)) {
        print("■ \(title(top))")
        var menu: AXUIElement?
        for c in children(top) where role(c) == kAXMenuRole as String { menu = c }
        guard let menu else { continue }
        for item in children(menu) {
            switch role(item) {
            case kAXMenuItemRole as String:
                let key = str(item, kAXMenuItemCmdCharAttribute)
                let mark = (attr(item, kAXMenuItemMarkCharAttribute) as? String) ?? ""
                let enabled = (attr(item, kAXEnabledAttribute) as? Bool) ?? true
                var line = "    \(mark.isEmpty ? " " : mark) \(title(item))"
                if !key.isEmpty { line += "   [\(key)]" }
                if !enabled { line += "   (禁用)" }
                print(line)
            case kAXMenuBarItemRole as String:
                print("    -- 子菜单 \(title(item))")
            default:
                if !title(item).isEmpty { print("    · \(title(item))") }
            }
        }
    }
}

func pathOfMenus(_ pid: pid_t, _ names: [String]) -> AXUIElement? {
    var current: AXUIElement = menuBar(pid)
    for (index, name) in names.enumerated() {
        var found: AXUIElement?
        for child in children(current) {
            if index == 0 {
                if title(child) == name { found = child; break }
            } else if title(child) == name {
                found = child; break
            }
        }
        guard let found else { return nil }
        current = found
        // 菜单项下面挂着真正的 NSMenu
        if index < names.count - 1 {
            for c in children(current) where role(c) == kAXMenuRole as String { current = c }
        }
    }
    return current
}

func findButton(_ el: AXUIElement, _ wanted: String, depth: Int = 0) -> AXUIElement? {
    if depth > 24 { return nil }
    let t = title(el)
    if (role(el) == kAXButtonRole as String || role(el) == kAXPopUpButtonRole as String) && t == wanted { return el }
    for c in children(el) {
        if let hit = findButton(c, wanted, depth: depth + 1) { return hit }
    }
    return nil
}

func windows(_ pid: pid_t) -> [AXUIElement] {
    // kAXWindowsAttribute 偶尔为空（窗口刚建/正在替换），退回扫 app 的子元素，
    // 否则会误报「没有窗口」，然后被当成崩溃去查。
    if let list = attr(app(pid), kAXWindowsAttribute) as? [AXUIElement], !list.isEmpty { return list }
    return children(app(pid)).filter { role($0) == kAXWindowRole as String }
}

/// 已打开的弹出菜单挂在 app 的子树里（不在窗口里），按标题找菜单项并按下。
func pickMenuItem(_ pid: pid_t, _ wanted: String) -> Bool {
    func search(_ el: AXUIElement, _ depth: Int) -> AXUIElement? {
        if depth > 6 { return nil }
        if role(el) == kAXMenuItemRole as String, title(el) == wanted { return el }
        for c in children(el) { if let hit = search(c, depth + 1) { return hit } }
        return nil
    }
    for c in children(app(pid)) {
        if let hit = search(c, 0) { return press(hit) }
    }
    return false
}

let a = CommandLine.arguments
guard a.count >= 3, let pid = pid_t(a[2]) else {
    print("用法: ax <tree|menu|press|button|popup|pick> <pid> …"); exit(2)
}

switch a[1] {
case "tree":
    let depth = a.count > 3 ? Int(a[3]) ?? 6 : 6
    for w in windows(pid) {
        walk(w, depth: 0, max: depth)
    }
case "menu":
    dumpMenu(pid)
case "press":
    let names = Array(a[3...])
    guard let item = pathOfMenus(pid, names) else { fail("找不到菜单路径 \(names.joined(separator: " › "))") }
    print(press(item) ? "已点击 \(names.joined(separator: " › "))" : "点击失败")
case "button":
    guard let w = windows(pid).first else { fail("没有窗口") }
    guard let b = findButton(w, a[3]) else { fail("找不到按钮「\(a[3])」") }
    print(press(b) ? "已点击按钮「\(a[3])」" : "点击失败")
case "popup":
    guard let w = windows(pid).first, let p = findButton(w, a[3]) else { fail("找不到弹出框「\(a[3])」") }
    _ = press(p)
    usleep(400_000)
    for c in children(app(pid)) {
        if role(c) == kAXMenuRole as String {
            for item in children(c) { print("  \(title(item))") }
        }
    }
default:
    fail("未知命令 \(a[1])")
}
