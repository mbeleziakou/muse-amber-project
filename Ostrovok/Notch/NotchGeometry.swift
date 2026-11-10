import AppKit

struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    var hasHardwareNotch: Bool

    static func current() -> NotchGeometry {
        let screen = pickScreen()
        return make(for: screen)
    }

    static func make(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let menuBar = max(24, frame.maxY - screen.visibleFrame.maxY)
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let w = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: w, height: screen.safeAreaInsets.top), hasHardwareNotch: true)
        }
        if Prefs.emulateNotch {
            return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: 185, height: max(32, menuBar)), hasHardwareNotch: true)
        }
        return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: 180, height: menuBar), hasHardwareNotch: false)
    }

    static func pickScreen() -> NSScreen {
        let screens = NSScreen.screens
        switch Prefs.display {
        case .notch:
            return screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens[0]
        case .main:
            return screens.first ?? NSScreen.main!
        case .mouse:
            let p = NSEvent.mouseLocation
            return screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main ?? screens[0]
        }
    }
}
