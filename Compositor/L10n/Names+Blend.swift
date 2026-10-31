import Foundation

extension LayerBlendMode {
    /// 混合模式的名字。取自 Photoshop 简中版：正片叠底、滤色、叠加、实色混合……
    ///
    /// `rawValue` 是工程文件里的身份（`"blendMode": "Multiply"`），这里只负责显示。
    nonisolated var displayName: String {
        switch self {
        case .normal: String(localized: "Normal", comment: "Blend mode")
        case .darken: String(localized: "Darken", comment: "Blend mode")
        case .multiply: String(localized: "Multiply", comment: "Blend mode")
        case .colorBurn: String(localized: "Color Burn", comment: "Blend mode")
        case .linearBurn: String(localized: "Linear Burn", comment: "Blend mode")
        case .lighten: String(localized: "Lighten", comment: "Blend mode")
        case .screen: String(localized: "Screen", comment: "Blend mode")
        case .colorDodge: String(localized: "Color Dodge", comment: "Blend mode")
        case .linearDodge: String(localized: "Linear Dodge (Add)", comment: "Blend mode")
        case .overlay: String(localized: "Overlay", comment: "Blend mode")
        case .softLight: String(localized: "Soft Light", comment: "Blend mode")
        case .hardLight: String(localized: "Hard Light", comment: "Blend mode")
        case .vividLight: String(localized: "Vivid Light", comment: "Blend mode")
        case .linearLight: String(localized: "Linear Light", comment: "Blend mode")
        case .pinLight: String(localized: "Pin Light", comment: "Blend mode")
        case .hardMix: String(localized: "Hard Mix", comment: "Blend mode")
        case .difference: String(localized: "Difference", comment: "Blend mode")
        case .exclusion: String(localized: "Exclusion", comment: "Blend mode")
        case .subtract: String(localized: "Subtract", comment: "Blend mode")
        case .divide: String(localized: "Divide", comment: "Blend mode")
        case .hue: String(localized: "Hue", comment: "Blend mode")
        case .saturation: String(localized: "Saturation", comment: "Blend mode")
        case .color: String(localized: "Color", comment: "Blend mode")
        case .luminosity: String(localized: "Luminosity", comment: "Blend mode")
        }
    }
}
