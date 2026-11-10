import AppKit
import SwiftUI
import Observation

enum NotchMode: Equatable {
    case idle
    case peek
    case expanded
    case saved(UUID)
    case focusDone
    case breakPrompt
    case breakDone
}

enum ExpandedTab { case recents, calendar }

/// Что сейчас показывает фигура (с учётом приоритетов S5 > S6/S7 > S1 > S0).
enum Presentation: Equatable {
    case idle, timer, peek, expanded, saved, focusDone, breakPrompt, breakDone, meeting
}

@MainActor
@Observable
final class NotchController {
    static let shared = NotchController()

    var geometry = NotchGeometry.current()
    var mode: NotchMode = .idle
    var tab: ExpandedTab = .recents
    var pinned = UserDefaults.standard.bool(forKey: Keys.pinned) {
        didSet { UserDefaults.standard.set(pinned, forKey: Keys.pinned) }
    }
    var draft = ""
    var draftImages: [Data] = []
    var shake: CGFloat = 0
    var measured: [Presentation: CGFloat] = [:]
    var meetingFlash = false
    var hiddenForFullscreen = false
    var focusRequest = 0
    @ObservationIgnored private var peekHovered = false

    @ObservationIgnored let focus = FocusController.shared
    @ObservationIgnored var panel: NotchPanel?
    @ObservationIgnored private var hoverWork: DispatchWorkItem?
    @ObservationIgnored private var collapseWork: DispatchWorkItem?
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var fullscreenTimer: Timer?

    // MARK: Presentation & geometry

    var presentation: Presentation {
        switch mode {
        case .peek: return .peek
        case .expanded: return .expanded
        case .saved: return .saved
        case .focusDone: return .focusDone
        case .breakDone: return .breakDone
        case .breakPrompt: return hiddenForFullscreen ? .idle : .breakPrompt
        case .idle:
            if hiddenForFullscreen { return .idle }
            if meetingFlash { return .meeting }
            if focus.isActive && Prefs.showTimerInWings { return .timer }
            return .idle
        }
    }

    struct Frame: Equatable { var width: CGFloat; var height: CGFloat; var radius: CGFloat; var ear: CGFloat }

    var frame: Frame {
        let n = geometry.notchSize
        let extra = measured[presentation] ?? 0
        switch presentation {
        case .idle: return Frame(width: n.width, height: n.height, radius: 10, ear: 6)
        case .timer: return Frame(width: n.width + 150, height: n.height + 8, radius: 12, ear: 8)
        case .saved: return Frame(width: n.width + 260, height: n.height, radius: 12, ear: 8)
        case .breakPrompt, .meeting: return Frame(width: n.width + 240, height: n.height, radius: 12, ear: 8)
        case .peek: return Frame(width: max(460, n.width + 120), height: max(extra, n.height + 60), radius: 24, ear: 12)
        case .expanded: return Frame(width: max(640, n.width + 200), height: max(extra, n.height + 120), radius: 32, ear: 14)
        case .focusDone, .breakDone: return Frame(width: max(460, n.width + 160), height: max(extra, n.height + 60), radius: 24, ear: 12)
        }
    }

    /// Прямоугольник фигуры в экранных координатах.
    var shapeRect: CGRect {
        let f = frame, s = geometry.screenFrame
        return CGRect(x: s.midX - f.width / 2 - f.ear, y: s.maxY - f.height, width: f.width + 2 * f.ear, height: f.height)
    }

    var isInteractive: Bool { mode == .peek || mode == .expanded }

    // MARK: Setup

