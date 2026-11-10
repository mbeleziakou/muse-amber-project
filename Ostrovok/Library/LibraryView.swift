import SwiftUI
import SwiftData
import AppKit

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, starred, focus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .starred: "Starred"
        case .focus: "During focus"
        }
    }
    var icon: String {
        switch self {
        case .all: "tray.full"
        case .starred: "star"
        case .focus: "timer"
        }
    }
}

struct LibraryView: View {
    @Query(sort: \Thought.createdAt, order: .reverse) private var all: [Thought]
    @State private var state = LibraryState.shared
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var pendingDelete: Set<UUID> = []
    @State private var toast: (id: UUID, work: DispatchWorkItem)?
    @State private var addingTo: Thought?
    @State private var composing = false
    @State private var selected: UUID?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Namespace private var ns

    private var visible: [Thought] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { t in
            if pendingDelete.contains(t.id) { return false }
            switch filter {
            case .all: break
            case .starred: if !t.isStarred { return false }
            case .focus: if t.focusSession == nil { return false }
            }
            return q.isEmpty || t.searchText.contains(q)
        }
    }

    private var grouped: [(day: Date, items: [Thought])] {
        let cal = Calendar.current
        var out: [(Date, [Thought])] = []
        for t in visible {
            let d = cal.startOfDay(for: t.createdAt)
            if let last = out.last, last.0 == d { out[out.count - 1].1.append(t) } else { out.append((d, [t])) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if composing {
                            NewThoughtRow { composing = false }.padding(.bottom, 8).popIn(0)
                        }
                        if visible.isEmpty { emptyState }
                        let flat = visible
                        ForEach(grouped, id: \.day) { group in
                            Text(Fmt.dayHeader(group.day))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                                .padding(.top, 18).padding(.bottom, 2).padding(.leading, 4)
                            ForEach(group.items) { t in
                                ThoughtRow(thought: t, query: query,
                                           expanded: state.expandedID == t.id,
                                           onToggle: { toggle(t.id) },
                                           onAdd: { addingTo = t },
                                           onDelete: { delete(t) })
                                    .modifier(ListSelection(selected: selected == t.id, namespace: ns, radius: 16))
                                    .onHover { if $0 { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selected = t.id } } }
                                    .popIn(flat.firstIndex(where: { $0.id == t.id }) ?? 0)
                                    .id(t.id)
                            }
                        }
                    }
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity)
                }
                .scrollClipDisabled()
                .edgeFade(top: 20, bottom: 56)
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, proxy); return .handled }
                .onKeyPress(.upArrow) { move(-1, proxy); return .handled }
                .onKeyPress(.return) { if let s = selected { toggle(s) }; return .handled }
                .onChange(of: state.focusID) { scrollToFocus(proxy) }
                .onAppear { scrollToFocus(proxy) }
            }
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $addingTo) { t in AddNoteSheet(thought: t) }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k", modifiers: .command).hidden()
            Button("") { composing = true }.keyboardShortcut("n", modifiers: .command).hidden()
        }
        .onChange(of: state.newThoughtRequest) { composing = true }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            state.expandedID = state.expandedID == id ? nil : id
            selected = id
        }
    }

    private func move(_ delta: Int, _ proxy: ScrollViewProxy) {
        let items = visible
        guard !items.isEmpty else { return }
        let idx = selected.flatMap { s in items.firstIndex { $0.id == s } } ?? (delta > 0 ? -1 : items.count)
        let next = max(0, min(items.count - 1, idx + delta))
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selected = items[next].id }
        withAnimation { proxy.scrollTo(items[next].id, anchor: .center) }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let id = state.focusID else { return }
        filter = .all
        query = ""
        selected = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            state.focusID = nil
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.text2)
                        .symbolEffect(.bounce, value: searchFocused)
                    TextField("Search", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text2) }
                            .buttonStyle(.plain).animatedIcon().accessibilityLabel("Clear")
                    } else {
                        Text("⌘K").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glass(999, active: searchFocused)
                Button { composing = true } label: { Image(systemName: "plus").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(CircleButtonStyle()).animatedIcon().help("New thought ⌘N").accessibilityLabel("New thought")
                Button { SettingsWindowController.shared.show() } label: { Image(systemName: "gearshape").font(.system(size: 14)) }
                    .buttonStyle(CircleButtonStyle()).animatedIcon(.spin).help("Settings").accessibilityLabel("Settings")
            }
            HStack {
                GooeyNav(items: LibraryFilter.allCases.map { .init(id: $0, label: $0.label, icon: $0.icon) }, selection: $filter)
                Spacer()
            }
        }
        .frame(maxWidth: 700)
        .padding(.top, 34).padding(.horizontal, 24).padding(.bottom, 4)
    }

    @ViewBuilder private var emptyState: some View {
        let (icon, text): (String, String) = {
            if !query.isEmpty { return ("magnifyingglass", "Nothing found") }
            switch filter {
            case .all: return ("sparkle", "Nothing yet. Hover the notch or press ⌃⌥Space")
            case .starred: return ("star", "No starred thoughts")
            case .focus: return ("timer", "No thoughts caught during focus")
            }
        }()
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.text2).symbolEffect(.pulse)
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
        .popIn(0)
    }

    private func delete(_ t: Thought) {
        toast?.work.perform()
        pendingDelete.insert(t.id)
        let id = t.id
        let work = DispatchWorkItem {
            if let t = DataStore.shared.thought(id: id) { DataStore.shared.delete(t) }
            pendingDelete.remove(id)
            if toast?.id == id { withAnimation { toast = nil } }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = (id, work) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 14) {
                Image(systemName: "trash").symbolEffect(.bounce, value: toast.id)
                Text("Thought deleted")
                Button("Undo") {
                    toast.work.cancel()
                    pendingDelete.remove(toast.id)
                    withAnimation { self.toast = nil }
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
            }
            .font(.system(size: 13))
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .glass(999)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .contentShape(Circle())
    }
}

