#!/usr/bin/env swift
// 界面截图的三个动作，合成一个脚本，免得每次现写。
//
//   ./shot.swift list                     列出正在运行的应用窗口（id / 尺寸 / 标题）
//   ./shot.swift capture <id> <out.png>   按窗口抓图（不受遮挡影响，原生 2x）
//   ./shot.swift crop <in> <out> x y w h  精确裁剪
//
// 为什么不用 `sips --cropOffset`：它的偏移是相对**居中**裁剪原点算的，
// 同一组坐标在不同高度的图上会剪到完全不同的位置，排查时极易误判。
//
// 为什么按窗口抓而不是全屏抓：全屏会带进桌面与其它应用，2x 图上还要猜坐标；
// 按窗口抓拿到的是窗口自身坐标系，裁剪坐标与 SwiftUI 里的 point 一一对应（乘 2）。
//
// 需要「屏幕录制」权限（CGPreflightScreenCaptureAccess）。不需要「辅助功能」——
// 窗口列表对任何进程开放，只有点击/读控件树才需要辅助功能。

import AppKit
import CoreGraphics

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func list() {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        fail("拿不到窗口列表")
    }
    var seen = Set<String>()
    for window in windows {
        let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
        guard owner.contains("Compositor") else { continue }
        let id = window[kCGWindowNumber as String] as? Int ?? -1
        let title = window[kCGWindowName as String] as? String ?? ""
        var size = "?"
        if let b = window[kCGWindowBounds as String] as? [String: Any],
           let w = b["Width"] as? Double, let h = b["Height"] as? Double,
           let x = b["X"] as? Double, let y = b["Y"] as? Double {
            size = "\(Int(w))x\(Int(h)) @ (\(Int(x)),\(Int(y)))"
        }
        // 同一 id 只报一次；窗口在屏幕外时这里看不到——那是「没有窗口」的常见误判来源。
        guard seen.insert("\(id)").inserted else { continue }
        print("id=\(id)  \(size)  \(title.isEmpty ? "<无标题>" : title)")
    }
}

func capture(id: String, out: String) {
    guard CGPreflightScreenCaptureAccess() else {
        fail("没有屏幕录制权限：系统设置 › 隐私与安全性 › 屏幕录制")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // -x 静音，-o 去掉窗口阴影，-l 指定窗口
    process.arguments = ["-x", "-o", "-l\(id)", out]
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: out) else {
        fail("抓图失败（窗口 id 可能已失效，重新跑 list）")
    }
    print("已写出 \(out)")
}

func crop(input: String, output: String, x: Int, y: Int, w: Int, h: Int) {
    guard let image = NSImage(contentsOfFile: input),
          let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("读不了 \(input)")
    }
    guard let cropped = source.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
        fail("裁剪超出边界：图是 \(source.width)×\(source.height)")
    }
    let rep = NSBitmapImageRep(cgImage: cropped)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("编码失败") }
    try? data.write(to: URL(fileURLWithPath: output))
    print("已写出 \(output)（\(cropped.width)×\(cropped.height)）")
}

let args = CommandLine.arguments
switch args.count >= 2 ? args[1] : "list" {
case "list":
    list()
case "capture" where args.count == 4:
    capture(id: args[2], out: args[3])
case "crop" where args.count == 8:
    guard let x = Int(args[4]), let y = Int(args[5]),
          let w = Int(args[6]), let h = Int(args[7]) else { fail("crop 的坐标要是整数") }
    crop(input: args[2], output: args[3], x: x, y: y, w: w, h: h)
default:
    print("用法：")
    print("  ./shot.swift list")
    print("  ./shot.swift capture <窗口id> <输出.png>")
    print("  ./shot.swift crop <输入.png> <输出.png> <x> <y> <宽> <高>")
    exit(2)
}