    func setup() {
        let panel = NotchPanel()
        self.panel = panel
        panel.contentView = FirstMouseHostingView(rootView: NotchRootView().modelContainer(DataStore.shared.container))
        layoutPanel()
        panel.orderFrontRegardless()

        focus.onFinished = { [weak self] s in self?.handleFinished(s) }
        focus.onMeetingSoon = { [weak self] in self?.flashMeeting() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.sharingType = Prefs.hideOnShare ? .none : .readOnly
                self?.refreshGeometry()
            }
        }
        installMonitors()
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullscreen() }
        }
        panel.sharingType = Prefs.hideOnShare ? .none : .readOnly
        if pinned { open(.expanded) }
    }

    func refreshGeometry() {
        let g = NotchGeometry.current()
        if g != geometry { geometry = g; layoutPanel() }
    }

    private func layoutPanel() {
        guard let panel else { return }
        let s = geometry.screenFrame
        let size = NSSize(width: 900, height: 620)
        panel.setFrame(NSRect(x: s.midX - size.width / 2, y: s.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: Mouse & keys

    private func installMonitors() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moved) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moved) { [weak self] e in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return e
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return MainActor.assumeIsolated { self.handleKey(e) ? nil : e }
        } as Any)
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        if Prefs.display == .mouse, !NSMouseInRect(p, geometry.screenFrame, false) { refreshGeometry() }
        let rect = shapeRect
        panel?.ignoresMouseEvents = !rect.contains(p)

        switch mode {
        case .idle, .breakPrompt:
            let hot = rect.insetBy(dx: -4, dy: 0)
            if hot.contains(p) {
                if hoverWork == nil {
                    let w = DispatchWorkItem { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.hoverWork = nil
                            if self.shapeRect.insetBy(dx: -4, dy: 0).contains(NSEvent.mouseLocation),
                               self.mode == .idle || self.mode == .breakPrompt { self.open(.peek) }
                        }
                    }
                    hoverWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
                }
            } else {
                hoverWork?.cancel(); hoverWork = nil
            }
        case .peek:
            if rect.contains(p) { peekHovered = true }
            guard peekHovered else { break }
            let far = !rect.insetBy(dx: -40, dy: -40).contains(p)
            if far && ThoughtText.isBlank(draft) && draftImages.isEmpty { collapse() }
        default: break
        }
    }

    private func clickedOutside() {
        // Глобальный монитор видит только клики мимо наших окон.
        switch mode {
        case .expanded where !pinned: collapse()
        case .peek where ThoughtText.isBlank(draft) && draftImages.isEmpty: collapse()
        default: break
        }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.window === panel else { return false }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if e.keyCode == 53 { escape(); return true }
        if mods == .command, e.charactersIgnoringModifiers == "z", case .saved(let id) = mode {
            undoSave(id); return true
        }
        if mods == .command, e.charactersIgnoringModifiers == "v", pasteImageIfAny() { return true }
        return false
    }

    private func pasteImageIfAny() -> Bool {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) != nil, pb.data(forType: .png) == nil, pb.data(forType: .tiff) == nil { return false }
        if let png = pb.data(forType: .png) { draftImages.append(png); return true }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            draftImages.append(png); return true
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL], !urls.isEmpty {
            for u in urls { if let d = try? Data(contentsOf: u) { draftImages.append(d) } }
            return true
        }
        return false
    }

    // MARK: Transitions

    func open(_ m: NotchMode) {
        collapseWork?.cancel()
        if !isInteractive, let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        if m == .expanded && mode != .expanded { tab = .recents }
        withAnimation(Theme.morph) { mode = m }
        if m == .peek { peekHovered = shapeRect.contains(NSEvent.mouseLocation) }
        if m == .peek || m == .expanded {
            panel?.makeKey()
            focusRequest += 1
        }
        panel?.ignoresMouseEvents = !shapeRect.contains(NSEvent.mouseLocation)
    }

    func toggleExpanded() {
        mode == .expanded ? collapse() : open(.expanded)
    }

    func collapse() {
        collapseWork?.cancel()
        hoverWork?.cancel(); hoverWork = nil
        let wasKey = panel?.isKeyWindow ?? false
        withAnimation(Theme.morph) { mode = .idle }
        if wasKey { returnFocus() }
        panel?.ignoresMouseEvents = !shapeRect.contains(NSEvent.mouseLocation)
    }

    private func returnFocus() {
        panel?.resignKey()
        if !LibraryWindowController.shared.isVisible, let prev = previousApp, !prev.isTerminated {
            prev.activate()
        }
    }

    func escape() {
        switch mode {
        case .expanded where tab == .calendar:
            withAnimation(Theme.morph) { tab = .recents }
        case .expanded, .peek:
            if mode == .expanded && pinned { pinned = false }
            collapse()
        case .focusDone, .breakDone: collapse()
        default: collapse()
        }
    }

    // MARK: Saving

    func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftImages.isEmpty else {
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
            return
        }
        let source: ThoughtSource = text.isEmpty ? .paste : .typed
        let t = DataStore.shared.addThought(text: text, source: source, images: draftImages, session: focus.currentSession)
        draft = ""
        draftImages = []
        let returnToExpanded = pinned && mode == .expanded
        withAnimation(Theme.morph) { mode = .saved(t.id) }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .saved = self.mode else { return }
                if returnToExpanded { self.open(.expanded) } else { self.collapse() }
            }
        }
        collapseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }

    func undoSave(_ id: UUID) {
        if let t = DataStore.shared.thought(id: id) {
            let text = t.text
            DataStore.shared.delete(t)
            draft = text
        }
        open(.peek)
    }

    // MARK: Focus events

    private func handleFinished(_ s: TimerState) {
        if mode == .expanded || mode == .peek { return }
        withAnimation(Theme.morph) { mode = s.kind == .focus ? .focusDone : .breakDone }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.mode == .focusDone {
                    withAnimation(Theme.morph) { self.mode = self.focus.isActive ? .idle : .breakPrompt }
                } else if self.mode == .breakDone {
                    self.collapse()
                }
            }
        }
        collapseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: w)
    }

    func startBreakFromCard() {
        focus.startBreak()
        focus.dismissFinished()
        collapse()
    }

    func startFocusFromCard() {
        focus.startFocus()
        focus.dismissFinished()
        collapse()
    }

    private func flashMeeting() {
        withAnimation(Theme.morph) { meetingFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            MainActor.assumeIsolated { withAnimation(Theme.morph) { self?.meetingFlash = false } }
        }
    }

    // MARK: Fullscreen

    private func updateFullscreen() {
        guard Prefs.hideInFullscreen else { if hiddenForFullscreen { hiddenForFullscreen = false }; return }
        let fs = Self.frontAppIsFullscreen(on: geometry.screenFrame)
        let nearTop = NSEvent.mouseLocation.y >= geometry.screenFrame.maxY - 6
        let hide = fs && !nearTop
        if hide != hiddenForFullscreen { withAnimation(Theme.morph) { hiddenForFullscreen = hide } }
    }

    static func frontAppIsFullscreen(on screen: CGRect) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.height
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: primaryHeight - (b["Y"] ?? 0) - (b["Height"] ?? 0), width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if abs(rect.width - screen.width) < 1, abs(rect.height - screen.height) < 1, abs(rect.minX - screen.minX) < 1 { return true }
        }
        return false
    }
}
