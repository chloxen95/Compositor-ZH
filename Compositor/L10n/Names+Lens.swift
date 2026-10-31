import Foundation

extension LensEffect {
    nonisolated var displayName: String {
        switch self {
        case .anamorphicFlare: String(localized: "Anamorphic Flare", comment: "Lens effect")
        case .starburst: String(localized: "Starburst", comment: "Lens effect")
        case .mist: String(localized: "Mist", comment: "Lens effect")
        case .prism: String(localized: "Prism", comment: "Lens effect")
        case .bokeh: String(localized: "Bokeh", comment: "Lens effect")
        }
    }
}

extension BokehShape {
    nonisolated var displayName: String {
        switch self {
        case .round: String(localized: "Round", comment: "Bokeh shape")
        case .hexagon: String(localized: "Hexagon", comment: "Bokeh shape")
        case .oval: String(localized: "Oval", comment: "Bokeh shape")
        case .catsEye: String(localized: "Cat's Eye", comment: "Bokeh shape")
        }
    }
}
