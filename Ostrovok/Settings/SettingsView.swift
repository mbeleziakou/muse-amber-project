import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    @AppStorage(Keys.focusMinutes) private var focusMinutes = 25
    @AppStorage(Keys.shortBreakMinutes) private var shortBreak = 5
    @AppStorage(Keys.longBreakMinutes) private var longBreak = 15
    @AppStorage(Keys.longBreakEvery) private var longEvery = 4
    @AppStorage(Keys.autoStartBreak) private var autoBreak = false
    @AppStorage(Keys.sounds) private var sounds = true
    @AppStorage(Keys.showTimerInWings) private var timerInWings = true
    @AppStorage(Keys.display) private var display = DisplayChoice.notch.rawValue
    @AppStorage(Keys.hideInFullscreen) private var hideFullscreen = true
    @AppStorage(Keys.hideOnShare) private var hideOnShare = false
    @AppStorage(Keys.emulateNotch) private var emulateNotch = false
    @AppStorage(Keys.shortcutOnStart) private var scStart = ""
    @AppStorage(Keys.shortcutOnEnd) private var scEnd = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var excluded = Prefs.excludedCalendars
    @State private var cal = CalendarService.shared
    @State private var exportResult: String?

    var body: some View {
        Form {
            Section("Хоткеи") {
                KeyboardShortcuts.Recorder("Поймать мысль", name: .capture)
                KeyboardShortcuts.Recorder("Старт / пауза фокуса", name: .focus)
                KeyboardShortcuts.Recorder("Библиотека", name: .library)
            }
            Section("Фокус") {
                Stepper("Фокус: \(focusMinutes) мин", value: $focusMinutes, in: 5...180, step: 5)
                Stepper("Перерыв: \(shortBreak) мин", value: $shortBreak, in: 1...30)
                Stepper("Длинный перерыв: \(longBreak) мин", value: $longBreak, in: 5...60, step: 5)
                Stepper("Длинный каждые \(longEvery) фокуса", value: $longEvery, in: 2...8)
                Toggle("Автостарт перерыва", isOn: $autoBreak)
                Toggle("Звуки", isOn: $sounds)
                Toggle("Таймер в крыльях", isOn: $timerInWings)
                TextField("Shortcut при старте", text: $scStart, prompt: Text("имя команды"))
                TextField("Shortcut при конце", text: $scEnd, prompt: Text("имя команды"))
            }
            Section("Вырез") {
                Picker("Дисплей", selection: $display) {
                    ForEach(DisplayChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Скрывать в полноэкранных приложениях", isOn: $hideFullscreen)
                Toggle("Скрывать при демонстрации экрана", isOn: $hideOnShare)
                Toggle("Эмулировать вырез", isOn: $emulateNotch)
            }
            Section("Календари") {
                if cal.hasAccess {
                    ForEach(cal.allCalendars, id: \.id) { c in
                        Toggle(isOn: Binding(get: { !excluded.contains(c.id) }, set: { on in
                            if on { excluded.remove(c.id) } else { excluded.insert(c.id) }
                            UserDefaults.standard.set(Array(excluded), forKey: Keys.excludedCalendars)
                            cal.reload()
                        })) {
                            HStack { Circle().fill(c.color).frame(width: 8, height: 8); Text(c.title) }
                        }
                    }
                } else {
                    HStack {
                        Text("Нет доступа").foregroundStyle(.secondary)
                        Spacer()
                        Button("Разрешить") {
                            if cal.status == .notDetermined { Task { await cal.requestAccess() } }
                            else { CalendarService.openPrivacySettings() }
                        }
                    }
                }
            }
            Section("Общее") {
                Toggle("Запускать при входе", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                HStack {
                    Button("Экспорт всего в Markdown…") { exportAll() }
                    if let exportResult { Text(exportResult).foregroundStyle(.secondary) }
                }
                Button("Выйти из Островка") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onAppear { cal.reload() }
    }

    private func exportAll() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Экспорт"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let n = try DataStore.shared.exportAll(to: url)
            exportResult = "Готово: \(Plural.thoughts(n))"
        } catch {
            exportResult = "Не получилось: \(error.localizedDescription)"
        }
    }
}
