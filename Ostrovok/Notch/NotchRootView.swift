import SwiftUI
import SwiftData

struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func measure(_ p: Presentation, into c: NotchController) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
            .onPreferenceChange(HeightKey.self) { h in
                guard h > 0, c.measured[p] != h else { return }
                if c.measured[p] == nil { c.measured[p] = h } else { withAnimation(Theme.morph) { c.measured[p] = h } }
            }
    }
}

struct NotchRootView: View {
    @State private var c = NotchController.shared

    var body: some View {
        let f = c.frame
        let shape = NotchShape(width: f.width, height: f.height, radius: f.radius, ear: f.ear)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .opacity(c.presentation == .idle && !c.geometry.hasHardwareNotch ? 0 : 1)
                .shadow(color: .black.opacity(c.isInteractive ? 0.35 : 0), radius: 18, y: 8)
            content
                .frame(width: f.width)
                .frame(maxWidth: .infinity, alignment: .top)
                .mask(shape)
        }
        .overlay(alignment: .top) {
            if c.mode == .idle || c.mode == .breakPrompt || c.mode == .peek {
                Color.clear
                    .frame(width: f.width + 2 * f.ear, height: c.geometry.notchSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture { tapped() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Открыть Островок")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    private func tapped() {
        switch c.mode {
        case .breakPrompt: c.startBreakFromCard()
        case .idle, .peek: c.open(.expanded)
        default: break
        }
    }

    @ViewBuilder private var content: some View {
        let n = c.geometry.notchSize
        switch c.presentation {
        case .idle:
            Color.clear.frame(height: n.height)
        case .timer:
            TimerWings(notch: n).transition(.blurFade)
        case .saved:
            Wings(notch: n) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").foregroundStyle(Theme.success)
                    Text("Сохранено").foregroundStyle(.white)
                }
                .font(.system(size: 13, weight: .semibold))
            } right: {
                Text("⌘Z — отменить").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            .transition(.blurFade)
        case .breakPrompt:
            Wings(notch: n) {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(Theme.mint)
            } right: {
                Text("Перерыв?").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .transition(.blurFade)
        case .meeting:
            Wings(notch: n) {
                Image(systemName: "calendar").foregroundStyle(Theme.lime)
            } right: {
                Text("Встреча через 2 мин").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .transition(.blurFade)
        case .peek:
            VStack(spacing: 0) {
                Color.clear.frame(height: n.height)
                CaptureField(compact: true)
                    .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 6)
            }
            .measure(.peek, into: c)
            .transition(.blurFade)
        case .expanded:
            VStack(spacing: 0) {
                ExpandedHeader(notch: n)
                ExpandedPanel()
            }
            .measure(.expanded, into: c)
            .transition(.blurFade)
        case .focusDone, .breakDone:
            VStack(spacing: 0) {
                Color.clear.frame(height: n.height)
                FinishedCard(isFocus: c.presentation == .focusDone)
                    .padding(.horizontal, 18).padding(.bottom, 16).padding(.top, 8)
            }
            .measure(c.presentation, into: c)
            .transition(.blurFade)
        }
    }
}

/// Контент только слева и справа от камеры.
struct Wings<L: View, R: View>: View {
    var notch: CGSize
    @ViewBuilder var left: L
    @ViewBuilder var right: R
    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            Color.clear.frame(width: notch.width)
            right.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
        }
        .frame(height: notch.height)
    }
}

struct TimerWings: View {
    var notch: CGSize
    @State private var f = FocusController.shared
    var body: some View {
        let tint = f.kind.isBreak ? Theme.mint : Theme.amber
        VStack(spacing: 0) {
            Wings(notch: notch) {
                ProgressRing(progress: f.progress, tint: tint, lineWidth: 2.6)
                    .frame(width: 15, height: 15)
                    .opacity(f.state?.isPaused == true ? 0.5 : 1)
            } right: {
                Text(Fmt.clock(f.remaining))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(f.state?.isPaused == true ? Theme.text2 : .white)
                    .contentTransition(.numericText(countsDown: true))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint).frame(width: g.size.width * f.progress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(f.kind.isBreak ? "Перерыв" : "Фокус"), осталось \(Fmt.clock(f.remaining))")
    }
}

struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 3
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
        }
    }
}

/// Шапка S3: таймер остаётся в крыльях, если идёт.
struct ExpandedHeader: View {
    var notch: CGSize
    @State private var f = FocusController.shared
    var body: some View {
        if f.isActive {
            Wings(notch: notch) {
                ProgressRing(progress: f.progress, tint: f.kind.isBreak ? Theme.mint : Theme.amber, lineWidth: 2.6)
                    .frame(width: 15, height: 15)
            } right: {
                Text(Fmt.clock(f.remaining)).font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        } else {
            Color.clear.frame(height: notch.height)
        }
    }
}

struct FinishedCard: View {
    var isFocus: Bool
    @State private var c = NotchController.shared
    @State private var f = FocusController.shared

    var body: some View {
        let stats = DataStore.shared.todayStats()
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if isFocus {
                    Text("Фокус \(Int((Double(f.finished?.plannedSeconds ?? Prefs.focusMinutes * 60) / 60).rounded())) мин готов")
                        .font(.system(size: 15, weight: .semibold))
                    let sub = subtitle(stats)
                    if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(Theme.text2) }
                } else {
                    Text("Перерыв окончен").font(.system(size: 15, weight: .semibold))
                }
            }
            Spacer(minLength: 8)
            if isFocus {
                Button("Перерыв \(nextBreakMinutes)") { c.startBreakFromCard() }
                    .buttonStyle(PillButtonStyle())
            }
            Button("\(isFocus ? "Ещё" : "Фокус") \(Prefs.focusMinutes)") { c.startFocusFromCard() }
                .buttonStyle(PillButtonStyle(fill: Theme.lime, fg: Theme.onLime))
        }
        .foregroundStyle(.white)
    }

    private var nextBreakMinutes: Int {
        let count = UserDefaults.standard.integer(forKey: Keys.cycleCount)
        return Cycle.nextBreak(completedFocusInCycle: count, longEvery: Prefs.longBreakEvery) == .longBreak ? Prefs.longBreakMinutes : Prefs.shortBreakMinutes
    }

    private func subtitle(_ s: DataStore.DayStats) -> String {
        var parts: [String] = []
        if s.focusCount > 0 { parts.append("\(s.focusCount)-я сессия сегодня") }
        if let fin = f.finished, let session = DataStore.shared.session(id: fin.sessionID), !session.thoughts.isEmpty {
            parts.append(Plural.thoughts(session.thoughts.count) + " " + (session.thoughts.count == 1 ? "поймана" : "поймано"))
        }
        return parts.joined(separator: " · ")
    }
}

enum Plural {
    static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        let w = (m10 == 1 && m100 != 11) ? one : ((2...4).contains(m10) && !(12...14).contains(m100)) ? few : many
        return "\(n) \(w)"
    }
    static func thoughts(_ n: Int) -> String { ru(n, "мысль", "мысли", "мыслей") }
    static func focuses(_ n: Int) -> String { ru(n, "фокус", "фокуса", "фокусов") }
}
