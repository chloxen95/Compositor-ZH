import Foundation

extension LayerEffectKind {
    /// 图层样式（描边、投影、发光……）的名字。`rawValue` 只用于标识，见 DisplayNames.swift。
    nonisolated var displayName: String {
        switch self {
        case .stroke: String(localized: "Stroke", comment: "Layer effect")
        case .shadow: String(localized: "Drop Shadow", comment: "Layer effect")
        case .colorOverlay: String(localized: "Color Overlay", comment: "Layer effect")
        case .innerShadow: String(localized: "Inner Shadow", comment: "Layer effect")
        case .outerGlow: String(localized: "Outer Glow", comment: "Layer effect")
        case .innerGlow: String(localized: "Inner Glow", comment: "Layer effect")
        }
    }
}
