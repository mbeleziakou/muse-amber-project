import SwiftUI
import SwiftData
import AppKit

/// Поле «✦ Поймай мысль…» — общее для S2 и S3.
struct CaptureField: View {
    var compact: Bool
    @State private var c = NotchController.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.spark)
                    .padding(.bottom, 3)
                TextField("Поймай мысль…", text: $c.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: compact ? 15 : 16))
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            c.draft += "\n"
                            return .handled
                        }
                        c.submit()
                        return .handled
                    }
                    .accessibilityLabel("Мысль")
                Button { c.submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canSend ? Theme.onLime : Theme.text2)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(canSend ? Theme.lime : Theme.surface2))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Сохранить")
            }
            if !c.draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(c.draftImages.enumerated()), id: \.offset) { i, data in
                            ZStack(alignment: .topTrailing) {
                                if let img = NSImage(data: data) {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Button { c.draftImages.remove(at: i) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                        .frame(width: 16, height: 16).background(Circle().fill(.black.opacity(0.7)))
                                }
                                .buttonStyle(.plain).offset(x: 4, y: -4)
                                .accessibilityLabel("Убрать картинку")
                            }
                        }
                    }
                    .padding(.top, 4).padding(.trailing, 6)
                }
                .padding(.leading, 25)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.field))
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
    @State private var f = FocusController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                FocusRow()
                Spacer()
                Button {
                    withAnimation(Theme.morph) { c.tab = c.tab == .calendar ? .recents : .calendar }
                    if c.tab == .calendar { Task { await CalendarService.shared.requestAccess() } }
                } label: {
                    Text("Календарь")
                }
                .buttonStyle(PillButtonStyle(fill: c.tab == .calendar ? Theme.surface : Theme.lime,
                                             fg: c.tab == .calendar ? Theme.lime : Theme.onLime))
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
        .padding(.bottom, 18)
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(f.kind.isBreak && f.isActive ? Theme.mint : Theme.amber))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(f.state?.isRunning == true ? "Пауза" : "Старт фокуса")

            VStack(alignment: .leading, spacing: 1) {
                Text(f.isActive ? (f.kind.isBreak ? "Перерыв" : (f.state?.untilEventTitle.map { "До «\($0)»" } ?? "Фокус")) : "Фокус")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if f.isActive {
                    Text(Fmt.clock(f.remaining)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2)
                } else {
                    Button { showPresets.toggle() } label: {
                        HStack(spacing: 3) {
                            Text("\(Prefs.focusMinutes) мин")
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
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
                        .buttonStyle(PillButtonStyle()).accessibilityLabel("Стоп")
                    Button("+5") { f.addFive() }.buttonStyle(PillButtonStyle())
                }
                .padding(.leading, 6)
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([25, 50, 90], id: \.self) { m in
                Button("\(m) мин") { set(m) }.buttonStyle(PillButtonStyle(fill: m == Prefs.focusMinutes ? Theme.surface2 : Theme.surface))
            }
            HStack(spacing: 6) {
                TextField("своё", text: $custom).textFieldStyle(.roundedBorder).frame(width: 60)
                    .onSubmit { if let m = Int(custom), (1...600).contains(m) { set(m) } }
                Text("мин").foregroundStyle(Theme.text2)
            }
        }
        .padding(12)
    }

    private func set(_ m: Int) {
        UserDefaults.standard.set(m, forKey: Keys.focusMinutes)
        showPresets = false
        f.startFocus(minutes: m)
    }
}

struct RecentsStrip: View {
    @Query(sort: \Thought.createdAt, order: .reverse) private var all: [Thought]
    @State private var c = NotchController.shared

    var body: some View {
        let recent = Array(all.prefix(10))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Недавние").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                Spacer()
                Button { LibraryWindowController.shared.show() } label: {
                    HStack(spacing: 4) { Text("Все"); Image(systemName: "arrow.right") }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                }
                .buttonStyle(.plain)
            }
            if recent.isEmpty {
                Text("Здесь появятся твои мысли · ⌃⌥Space")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let colors = Theme.cardIndices(for: recent.map(\.id))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { i, t in
                            ThoughtCard(thought: t, colorIndex: colors[i])
                        }
                    }
                    .padding(.trailing, 40)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}

struct ThoughtCard: View {
    let thought: Thought
    let colorIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thought.title)
                .font(.system(size: 15, weight: .semibold)).lineLimit(3)
                .foregroundStyle(.white)
            if !thought.preview.isEmpty {
                Text(thought.preview).font(.system(size: 13)).lineLimit(3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(Fmt.shortDate(thought.createdAt))
                if thought.isStarred { Image(systemName: "star.fill") }
                if !thought.attachments.isEmpty { Image(systemName: "paperclip"); Text("\(thought.attachments.count)") }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(14)
        .frame(width: 178, height: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardGradient(colorIndex)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { LibraryWindowController.shared.show(focus: thought.id) }
        .contextMenu {
            Button(thought.isStarred ? "Убрать из избранного" : "В избранное") { thought.isStarred.toggle(); DataStore.shared.save() }
            Button("Копировать") { Clip.copy(thought.text.isEmpty ? thought.title : thought.text) }
            Divider()
            Button("Удалить", role: .destructive) { DataStore.shared.delete(thought) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть в библиотеке")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !cal.hasAccess {
                HStack {
                    Text("Разреши доступ к календарю").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button(cal.status == .notDetermined ? "Разрешить" : "Настройки") {
                        if cal.status == .notDetermined { Task { await cal.requestAccess() } }
                        else { CalendarService.openPrivacySettings() }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .frame(minHeight: 60)
            } else if cal.events.isEmpty {
                HStack {
                    Text("Сегодня встреч нет").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button("Фокус \(Prefs.focusMinutes)") { f.startFocus(); c.collapse() }
                        .buttonStyle(PillButtonStyle(fill: Theme.lime, fg: Theme.onLime))
                }
                .frame(minHeight: 60)
            } else {
                focusUntilButton
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cal.events) { e in
                            let past = e.end < f.now
                            HStack(spacing: 10) {
                                Circle().fill(e.color).frame(width: 8, height: 8)
                                Text(e.isAllDay ? "весь день" : "\(Fmt.time(e.start))–\(Fmt.time(e.end))")
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
                                    .frame(width: 96, alignment: .leading)
                                Text(e.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Spacer()
                            }
                            .opacity(past ? 0.4 : 1)
                        }
                    }
                }
                .frame(maxHeight: 160)
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
                    Text("Фокус до \(Fmt.time(next.start)) · \(mins) мин")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(fill: Theme.lime, fg: Theme.onLime))
            } else {
                Text("Фокус до \(Fmt.time(next.start)) · скоро встреча")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.surface))
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
        HStack {
            if s.focusCount > 0 {
                Text("Сегодня · \(Plural.focuses(s.focusCount)) · \(Fmt.minutes(s.focusSeconds))")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button { c.pinned.toggle() } label: {
                Image(systemName: c.pinned ? "pin.fill" : "pin").foregroundStyle(c.pinned ? Theme.amber : Theme.text2)
            }
            .buttonStyle(IconButtonStyle()).help("Закрепить").accessibilityLabel("Закрепить панель")
            Button { LibraryWindowController.shared.show() } label: {
                Image(systemName: "macwindow").foregroundStyle(Theme.text2)
            }
            .buttonStyle(IconButtonStyle()).help("Библиотека ⌃⌥L").accessibilityLabel("Открыть библиотеку")
        }
        .font(.system(size: 14))
    }
}
