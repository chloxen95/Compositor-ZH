// 语言偏好的独立自检程序。
//
// 为什么不是 XCTest：本机的受限会话里 `xcodebuild test` 起不了测试宿主
// （宿主进程根本没被注入 XCTest 镜像，原因见 l10n/RELEASE.md §六）。
// 但「可测试」这条原则不能因此打折，所以把纯逻辑抽成不依赖 SwiftUI/AppKit 的类，
// 用 swiftc 直接编成一个可执行程序去断言——不依赖 Xcode 的测试流程。
//
// 跑法：
//   ./scripts/l10n/selftest-language.sh
//
// 覆盖的是最容易写错、且错了不会被界面暴露的那几条：
//   · 「跟随系统」必须删键，而不是写一个猜出来的值
//   · 写进去的必须是系统真正读的 AppleLanguages
//   · 值没变时不该提示重启（否则菜单会一直亮着「重新启动」）
//   · 系统语言是 ja/zh-Hant 这类我们没提供的情况，应视作「跟随系统」

import Foundation

final class FakeStore: LanguageStoring {
    var values: [String: Any] = [:]
    private(set) var writes = 0
    private(set) var removals = 0

    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }

    func set(_ value: Any?, forKey key: String) {
        writes += 1
        values[key] = value
    }

    func removeObject(forKey key: String) {
        removals += 1
        values.removeValue(forKey: key)
    }
}

@main
struct LanguageSelfTest {
    static var failures = 0
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if condition {
            print("  ✅ \(message)")
        } else {
            failures += 1
            print("  ❌ \(message)")
        }
    }

    static func main() {
        print("▸ LanguagePreference 自检")

        // 1. 没有键 = 跟随系统
        let store = FakeStore()
        let preference = LanguagePreference(store: store)
        expect(preference.current == .system, "空存储时判定为「跟随系统」")

        // 2. 选简体中文：写 AppleLanguages，且写的是数组
        let changed = preference.apply(.simplifiedChinese)
        expect(changed, "切换语言报告「有变化」")
        expect(store.values[LanguagePreference.defaultsKey] as? [String] == ["zh-Hans"],
               "写入了 AppleLanguages = [zh-Hans]（CFBundle 读的就是这个键）")
        expect(preference.current == .simplifiedChinese, "写入后 current 立刻反映新值")
        expect(preference.pendingRelaunch, "写入后置位「待重启」")

        // 3. 重复选同一项：不写盘、不提示重启
        let writesBefore = store.writes
        let changedAgain = preference.apply(.simplifiedChinese)
        expect(!changedAgain, "重复选择同一语言报告「无变化」")
        expect(store.writes == writesBefore, "重复选择不产生多余写盘")
        expect(!preference.pendingRelaunch, "重复选择不提示重启")

        // 4. 跟随系统 = 删键，而不是写 ["en"]
        let back = preference.apply(.system)
        expect(back, "切回「跟随系统」报告「有变化」")
        expect(store.values[LanguagePreference.defaultsKey] == nil,
               "「跟随系统」删除了 AppleLanguages，而不是写入猜出来的值")
        expect(store.removals >= 1, "确实调用了 removeObject")
        expect(preference.current == .system, "删除后 current 回到「跟随系统」")

        // 5. 系统给了别的语言（我们没提供）：视作跟随系统，而不是硬塞英文
        store.values[LanguagePreference.defaultsKey] = ["ja-JP"]
        expect(preference.current == .system, "系统语言为日语时判定为「跟随系统」")
        store.values[LanguagePreference.defaultsKey] = ["zh-Hant-TW"]
        expect(preference.current == .system, "系统语言为繁体中文时判定为「跟随系统」")

        // 6. 带地区的写法要能识别
        store.values[LanguagePreference.defaultsKey] = ["zh-Hans-CN"]
        expect(preference.current == .simplifiedChinese, "zh-Hans-CN 识别为简体中文")
        store.values[LanguagePreference.defaultsKey] = ["en-GB"]
        expect(preference.current == .english, "en-GB 识别为英文")

        // 7. 显式选英文
        store.values.removeAll()
        preference.apply(.english)
        expect(store.values[LanguagePreference.defaultsKey] as? [String] == ["en"], "显式选英文写入 [en]")
        expect(preference.current == .english, "显式选英文后 current 为 .english")

        print(failures == 0
              ? "✅ 自检通过（\(checks) 项断言）"
              : "❌ 自检失败：\(failures)/\(checks) 项断言未通过")
        exit(failures == 0 ? 0 : 1)
    }
}
