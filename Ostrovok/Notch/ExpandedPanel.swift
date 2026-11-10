import SwiftUI
import SwiftData
import AppKit

/// "Catch a thought…" — glass input shared by S2 and S3.
struct CaptureField: View {
    var compact: Bool
    @State private var c = NotchController.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                SparkleIcon(text: c.draft)

                TextField("Catch a thought…", text: $c.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: compact ? 15 : 16, weight: .regular))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.vertical, 5)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            c.draft += "\n"
                            return .handled
                        }
                        c.submit()
                        return .handled
                    }
                    .accessibilityLabel("Thought")

                Button { c.submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .symbolEffect(.bounce.up, value: canSend)
                        .foregroundStyle(canSend ? Theme.onAccent : .white.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .background {
                            Circle().fill(canSend ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.08)))
                                .shadow(color: .white.opacity(canSend ? 0.35 : 0), radius: 8)
                        }
                        .overlay(Circle().strokeBorder(.white.opacity(canSend ? 0 : 0.12)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .scaleEffect(canSend ? 1 : 0.9)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: canSend)
                .animatedIcon()
                .accessibilityLabel("Save")
            }
            if !c.draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(c.draftImages.enumerated()), id: \.offset) { i, data in
                            ZStack(alignment: .topTrailing) {
                                if let img = NSImage(data: data) {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18)))
                                }
                                Button { c.draftImages.remove(at: i) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                        .animatedIcon()
                                        .frame(width: 16, height: 16).background(Circle().fill(.black.opacity(0.75)))
                                }
                                .buttonStyle(.plain).offset(x: 4, y: -4)
                                .accessibilityLabel("Remove image")
                            }
                            .popIn(i)
                        }
                    }
                    .padding(.top, 4).padding(.trailing, 6)
                }
                .padding(.leading, 40)
            }
        }
        .padding(.leading, 10).padding(.trailing, 9).padding(.vertical, 8)
        .glass(22, active: focused)
        .borderGlow(radius: 22, colors: [.white.opacity(0.7), Theme.spark.mix(.white, 0.5), .white.opacity(0.4)])
        .modifier(Shake(animatableData: c.shake))
        .onAppear { requestFocus() }
        .onChange(of: c.focusRequest) { requestFocus() }
    }

    private var canSend: Bool { !ThoughtText.isBlank(c.draft) || !c.draftImages.isEmpty }

    private func requestFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }
}

struct ExpandedPanel: View {
    @State private var c = NotchController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                FocusRow()
                Spacer()
                GooeyNav(items: [.init(id: ExpandedTab.recents, label: "Recent"),
                                 .init(id: ExpandedTab.calendar, label: "Calendar")],
                         selection: Binding(get: { c.tab }, set: { t in
                             withAnimation(Theme.morph) { c.tab = t }
                             if t == .calendar { Task { await CalendarService.shared.requestAccess() } }
                         }),
                         compact: true)
            }
            CaptureField(compact: false)
            Group {
                if c.tab == .recents { RecentsStrip().transition(.blurFade) }
                else { CalendarPane().transition(.blurFade) }
            }
            BottomBar()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }
}

struct FocusRow: View {
    @State private var f = FocusController.shared
    @State private var showPresets = false
    @State private var custom = ""

    var body: some View {
        HStack(spacing: 10) {
            Button { f.toggle() } label: {
                Image(systemName: f.state?.isRunning == true ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.accent).shadow(color: .white.opacity(0.25), radius: 10))
                    .overlay {
                        if f.isActive {
                            ProgressRing(progress: f.progress, tint: f.kind.isBreak ? Theme.mint : Theme.amber, lineWidth: 2.4)
                                .frame(width: 46, height: 46)
                        }
                    }
            }
            .buttonStyle(.plain)
            .animatedIcon()
            .frame(width: 46, height: 46)
            .accessibilityLabel(f.state?.isRunning == true ? "Pause" : "Start focus")

            VStack(alignment: .leading, spacing: 1) {
                Text(f.isActive ? (f.kind.isBreak ? "Break" : (f.state?.untilEventTitle.map { "Until “\($0)”" } ?? "Focus")) : "Focus")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if f.isActive {
                    Text(Fmt.clock(f.remaining)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2)
                } else {
                    Button { showPresets.toggle() } label: {
                        HStack(spacing: 3) {
                            Text("\(Prefs.focusMinutes) min")
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(showPresets ? 180 : 0))
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPresets)
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showPresets, arrowEdge: .bottom) { presets }
                }
            }
            if f.isActive {
                HStack(spacing: 6) {
                    Button { f.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(GhostButtonStyle()).animatedIcon().accessibilityLabel("Stop")
                    Button("+5") { f.addFive() }.buttonStyle(GhostButtonStyle())
                }
                .padding(.leading, 4)
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([25, 50, 90], id: \.self) { m in
                Button("\(m) min") { set(m) }
                    .buttonStyle(m == Prefs.focusMinutes ? AnyButtonStyleBox(AccentButtonStyle()) : AnyButtonStyleBox(GhostButtonStyle()))
            }
            HStack(spacing: 6) {
                TextField("custom", text: $custom).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 6).glass(10).frame(width: 74)
                    .onSubmit { if let m = Int(custom), (1...600).contains(m) { set(m) } }
                Text("min").foregroundStyle(Theme.text2)
            }
        }
        .padding(12)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private func set(_ m: Int) {
        UserDefaults.standard.set(m, forKey: Keys.focusMinutes)
        showPresets = false
        f.startFocus(minutes: m)
    }
}

