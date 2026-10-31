import Foundation

extension ShapeKind {
    nonisolated var displayName: String {
        switch self {
        case .rectangle: String(localized: "Rectangle", comment: "Shape")
        case .ellipse: String(localized: "Ellipse", comment: "Shape")
        case .line: String(localized: "Line", comment: "Shape")
        }
    }
}

extension ShapeLineStyle {
    nonisolated var displayName: String {
        switch self {
        case .solid: String(localized: "Solid", comment: "Stroke style")
        case .dotted: String(localized: "Dotted", comment: "Stroke style")
        case .dashed: String(localized: "Dashed", comment: "Stroke style")
        case .longDash: String(localized: "Long Dash", comment: "Stroke style")
        }
    }
}

extension ShapeLineCap {
    nonisolated var displayName: String {
        switch self {
        case .square: String(localized: "Square", comment: "Stroke cap")
        case .round: String(localized: "Round", comment: "Stroke cap")
        }
    }
}

extension TextAlignment {
    /// 文字对齐的提示语。这里连着动词一起本地化，而不是显示单词再加前缀：
    /// 原代码是 `"Align " + alignment.rawValue.lowercased()`，中文语序里没有对应位置，
    /// 拆开拼只能拼出「对齐 left」。整句成键才能翻成「左对齐」。
    nonisolated var alignmentName: String {
        switch self {
        case .left: String(localized: "Align left", comment: "Text alignment")
        case .center: String(localized: "Align center", comment: "Text alignment")
        case .right: String(localized: "Align right", comment: "Text alignment")
        }
    }
}

extension CanvasGuide.Axis {
    /// 参考线的方向。rawValue 是小写的 "horizontal"/"vertical"，那是文件格式，不能直接显示。
    nonisolated var displayName: String {
        switch self {
        case .horizontal: String(localized: "Horizontal", comment: "Guide orientation")
        case .vertical: String(localized: "Vertical", comment: "Guide orientation")
        }
    }
}

extension GIFDelayMode {
    nonisolated var displayName: String {
        switch self {
        case .perFrame: String(localized: "Frame delay", comment: "GIF timing")
        case .uniform: String(localized: "Same for all", comment: "GIF timing")
        }
    }
}

extension LayerSampling {
    /// 缩放取样方式，对应 Photoshop 图像大小里的「邻近、平滑、高品质」一档。
    nonisolated var displayName: String {
        switch self {
        case .nearest: String(localized: "Nearest", comment: "Resampling")
        case .smooth: String(localized: "Smooth", comment: "Resampling")
        case .high: String(localized: "High quality", comment: "Resampling")
        }
    }
}

extension CanvasUnit {
    /// 「画布大小」「图像大小」的单位下拉。`rawValue` 是身份，不是文案。
    nonisolated var displayName: String {
        switch self {
        case .pixels: String(localized: "Pixels", comment: "Canvas unit")
        case .percent: String(localized: "Percent", comment: "Canvas unit")
        case .inches: String(localized: "Inches", comment: "Canvas unit")
        case .centimeters: String(localized: "Centimeters", comment: "Canvas unit")
        }
    }
}

extension CanvasExtension {
    nonisolated var displayName: String {
        switch self {
        case .transparent: String(localized: "Transparent", comment: "Canvas extension")
        case .foreground: String(localized: "Foreground", comment: "Canvas extension")
        case .background: String(localized: "Background", comment: "Canvas extension")
        case .white: String(localized: "White", comment: "Canvas extension")
        case .black: String(localized: "Black", comment: "Canvas extension")
        case .custom: String(localized: "Custom", comment: "Canvas extension")
        }
    }
}
