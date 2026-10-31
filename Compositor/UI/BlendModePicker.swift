import SwiftUI
import AppKit

struct BlendModePicker: NSViewRepresentable {
    let session: EditorSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        // Grouped as Photoshop groups them — darkening, lightening, contrast, comparative, component —
        // with a line between, so a long list stays readable.
        for (index, group) in LayerBlendMode.groups.enumerated() {
            if index > 0 { button.menu?.addItem(.separator()) }
            for mode in group {
                button.addItem(withTitle: mode.displayName)
                // The title is for people; the represented object is the identity. Reading the mode back
                // from the title would break the moment the interface is translated — and it did: the
                // title used to be `rawValue`, which is the value stored in project files.
                button.lastItem?.representedObject = mode.rawValue
            }
        }
        button.menu?.delegate = context.coordinator
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityLabel(String(localized: "Blend mode"))
        // A capsule like the SwiftUI buttons and menus (`roundedControls`), which don't reach this AppKit pop-up.
        button.borderShape = .capsule
        return button
    }
    /// As wide as it's offered. Left to itself, the pop-up insists on the width of its longest mode, wider than a
    /// narrow Layers panel has room for, and that pushed the whole panel out past its edges.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSPopUpButton, context: Context) -> CGSize? {
        let natural = button.intrinsicContentSize
        guard let width = proposal.width, width.isFinite else { return natural }
        return CGSize(width: max(width, 60), height: natural.height)
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = session.canEditAppearance
        if !context.coordinator.tracking {
            Self.select(session.activeLayer?.blendMode ?? .normal, in: button)
        }
    }
    static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
        if coordinator.tracking { coordinator.session.previewBlendMode(nil, for: nil) }
        button.menu?.delegate = nil
    }
    /// The mode an item stands for. Separators carry no represented object and come back nil.
    static func mode(of item: NSMenuItem?) -> LayerBlendMode? {
        guard let raw = item?.representedObject as? String else { return nil }
        return LayerBlendMode(rawValue: raw)
    }
    /// Selecting by identity rather than by title, so the menu keeps working in every language.
    static func select(_ mode: LayerBlendMode, in button: NSPopUpButton) {
        guard let item = button.itemArray.first(where: { ($0.representedObject as? String) == mode.rawValue })
        else { return }
        button.select(item)
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        let session: EditorSession
        var tracking = false
        private var layerID: UUID?
        private var highlightedMode: LayerBlendMode?
        init(session: EditorSession) { self.session = session }
        func menuWillOpen(_ menu: NSMenu) {
            tracking = true
            layerID = session.activeLayerID
            highlightedMode = nil
        }
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            // AppKit briefly reports no highlighted item while dismissing the menu.
            // Keep the last preview alive until the selection action has committed so
            // the canvas never flashes back to the layer's previous mode.
            guard let mode = BlendModePicker.mode(of: item) else { return }
            highlightedMode = mode
            session.previewBlendMode(mode, for: layerID)
        }
        func menuDidClose(_ menu: NSMenu) {
            tracking = false
            // A chosen item's action runs as the menu finishes closing. Clearing on the
            // next turn lets that action replace the preview with the committed mode;
            // when the menu was cancelled, this simply restores the original mode.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.tracking else { return }
                self.session.previewBlendMode(nil, for: nil)
            }
        }
        @objc func choose(_ button: NSPopUpButton) {
            guard session.activeLayerID == layerID,
                  let mode = highlightedMode ?? BlendModePicker.mode(of: button.selectedItem) else { return }
            session.setLayerBlendMode(mode)
            BlendModePicker.select(mode, in: button)
            highlightedMode = nil
            session.refreshCanvasPreview?()
        }
    }
}
