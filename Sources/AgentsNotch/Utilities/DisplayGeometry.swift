import AppKit
import Foundation

struct DisplayGeometry: Equatable {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let centerX: CGFloat
    let hasPhysicalNotch: Bool

    /// Placeholder for the rare no-screen window (clamshell boot, screenless
    /// launch). The display-change observer replaces it as soon as a screen
    /// appears, so only rough proportions matter here.
    static let fallback = DisplayGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        notchWidth: 176,
        notchHeight: 30,
        centerX: 720,
        hasPhysicalNotch: false
    )

    static func detect(on screen: NSScreen) -> DisplayGeometry {
        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea
        let safeTop = screen.safeAreaInsets.top

        let detectedWidth: CGFloat?
        if let leftArea, let rightArea, rightArea.minX > leftArea.maxX {
            detectedWidth = rightArea.minX - leftArea.maxX
        } else {
            detectedWidth = nil
        }

        let hasNotch = safeTop > 0 && detectedWidth != nil
        let notchWidth = hasNotch ? max(detectedWidth ?? 0, 120) : 176
        let notchHeight = hasNotch ? max(safeTop, 28) : 30

        return DisplayGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            centerX: screen.frame.midX,
            hasPhysicalNotch: hasNotch
        )
    }
}

enum DisplayPreference: String, CaseIterable, Identifiable {
    case primary
    case pointer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .primary: "Primary display"
        case .pointer: "Display under pointer"
        }
    }
}

enum DisplayResolver {
    static func preferredScreen() -> NSScreen? {
        let raw = UserDefaults.standard.string(forKey: AppPreferences.Key.displayPreference)
            ?? DisplayPreference.primary.rawValue
        if raw == DisplayPreference.pointer.rawValue {
            let location = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        }
        return NSScreen.screens.first ?? NSScreen.main
    }
}
