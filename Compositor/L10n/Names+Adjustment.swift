import Foundation

extension AdjustmentKind {
    /// 调整图层与滤镜菜单里的名字。`rawValue` 是工程文件里 `"kind"` 的身份。
    nonisolated var displayName: String {
        switch self {
        case .hsv: String(localized: "Hue/Saturation", comment: "Adjustment")
        case .levels: String(localized: "Levels", comment: "Adjustment")
        case .curves: String(localized: "Curves", comment: "Adjustment")
        case .exposure: String(localized: "Exposure", comment: "Adjustment")
        case .gradientMap: String(localized: "Gradient Map", comment: "Adjustment")
        case .grain: String(localized: "Grain", comment: "Adjustment")
        case .addNoise: String(localized: "Add Noise", comment: "Adjustment")
        case .gaussianBlur: String(localized: "Gaussian Blur", comment: "Adjustment")
        case .motionBlur: String(localized: "Motion Blur", comment: "Adjustment")
        case .invert: String(localized: "Invert", comment: "Adjustment")
        case .blackWhite: String(localized: "Black & White", comment: "Adjustment")
        case .colorBalance: String(localized: "Color Balance", comment: "Adjustment")
        case .progressiveBlur: String(localized: "Progressive Blur", comment: "Adjustment")
        case .bloomGlow: String(localized: "Bloom / Glow", comment: "Adjustment")
        case .rgbSplit: String(localized: "RGB Split", comment: "Adjustment")
        case .vignette: String(localized: "Vignette", comment: "Adjustment")
        case .lensEffects: String(localized: "Lens Effects", comment: "Adjustment")
        case .tonalContrast: String(localized: "Tonal Contrast", comment: "Adjustment")
        case .sharpen: String(localized: "Sharpen", comment: "Adjustment")
        }
    }
}

extension LevelsChannel {
    /// 色阶、曲线的通道选择。Photoshop 简中版就是单字：红、绿、蓝。
    nonisolated var displayName: String {
        switch self {
        case .rgb: String(localized: "RGB", comment: "Channel")
        case .red: String(localized: "Red", comment: "Channel")
        case .green: String(localized: "Green", comment: "Channel")
        case .blue: String(localized: "Blue", comment: "Channel")
        }
    }
}

extension ColorRange {
    /// 色相/饱和度的颜色范围。Photoshop 的下拉是「全图、红色、黄色、绿色、青色、蓝色、洋红」，
    /// Master 在简中版里叫「全图」，不是「主通道」。
    nonisolated var displayName: String {
        switch self {
        case .master: String(localized: "Master", comment: "Hue/Saturation range")
        case .reds: String(localized: "Reds", comment: "Hue/Saturation range")
        case .yellows: String(localized: "Yellows", comment: "Hue/Saturation range")
        case .greens: String(localized: "Greens", comment: "Hue/Saturation range")
        case .cyans: String(localized: "Cyans", comment: "Hue/Saturation range")
        case .blues: String(localized: "Blues", comment: "Hue/Saturation range")
        case .magentas: String(localized: "Magentas", comment: "Hue/Saturation range")
        }
    }
}
