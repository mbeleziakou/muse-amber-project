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
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Catch a thought", name: .capture)
                KeyboardShortcuts.Recorder("Start / pause focus", name: .focus)
                KeyboardShortcuts.Recorder("Library", name: .library)
            }
            Section("Focus") {
                Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 5...180, step: 5)
                Stepper("Break: \(shortBreak) min", value: $shortBreak, in: 1...30)
                Stepper("Long break: \(longBreak) min", value: $longBreak, in: 5...60, step: 5)
                Stepper("Long break every \(longEvery) sessions", value: $longEvery, in: 2...8)
                Toggle("Auto-start breaks", isOn: $autoBreak)
                Toggle("Sounds", isOn: $sounds)
                Toggle("Timer around the notch", isOn: $timerInWings)
                TextField("Shortcut on start", text: $scStart, prompt: Text("shortcut name"))
                TextField("Shortcut on end", text: $scEnd, prompt: Text("shortcut name"))
            }
            Section("Notch") {
                Picker("Display", selection: $display) {
                    ForEach(DisplayChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Hide in full-screen apps", isOn: $hideFullscreen)
                Toggle("Hide while screen sharing", isOn: $hideOnShare)
                Toggle("Emulate notch", isOn: $emulateNotch)
            }
            Section("Calendars") {
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
                        Text("No access").foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow") {
                            if cal.status == .notDetermined { Task { await cal.requestAccess() } }
                            else { CalendarService.openPrivacySettings() }
                        }
                    }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                HStack {
                    Button("Export all to Markdown…") { exportAll() }
                    if let exportResult { Text(exportResult).foregroundStyle(.secondary) }
                }
                Button("Quit Ostrovok") { NSApp.terminate(nil) }
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
        p.prompt = "Export"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let n = try DataStore.shared.exportAll(to: url)
            exportResult = "Exported \(Plural.thoughts(n))"
        } catch {
            exportResult = "Failed: \(error.localizedDescription)"
        }
    }
}
