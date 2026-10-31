import Foundation

extension FilterKind {
    /// 滤镜菜单与图像菜单里的名字。`rawValue` 是身份（撤销动作、工程文件里可能出现的字符串），
    /// 不是文案：菜单直接用 `rawValue` 拼字符串，整块「滤镜」菜单在中文界面里就是英文。
    /// 与 `AdjustmentKind.displayName` 同一条约定——穷举 switch，上游新增滤镜时编译失败。
    nonisolated var displayName: String {
        switch self {
        case .gaussianBlur: String(localized: "Gaussian Blur", comment: "Filter")
        case .motionBlur: String(localized: "Motion Blur", comment: "Filter")
        case .progressiveBlur: String(localized: "Progressive Blur", comment: "Filter")
        case .sharpen: String(localized: "Sharpen", comment: "Filter")
        case .addNoise: String(localized: "Add Noise", comment: "Filter")
        case .vignette: String(localized: "Vignette", comment: "Filter")
        case .bloomGlow: String(localized: "Bloom / Glow", comment: "Filter")
        case .dither: String(localized: "Dither", comment: "Filter")
        case .scanlines: String(localized: "Scanlines", comment: "Filter")
        case .rgbSplit: String(localized: "RGB Split", comment: "Filter")
        case .lensEffects: String(localized: "Lens Effects", comment: "Filter")
        case .tonalContrast: String(localized: "Tonal Contrast", comment: "Filter")
        case .rimLight: String(localized: "Rim Light", comment: "Filter")
        case .lensCorrection: String(localized: "Lens Correction", comment: "Filter")
        case .cameraRaw: String(localized: "Camera Raw Filter", comment: "Filter")
        case .removeBackground: String(localized: "Remove Background", comment: "Filter")
        case .contentAwareFill: String(localized: "Content-Aware Fill", comment: "Filter")
        case .curves: String(localized: "Curves", comment: "Filter")
        case .exposure: String(localized: "Exposure", comment: "Filter")
        case .gradientMap: String(localized: "Gradient Map", comment: "Filter")
        case .grain: String(localized: "Grain", comment: "Filter")
        case .blackWhite: String(localized: "Black & White", comment: "Filter")
        case .colorBalance: String(localized: "Color Balance", comment: "Filter")
        }
    }
}
