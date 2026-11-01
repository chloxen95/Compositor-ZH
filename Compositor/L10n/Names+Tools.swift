import Foundation

// 纯显示枚举：`rawValue` 是英文文案，直接塞进下拉框，中文界面里就是英文。
// 这里统一补 `displayName`，`rawValue` 一律不动——它是身份（撤销名、滤镜参数、
// 可能出现在工程文件里的字符串），改它等于改数据格式。
//
// 与 `Names+Adjustment` / `Names+Filters` / `Names+Canvas` 同一套约定：穷举 switch，
// 上游新增取值时编译失败，不会静默漏翻。

extension DitherColors {
    var displayName: String {
        switch self {
        case .blackWhite: String(localized: "Black & White", comment: "Dither colors")
        case .twoColors: String(localized: "Two Colors", comment: "Dither colors")
        case .original: String(localized: "Original", comment: "Dither colors")
        }
    }
}

extension DitherPixelShape {
    var displayName: String {
        switch self {
        case .square: String(localized: "Square", comment: "Dither pixel shape")
        case .dot: String(localized: "Dot", comment: "Dither pixel shape")
        }
    }
}

extension BackgroundQuality {
    var displayName: String {
        switch self {
        case .basic: String(localized: "Basic", comment: "Background quality")
        case .advanced: String(localized: "Advanced", comment: "Background quality")
        }
    }
}

extension GradientShape {
    var displayName: String {
        switch self {
        case .linear: String(localized: "Linear", comment: "Gradient shape")
        case .radial: String(localized: "Radial", comment: "Gradient shape")
        }
    }
}

extension GradientStyle {
    var displayName: String {
        switch self {
        case .foregroundToBackground: String(localized: "Foreground to Background", comment: "Gradient style")
        case .foregroundToTransparent: String(localized: "Foreground to Transparent", comment: "Gradient style")
        }
    }
}

extension WandMode {
    var displayName: String {
        switch self {
        case .wand: String(localized: "Wand", comment: "Wand mode")
        case .object: String(localized: "Object", comment: "Wand mode")
        }
    }
}

extension SelectionMode {
    var displayName: String {
        switch self {
        case .replace: String(localized: "New", comment: "Selection mode")
        case .add: String(localized: "Add", comment: "Selection mode")
        case .subtract: String(localized: "Subtract", comment: "Selection mode")
        }
    }
}

extension BrushToolMode {
    var displayName: String {
        switch self {
        case .paint: String(localized: "Paint", comment: "Brush mode")
        case .erase: String(localized: "Erase", comment: "Brush mode")
        }
    }
}

extension BlurToolMode {
    var displayName: String {
        switch self {
        case .liquify: String(localized: "Liquify", comment: "Blur tool mode")
        case .blur: String(localized: "Blur", comment: "Blur tool mode")
        case .smudge: String(localized: "Smudge", comment: "Blur tool mode")
        }
    }
}

extension SpotHealingMode {
    var displayName: String {
        switch self {
        case .contentAware: String(localized: "Content-Aware", comment: "Spot healing mode")
        case .createTexture: String(localized: "Create Texture", comment: "Spot healing mode")
        case .proximityMatch: String(localized: "Proximity Match", comment: "Spot healing mode")
        }
    }
}

// MARK: - Camera Raw

extension CameraRawWhiteBalance {
    var displayName: String {
        switch self {
        case .custom: String(localized: "Custom", comment: "White balance")
        case .auto: String(localized: "Auto", comment: "White balance")
        }
    }
}

extension CameraRawGlowStyle {
    var displayName: String {
        switch self {
        case .diffusion: String(localized: "Diffusion", comment: "Glow style")
        case .bloom: String(localized: "Bloom", comment: "Glow style")
        case .halation: String(localized: "Halation", comment: "Glow style")
        }
    }
}

extension CameraRawVignetteStyle {
    var displayName: String {
        switch self {
        case .highlightPriority: String(localized: "Highlight Priority", comment: "Vignette style")
        case .colorPriority: String(localized: "Color Priority", comment: "Vignette style")
        case .paintOverlay: String(localized: "Paint Overlay", comment: "Vignette style")
        }
    }
}

extension CameraRawUprightMode {
    var displayName: String {
        switch self {
        case .off: String(localized: "Off", comment: "Upright mode")
        case .guided: String(localized: "Guided", comment: "Upright mode")
        }
    }
}

