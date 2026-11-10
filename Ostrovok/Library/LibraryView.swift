import SwiftUI
import SwiftData
import AppKit

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, starred, focus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Все"
        case .starred: "Избранное"
        case .focus: "Во время фокуса"
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
    @FocusState private var searchFocused: Bool

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
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        if composing {
                            NewThoughtRow { composing = false }.padding(.bottom, 12)
                        }
                        if visible.isEmpty { emptyState }
                        ForEach(grouped, id: \.day) { group in
                            Text(Fmt.dayHeader(group.day))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                                .padding(.top, 22).padding(.bottom, 6)
                            ForEach(group.items) { t in
                                ThoughtRow(thought: t, query: query,
                                           expanded: state.expandedID == t.id,
                                           onToggle: { withAnimation(.easeOut(duration: 0.18)) { state.expandedID = state.expandedID == t.id ? nil : t.id } },
                                           onAdd: { addingTo = t },
                                           onDelete: { delete(t) })
                                    .id(t.id)
                                Divider().overlay(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity)
                }
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

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let id = state.focusID else { return }
        filter = .all
        query = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            state.focusID = nil
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.text2)
                    TextField("Поиск", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text2) }
                            .buttonStyle(.plain).accessibilityLabel("Очистить")
                    } else {
                        Text("⌘K").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.surface))
                Button { composing = true } label: { Image(systemName: "plus").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(CircleButtonStyle()).help("Новая мысль ⌘N").accessibilityLabel("Новая мысль")
                Button { SettingsWindowController.shared.show() } label: { Image(systemName: "gearshape").font(.system(size: 14)) }
                    .buttonStyle(CircleButtonStyle()).help("Настройки").accessibilityLabel("Настройки")
            }
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in
                    Button(f.label) { filter = f }
                        .buttonStyle(PillButtonStyle(fill: filter == f ? .white : Theme.surface, fg: filter == f ? .black : Theme.text2))
                }
                Spacer()
            }
        }
        .frame(maxWidth: 700)
        .padding(.top, 34).padding(.horizontal, 24).padding(.bottom, 4)
    }

    @ViewBuilder private var emptyState: some View {
        let text: String = {
            if !query.isEmpty { return "Ничего не найдено" }
            switch filter {
            case .all: return "Пока пусто. Наведи на вырез или нажми ⌃⌥Space"
            case .starred: return "Нет избранного"
            case .focus: return "Нет мыслей, пойманных во время фокуса"
            }
        }()
        Text(text).font(.system(size: 14)).foregroundStyle(Theme.text2)
            .frame(maxWidth: .infinity).padding(.top, 80)
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
        withAnimation { toast = (id, work) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 14) {
                Text("Мысль удалена")
                Button("Отменить") {
                    toast.work.cancel()
                    pendingDelete.remove(toast.id)
                    withAnimation { self.toast = nil }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.lime).fontWeight(.semibold)
                .keyboardShortcut("z", modifiers: .command)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(Capsule().fill(Theme.surface2))
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
            .background(Circle().fill(Theme.surface))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.6 : 1)
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
                    Label("во время фокуса", systemImage: "timer").labelStyle(.titleAndIcon).foregroundStyle(Theme.amber.opacity(0.8))
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
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
        .padding(.vertical, 14)
        .padding(.bottom, expanded ? 44 : 0)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { onToggle() } }
        .overlay(alignment: .bottomTrailing) {
            if expanded {
                HStack(spacing: 8) {
                    actions
                    Button("Готово") { commit(); onToggle() }
                        .buttonStyle(PillButtonStyle(fill: Theme.lime, fg: Theme.onLime))
                }
                .padding(.bottom, 14)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { thought.isStarred.toggle(); DataStore.shared.save() } label: {
                Image(systemName: thought.isStarred ? "star.fill" : "star")
                    .foregroundStyle(thought.isStarred ? Theme.amber : Theme.text2)
            }
            .buttonStyle(CircleButtonStyle(size: 28)).accessibilityLabel(thought.isStarred ? "Убрать из избранного" : "В избранное")
            Button { Clip.copy(thought.text) } label: { Image(systemName: "doc.on.doc").foregroundStyle(Theme.text2) }
                .buttonStyle(CircleButtonStyle(size: 28)).help("Копировать").accessibilityLabel("Копировать")
            Menu {
                Button("Дописать…", action: onAdd)
                Button("Экспорт .md…") { DataStore.shared.export(thought) }
                Divider()
                Button("Удалить", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28).background(Circle().fill(Theme.surface))
                .accessibilityLabel("Ещё")
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
            a[r].backgroundColor = Theme.amber.opacity(0.35)
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) { NSWorkspace.shared.open(attachment.url) }
        .contextMenu {
            Button("Открыть") { NSWorkspace.shared.open(attachment.url) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([attachment.url]) }
        }
    }
}

/// Новая текстовая мысль прямо в библиотеке.
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
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
            HStack {
                Button("Отмена", action: onDone).buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    guard !ThoughtText.isBlank(text) else { return }
                    DataStore.shared.addThought(text: text.trimmingCharacters(in: .whitespacesAndNewlines), source: .typed, session: FocusController.shared.currentSession)
                    onDone()
                }
                .buttonStyle(PillButtonStyle(fill: Theme.lime, fg: Theme.onLime))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(ThoughtText.isBlank(text))
            }
        }
        .padding(.top, 16)
        .onAppear { focused = true }
    }
}

/// «Дописать» — как модалка Add a note из референса.
struct AddNoteSheet: View {
    let thought: Thought
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var images: [Data] = []

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Назад") { dismiss() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Text("Дописать").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { save() } label: { Label("Готово", systemImage: "checkmark") }
                    .buttonStyle(PillButtonStyle(fill: canSave ? Theme.lime : Theme.surface, fg: canSave ? Theme.onLime : Theme.text2))
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
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { images.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).padding(5)
                        }
                    }
                    Spacer()
                    Button { pickImages() } label: { Image(systemName: "photo.on.rectangle") }
                        .buttonStyle(CircleButtonStyle()).accessibilityLabel("Добавить фото")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.field))
        }
        .padding(18)
        .frame(width: 460, height: 420)
        .background(Color.black)
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