struct RecentsStrip: View {
    var compact = false
    @Query(sort: \Thought.createdAt, order: .reverse) private var all: [Thought]

    var body: some View {
        let recent = Array(all.prefix(10))
        if recent.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(Theme.spark)
                    .symbolEffect(.pulse)
                Text("Your thoughts will appear here · ⌃⌥Space")
            }
            .font(.system(size: 13)).foregroundStyle(Theme.text2)
            .frame(maxWidth: .infinity, minHeight: compact ? 70 : 150)
        } else {
            let colors = Theme.cardIndices(for: recent.map(\.id))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { i, t in
                        ThoughtCard(thought: t, colorIndex: colors[i], sweep: i == 0, compact: compact)
                            .popIn(i)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 6)
                .padding(.trailing, 40)
            }
            .scrollClipDisabled()
            .padding(.vertical, -14)
            .padding(.horizontal, -6)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.02),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .padding(.vertical, -24)
            }
        }
    }
}

struct ThoughtCard: View {
    let thought: Thought
    let colorIndex: Int
    var sweep = false
    var compact = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thought.title)
                .font(.system(size: compact ? 13 : 15, weight: .semibold)).lineLimit(compact ? 2 : 3)
                .foregroundStyle(.white)
            if !thought.preview.isEmpty && !compact {
                Text(thought.preview).font(.system(size: 13)).lineLimit(3)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(Fmt.shortDate(thought.createdAt))
                if thought.isStarred { Image(systemName: "star.fill").symbolEffect(.bounce, value: hover) }
                if !thought.attachments.isEmpty { Image(systemName: "paperclip").symbolEffect(.bounce, value: hover); Text("\(thought.attachments.count)") }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(compact ? 12 : 14)
        .frame(width: compact ? 140 : 178, height: compact ? 96 : 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardGradient(colorIndex)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .borderGlow(radius: 20, colors: Theme.cardGlow(colorIndex), sweep: sweep)
        .scaleEffect(hover ? 1.025 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { LibraryWindowController.shared.show(focus: thought.id) }
        .contextMenu {
            Button(thought.isStarred ? "Unstar" : "Star") { thought.isStarred.toggle(); DataStore.shared.save() }
            Button("Copy") { Clip.copy(thought.text.isEmpty ? thought.title : thought.text) }
            Divider()
            Button("Delete", role: .destructive) { DataStore.shared.delete(thought) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open in library")
    }
}

enum Clip {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct CalendarPane: View {
    @State private var cal = CalendarService.shared
    @State private var f = FocusController.shared
    @State private var c = NotchController.shared
    @State private var hovered: String?
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !cal.hasAccess {
                HStack {
                    Text("Allow calendar access").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button(cal.status == .notDetermined ? "Allow" : "Open Settings") {
                        if cal.status == .notDetermined { Task { await cal.requestAccess() } }
                        else { CalendarService.openPrivacySettings() }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .frame(minHeight: 60)
            } else if cal.events.isEmpty {
                HStack {
                    Text("No meetings today").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button("Focus \(Prefs.focusMinutes)") { f.startFocus(); c.collapse() }
                        .buttonStyle(AccentButtonStyle())
                }
                .frame(minHeight: 60)
            } else {
                focusUntilButton
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(cal.events.enumerated()), id: \.element.id) { i, e in
                            let past = e.end < f.now
                            HStack(spacing: 10) {
                                Circle().fill(e.color).frame(width: 8, height: 8)
                                Text(e.isAllDay ? "All day" : "\(Fmt.time(e.start)) – \(Fmt.time(e.end))")
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
                                    .frame(width: 140, alignment: .leading)
                                Text(e.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .opacity(past ? 0.4 : 1)
                            .modifier(ListSelection(selected: hovered == e.id, namespace: ns, radius: 12))
                            .onHover { if $0 { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovered = e.id } } }
                            .popIn(i)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 170)
                .edgeFade(top: 10, bottom: 24)
            }
        }
        .frame(minHeight: 150, alignment: .top)
        .onAppear { cal.reload() }
    }

    @ViewBuilder private var focusUntilButton: some View {
        if let next = cal.nextMeeting(after: f.now) {
            if let mins = Cycle.minutesUntil(next.start, now: f.now) {
                Button {
                    f.startFocus(untilEvent: (next.title, next.start))
                    c.collapse()
                } label: {
                    Text("Focus until \(Fmt.time(next.start)) · \(mins) min").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle())
            } else {
                Text("Focus until \(Fmt.time(next.start)) · meeting soon")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .glass(999)
            }
        }
    }
}

struct BottomBar: View {
    @State private var c = NotchController.shared
    @State private var f = FocusController.shared

    var body: some View {
        let _ = f.now
        let s = DataStore.shared.todayStats()
        HStack(spacing: 6) {
            if s.focusCount > 0 {
                Text("Today · \(Plural.focuses(s.focusCount)) · \(Fmt.minutes(s.focusSeconds))")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button { c.pinned.toggle() } label: {
                Image(systemName: c.pinned ? "pin.fill" : "pin").foregroundStyle(c.pinned ? .white : Theme.text2)
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(c.pinned ? -20 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: c.pinned)
            }
            .buttonStyle(IconButtonStyle())
            .animatedIcon().help("Keep open").accessibilityLabel("Pin panel")
            Button { LibraryWindowController.shared.show() } label: {
                HStack(spacing: 4) { Text("All"); Image(systemName: "arrow.right") }
            }
            .buttonStyle(GhostButtonStyle())
            .animatedIcon().help("Library ⌃⌥L")
        }
        .font(.system(size: 14))
    }
}

// MARK: - Buttons (one family across the app)

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(Theme.onAccent)
            .background(Capsule().fill(Theme.accent).shadow(color: .white.opacity(0.18), radius: 8))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .contentShape(Capsule())
    }
}

struct AnyButtonStyleBox: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// The sparkle in the input: breathes when empty, bursts when you start typing,
/// twinkles on every keystroke.
struct SparkleIcon: View {
    var text: String
    @State private var breathe = false
    @State private var burst = 0
    @State private var burstStart: Date?
    @State private var tick = 0
    @State private var lastTick = Date.distantPast

    private var hasText: Bool { !text.isEmpty }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.spark.opacity(hasText ? 0.7 : 0.45), .clear], center: .center, startRadius: 0, endRadius: hasText ? 20 : 16))
                .scaleEffect(breathe ? 1.15 : 0.85)
                .opacity(breathe ? 1 : 0.6)
            particles
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: hasText ? [.white, Theme.spark] : [.white.opacity(0.85), Theme.spark.opacity(0.8)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.bounce, value: tick)
                .symbolEffect(.bounce.up, value: burst)
                .rotationEffect(.degrees(hasText ? 90 : 0))
                .scaleEffect(hasText ? 1.12 : 1)
                .shadow(color: Theme.spark.opacity(hasText ? 0.8 : 0.3), radius: hasText ? 6 : 3)
        }
        .frame(width: 28, height: 28)
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: hasText)
        .onAppear {
            guard !Theme.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onChange(of: text) { old, new in
            guard !Theme.reduceMotion else { return }
            if old.isEmpty && !new.isEmpty {
                burst += 1
                burstStart = .now
            } else if new.count > old.count, Date.now.timeIntervalSince(lastTick) > 0.18 {
                tick += 1
                lastTick = .now
            }
        }
        .accessibilityHidden(true)
    }

    /// Eight tiny sparks fly out and fade when typing starts.
    private var particles: some View {
        TimelineView(.animation(paused: burstStart == nil)) { tl in
            let t = burstStart.map { tl.date.timeIntervalSince($0) / 0.7 } ?? 1
            ZStack {
                if t < 1 {
                    ForEach(0..<8, id: \.self) { i in
                        let a = Double(i) / 8 * 2 * .pi + 0.4
                        let ease = 1 - pow(1 - t, 3)
                        Image(systemName: "sparkle")
                            .font(.system(size: i % 2 == 0 ? 6 : 4.5, weight: .bold))
                            .foregroundStyle(i % 3 == 0 ? Color.white : Theme.spark)
                            .offset(x: cos(a) * 20 * ease, y: sin(a) * 20 * ease)
                            .scaleEffect(1 - t * 0.6)
                            .opacity(1 - t)
                    }
                }
            }
            .onChange(of: t >= 1) { _, done in if done { burstStart = nil } }
        }
        .allowsHitTesting(false)
    }
}