struct ThoughtRow: View {
    @Bindable var thought: Thought
    var query: String
    var expanded: Bool
    var onToggle: () -> Void
    var onAdd: () -> Void
    var onDelete: () -> Void
    @State private var draft = ""
    @State private var saveWork: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(Fmt.time(thought.createdAt))
                if thought.duringFocus {
                    Text("·")
                    Label("during focus", systemImage: "timer").labelStyle(.titleAndIcon).foregroundStyle(Theme.amber.opacity(0.85))
                }
                if !thought.attachments.isEmpty {
                    Text("·")
                    Label("\(thought.attachments.count)", systemImage: "paperclip")
                }
                Spacer()
                if !expanded { actions }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.text2)

            if expanded {
                TextEditor(text: $draft)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 360)
                    .padding(8)
                    .glass(14, active: true)
                    .onAppear { draft = thought.text }
                    .onChange(of: draft) { scheduleSave() }
                    .onDisappear { commit() }
            } else {
                Text(highlight(thought.title))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                if !thought.preview.isEmpty {
                    Text(highlight(thought.preview))
                        .font(.system(size: 15)).foregroundStyle(Theme.text2)
                        .lineLimit(3)
                }
            }

            if !thought.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(thought.attachments.sorted { $0.createdAt < $1.createdAt }) { a in
                            AttachmentThumb(attachment: a, size: expanded ? 120 : 56)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .padding(.bottom, expanded ? 44 : 0)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { onToggle() } }
        .overlay(alignment: .bottomTrailing) {
            if expanded {
                HStack(spacing: 8) {
                    actions
                    Button("Done") { commit(); onToggle() }.buttonStyle(AccentButtonStyle())
                }
                .padding(.bottom, 14).padding(.trailing, 16)
                .transition(.blurFade)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { thought.isStarred.toggle(); DataStore.shared.save() } label: {
                Image(systemName: thought.isStarred ? "star.fill" : "star")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(thought.isStarred ? Theme.amber : Theme.text2)
            }
            .buttonStyle(CircleButtonStyle(size: 28))
            .animatedIcon(trigger: thought.isStarred)
            .accessibilityLabel(thought.isStarred ? "Unstar" : "Star")
            CopyIconButton(text: { thought.text })
            Menu {
                Button("Add a note…", action: onAdd)
                Button("Export .md…") { DataStore.shared.export(thought) }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
                .animatedIcon()
                .accessibilityLabel("More")
        }
        .font(.system(size: 12))
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { commit() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    private func commit() {
        saveWork?.cancel()
        guard draft != thought.text else { return }
        thought.setText(draft)
        DataStore.shared.save()
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return a }
        var search = a.startIndex..<a.endIndex
        while let r = a[search].range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].backgroundColor = Color.white.opacity(0.22)
            a[r].foregroundColor = .white
            search = r.upperBound..<a.endIndex
        }
        return a
    }
}

struct AttachmentThumb: View {
    let attachment: Attachment
    var size: CGFloat
    var body: some View {
        Group {
            if let img = NSImage(contentsOf: attachment.url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").foregroundStyle(Theme.text2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onTapGesture(count: 2) { NSWorkspace.shared.open(attachment.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(attachment.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([attachment.url]) }
        }
    }
}

/// New text thought right in the library.
struct NewThoughtRow: View {
    var onDone: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 90, maxHeight: 260)
                .padding(10)
                .glass(16, active: focused)
            HStack {
                Button("Cancel", action: onDone).buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard !ThoughtText.isBlank(text) else { return }
                    DataStore.shared.addThought(text: text.trimmingCharacters(in: .whitespacesAndNewlines), source: .typed, session: FocusController.shared.currentSession)
                    onDone()
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(ThoughtText.isBlank(text))
            }
        }
        .padding(.top, 16)
        .onAppear { focused = true }
    }
}

/// "Add a note" sheet.
struct AddNoteSheet: View {
    let thought: Thought
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var images: [Data] = []

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Back") { dismiss() }.buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Text("Add a note").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { save() } label: { Label("Done", systemImage: "checkmark") }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text).font(.system(size: 15)).scrollContentBackground(.hidden)
                HStack(alignment: .bottom) {
                    ForEach(Array(images.enumerated()), id: \.offset) { i, d in
                        ZStack(alignment: .topTrailing) {
                            if let img = NSImage(data: d) {
                                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            Button { images.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).padding(5).animatedIcon()
                        }
                        .popIn(i)
                    }
                    Spacer()
                    Button { pickImages() } label: { Image(systemName: "photo.on.rectangle") }
                        .buttonStyle(CircleButtonStyle()).animatedIcon().accessibilityLabel("Add photo")
                }
            }
            .padding(14)
            .glass(18)
        }
        .padding(18)
        .frame(width: 460, height: 420)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onPasteCommand(of: [.image, .png, .tiff]) { providers in
            for p in providers {
                _ = p.loadDataRepresentation(for: .image) { d, _ in
                    if let d { DispatchQueue.main.async { images.append(d) } }
                }
            }
        }
    }

    private var canSave: Bool { !ThoughtText.isBlank(text) || !images.isEmpty }

    private func pickImages() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.image]
        if p.runModal() == .OK {
            for u in p.urls { if let d = try? Data(contentsOf: u) { images.append(d) } }
        }
    }

    private func save() {
        let add = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !add.isEmpty { thought.setText(thought.text.isEmpty ? add : thought.text + "\n\n" + add) }
        if !images.isEmpty { DataStore.shared.addImages(images, to: thought) }
        DataStore.shared.save()
        dismiss()
    }
}