extension CameraRawProjection {
    var displayName: String {
        switch self {
        case .perspective: String(localized: "Perspective", comment: "Projection")
        case .rectilinear: String(localized: "Rectilinear", comment: "Projection")
        }
    }
}

extension CameraRawProcessVersion {
    var displayName: String {
        switch self {
        case .version1: String(localized: "Version 1", comment: "Process version")
        case .version2: String(localized: "Version 2", comment: "Process version")
        case .version3: String(localized: "Version 3", comment: "Process version")
        case .version4: String(localized: "Version 4", comment: "Process version")
        case .version5: String(localized: "Version 5", comment: "Process version")
        case .version6: String(localized: "Version 6", comment: "Process version")
        }
    }
}

extension CameraRawScopeMode {
    var displayName: String {
        switch self {
        case .histogram: String(localized: "Histogram", comment: "Scope mode")
        case .vectorscope: String(localized: "Vectorscope", comment: "Scope mode")
        }
    }
}

extension CameraRawCurvePage {
    var displayName: String {
        switch self {
        case .parametric: String(localized: "Parametric", comment: "Curve page")
        case .point: String(localized: "Point", comment: "Curve page")
        }
    }
}

extension CameraRawPointChannel {
    var displayName: String {
        switch self {
        case .rgb: String(localized: "RGB", comment: "Point curve channel")
        case .red: String(localized: "Red", comment: "Point curve channel")
        case .green: String(localized: "Green", comment: "Point curve channel")
        case .blue: String(localized: "Blue", comment: "Point curve channel")
        }
    }
}

extension CameraRawMixerPage {
    var displayName: String {
        switch self {
        case .hsl: String(localized: "HSL", comment: "Mixer page")
        case .color: String(localized: "Color", comment: "Mixer page")
        case .point: String(localized: "Point Color", comment: "Mixer page")
        }
    }
}

extension CameraRawMixerTab {
    var displayName: String {
        switch self {
        case .hue: String(localized: "Hue", comment: "Mixer tab")
        case .saturation: String(localized: "Saturation", comment: "Mixer tab")
        case .luminance: String(localized: "Luminance", comment: "Mixer tab")
        }
    }
}

extension CameraRawGradePage {
    var displayName: String {
        switch self {
        case .threeWay: String(localized: "Three-Way", comment: "Color grade page")
        case .shadows: String(localized: "Shadows", comment: "Color grade page")
        case .midtones: String(localized: "Midtones", comment: "Color grade page")
        case .highlights: String(localized: "Highlights", comment: "Color grade page")
        case .global: String(localized: "Global", comment: "Color grade page")
        }
    }
}

// MARK: - 网格外观（嵌套在 GridAppearance 里）

extension GridAppearance.Preset {
    var displayName: String {
        switch self {
        case .lightGray: String(localized: "Light Gray", comment: "Grid color")
        case .lightBlue: String(localized: "Light Blue", comment: "Grid color")
        case .lightRed: String(localized: "Light Red", comment: "Grid color")
        case .green: String(localized: "Green", comment: "Grid color")
        case .mediumBlue: String(localized: "Medium Blue", comment: "Grid color")
        case .yellow: String(localized: "Yellow", comment: "Grid color")
        case .magenta: String(localized: "Magenta", comment: "Grid color")
        case .cyan: String(localized: "Cyan", comment: "Grid color")
        case .black: String(localized: "Black", comment: "Grid color")
        case .custom: String(localized: "Custom", comment: "Grid color")
        }
    }
}

extension GridAppearance.Style {
    var displayName: String {
        switch self {
        case .lines: String(localized: "Lines", comment: "Grid line style")
        case .dashedLines: String(localized: "Dashed Lines", comment: "Grid line style")
        case .dots: String(localized: "Dots", comment: "Grid line style")
        }
    }
}

extension EditorSession.SelectionAmountOperation {
    /// 浮动面板标题。整句成键，不在调用点拼 "\(名字) Selection"——那样的插值不好译。
    var panelTitle: String {
        switch self {
        case .expand: String(localized: "Expand Selection", comment: "Panel title")
        case .contract: String(localized: "Contract Selection", comment: "Panel title")
        case .feather: String(localized: "Feather Selection", comment: "Panel title")
        }
    }
}
