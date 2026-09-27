import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers


enum ImageTransformer: String, CaseIterable, Identifiable {
    case none = "Original"
    case grayscale = "Black & White"
    var id: String { rawValue }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google = "Google"
    case chatGPT = "ChatGPT"
    case bing = "Bing"
    case duckDuckGo = "DuckDuckGo"

    var id: String { rawValue }
}

enum ActionType: Equatable, Identifiable {
    case saveAs
    case extractText
    case transcodeAudio
    case transcodeVideo
    case rule(UUID)
    case search(SearchEngine)

    var id: String {
        switch self {
        case .saveAs:
            return "save-as"
        case .extractText:
            return "extract-text"
        case .transcodeAudio: return "transcode-audio"
        case .transcodeVideo: return "transcode-video"
        case .rule(let id): return "rule-\(id.uuidString)"
        case .search(let engine):
            return "search-\(engine.id)"
        }
    }

    var categoryID: String {
        switch self {
        case .saveAs:
            return "save-as"
        case .extractText:
            return "extract-text"
        case .transcodeAudio, .transcodeVideo: return "transcode"
        case .rule: return "text-rule"
        case .search:
            return "search"
        }
    }

    var categoryTitle: String {
        switch self {
        case .saveAs:
            return "Save As..."
        case .extractText:
            return "Extract Text"
        case .transcodeAudio, .transcodeVideo: return "Transcode"
        case .rule: return "Text Action"
        case .search:
            return "Search"
        }
    }

    var detailTitle: String? {
        switch self {
        case .saveAs:
            return nil
        case .extractText:
            return nil
        case .transcodeAudio, .transcodeVideo: return nil
        case .rule: return nil
        case .search(let engine):
            return engine.rawValue
        }
    }
}

enum TextTransformer: String, CaseIterable, Identifiable {
    case none = "Original"
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case titlecase = "Title Case"
    case camelCase = "camelCase"
    case snakeCase = "snake_case"
    case kebabCase = "kebab-case"
    case urlEncode = "URL Encode"
    case base64Encode = "Base64"
    case plainText = "Plain Text"
    case markdown = "Markdown"
    case jsonString = "JSON String"
    
    var id: String { rawValue }
    
    func transform(_ text: String) -> String {
        switch self {
        case .none: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titlecase: return text.capitalized
        case .plainText: return text
        case .markdown: return text
        case .jsonString: return ClipboardFormats.jsonString(text)
        case .urlEncode: return ClipboardTransfer.encodeQuery(text)
        case .base64Encode: return text.data(using: .utf8)?.base64EncodedString() ?? text
        case .camelCase, .snakeCase, .kebabCase:
            let words = text.components(separatedBy: CharacterSet.alphanumerics.union(.nonBaseCharacters).inverted).filter { !$0.isEmpty }
            if words.isEmpty { return text }
            switch self {
            case .camelCase:
                let first = words[0].lowercased()
                let rest = words.dropFirst().map { $0.capitalized }
                return first + rest.joined()
            case .snakeCase:
                return words.map { $0.lowercased() }.joined(separator: "_")
            case .kebabCase:
                return words.map { $0.lowercased() }.joined(separator: "-")
            default: return text
            }
        }
    }
}

@MainActor
final class PickerWindowController {
    private let store: ClipboardHistoryStore
    private let pasteController: PasteController
    private var panel: NSPanel?
    private var pasteTargetApp: NSRunningApplication?
    private let bubbleSize = NSSize(width: 440, height: 380)

    init(store: ClipboardHistoryStore, pasteController: PasteController) {
        self.store = store
        self.pasteController = pasteController
    }

    func show() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            pasteTargetApp?.activate()
            return
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pasteTargetApp = frontmost
        }
        NSLog("Better Paste showing picker; target app: \(pasteTargetApp?.localizedName ?? "unknown")")

        if panel == nil {
            let panel = KeyablePanel(
                contentRect: NSRect(origin: .zero, size: bubbleSize),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            self.panel = panel
        }

        let root = PickerView(store: store) { [weak self] items, textTransformer, imageTransformer, action in
            guard let self else { return }
            self.panel?.orderOut(nil)
            if action == nil, let target = self.pasteTargetApp {
                NSApp.yieldActivation(to: target)
            }
            self.pasteController.paste(items, textTransformer: textTransformer, imageTransformer: imageTransformer, action: action, into: self.pasteTargetApp)
        } onClose: { [weak self] in
            self?.panel?.orderOut(nil)
            if let target = self?.pasteTargetApp {
                NSApp.yieldActivation(to: target)
                target.activate()
            }
        }
        panel?.contentView = NSHostingView(rootView: root)
        positionPanelNearCursor()
        NSApp.setActivationPolicy(.accessory)
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        NSApp.activate()
        panel?.makeKey()
    }

    private func positionPanelNearCursor() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        let screenFrame = NSScreen.screens
            .first { $0.frame.contains(mouse) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        let gap: CGFloat = 12
        let edgePadding: CGFloat = 8

        var origin = NSPoint(
            x: mouse.x - size.width / 2,
            y: mouse.y + gap
        )

        if origin.y + size.height > screenFrame.maxY {
            origin.y = mouse.y - size.height - gap
        }

        origin.x = min(max(origin.x, screenFrame.minX + edgePadding), screenFrame.maxX - size.width - edgePadding)
        origin.y = min(max(origin.y, screenFrame.minY + edgePadding), screenFrame.maxY - size.height - edgePadding)

        panel.setFrameOrigin(origin)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PickerView: View {
    private enum ClipFilter: Hashable {
        case recent, pinned, group(String)
    }

    @ObservedObject var store: ClipboardHistoryStore
    let onPaste: ([ClipboardItem], TextTransformer, ImageTransformer, ActionType?) -> Void
    let onClose: () -> Void

    @State private var selectedID: ClipboardItem.ID?
    @State private var query = ""
    @State private var filter: ClipFilter = .recent
    @State private var editingItem: ClipboardItem?
    @FocusState private var searchFocused: Bool
    
    @State private var selectedItemIDs: [ClipboardItem.ID] = []
    @State private var isTransforming: Bool = false
    @State private var textTransformer: TextTransformer = .none
    @State private var imageTransformer: ImageTransformer = .none
    @State private var isActioning: Bool = false
    @State private var actionType: ActionType = .saveAs
    @State private var isQuickLooking: Bool = false
    @Namespace private var namespace

    private var filteredItems: [ClipboardItem] {
        let base: [ClipboardItem]
        switch filter {
        case .recent: base = query.isEmpty ? store.visibleItems : store.items
        case .pinned: base = store.items.filter(\.isPinned)
        case .group(let name): base = store.items.filter { $0.group == name }
        }
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.preview.localizedCaseInsensitiveContains(query)
                || $0.sourceAppName.localizedCaseInsensitiveContains(query)
                || $0.group.localizedCaseInsensitiveContains(query)
                || $0.note.localizedCaseInsensitiveContains(query)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }


    var body: some View {
        LiquidGlassContainer(spacing: 10) {
            VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.9))
                TextField("Search clipboard history", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($searchFocused)
                    .onSubmit { pasteSelected() }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .liquidGlassID("search", in: namespace)

            HStack(spacing: 6) {
                filterButton("Recent", symbol: "clock", value: .recent)
                filterButton("Pinned", symbol: "pin", value: .pinned)
                if !store.groups.isEmpty {
                    Menu {
                        ForEach(store.groups, id: \.self) { group in
                            Button(group) { filter = .group(group) }
                        }
                    } label: {
                        Label(groupTitle, systemImage: "folder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 25)

            if isTransforming || isActioning {
                menuPanel
            } else if filteredItems.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Your clipboard starts here" : "No matching clips", systemImage: "doc.on.clipboard", description: Text(query.isEmpty ? "Copy some text or an image, then open Better Paste." : "Try different words or an app name."))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(filteredItems) { item in
                        let isMulti = selectedItemIDs.contains(item.id)
                        let orderIndex = isMulti ? selectedItemIDs.firstIndex(of: item.id) : nil
                        
                        ClipboardRow(
                            item: item,
                            isSelected: selectedID == item.id,
                            isMultiSelected: isMulti,
                            multiSelectIndex: orderIndex,
                            isTransforming: selectedID == item.id && isTransforming,
                            isActioning: selectedID == item.id && isActioning,
                            textTransformer: $textTransformer,
                            imageTransformer: $imageTransformer,
                            actionType: $actionType
                        )
                        .id(item.id)
                        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                        .onDrop(of: ["public.utf8-plain-text"], isTargeted: nil) { providers in
                            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
                            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                                guard let text = value as? String, let id = UUID(uuidString: text) else { return }
                                Task { @MainActor in store.move(id: id, before: item.id) }
                            }
                            return true
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
                        .onTapGesture(count: 2) {
                            selectedID = item.id
                            pasteSelected()
                        }
                        .onTapGesture {
                            selectedID = item.id
                            searchFocused = false
                        }
                        .contextMenu {
                            Button("Paste") { selectedID = item.id; selectedItemIDs = []; resetMenus(); pasteSelected() }
                            Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(id: item.id) }
                            Button("Edit Clip…") { editingItem = item }
                            if !store.groups.isEmpty {
                                Menu("Move to Group") {
                                    Button("None") { store.setGroup(id: item.id, name: "") }
                                    ForEach(store.groups, id: \.self) { group in
                                        Button(group) { store.setGroup(id: item.id, name: group) }
                                    }
                                }
                            }
                            Button("Select / Deselect") { selectedID = item.id; toggleSelection() }
                            Button("Save As…") { onPaste([item], .none, .none, .saveAs) }
                            if case .image = item.payload {
                                Button("Extract Text and Paste") { onPaste([item], .none, .none, .extractText) }
                            } else if case .file(let url) = item.payload {
                                if let type = UTType(filenameExtension: url.pathExtension) {
                                    if type.conforms(to: .audio) || type.conforms(to: .movie) {
                                        Button("Convert to M4A") { onPaste([item], .none, .none, .transcodeAudio) }
                                    }
                                    if type.conforms(to: .movie) {
                                        Button("Convert to MP4") { onPaste([item], .none, .none, .transcodeVideo) }
                                    }
                                }
                            } else {
                                if !ConfigManager.shared.config.textRules.isEmpty {
                                    Menu("Text Actions") {
                                        ForEach(ConfigManager.shared.config.textRules) { rule in
                                            Button(rule.name) { onPaste([item], .none, .none, .rule(rule.id)) }
                                        }
                                    }
                                }
                                Menu("Search with") {
                                    ForEach(SearchEngine.allCases) { engine in
                                        Button(engine.rawValue) { onPaste([item], .none, .none, .search(engine)) }
                                    }
                                }
                            }
                            Button("Delete", role: .destructive) { store.delete(id: item.id) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: selectedID) {
                        if let selectedID {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(selectedID)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Label("Move", systemImage: "arrow.up.arrow.down")
                Text(isTransforming || isActioning ? "↑ ↓ Choose · Esc Back" : "← Actions · → Format")
                Text("↵ Paste")
                Spacer()
                Text(selectionSummary)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .liquidGlassID("footer", in: namespace)
            }
            .padding(10)
        }
        .liquidGlassSurface(radius: 18)
        .padding(6)
        .clearGlassSurface(radius: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .overlay {
            if isQuickLooking, let selectedID, let item = filteredItems.first(where: { $0.id == selectedID }) {
                QuickLookOverlay(item: item) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isQuickLooking = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onAppear {
            selectedID = filteredItems.first?.id
            searchFocused = true
        }
        .onChange(of: query) {
            reconcileSelection()
        }
        .onChange(of: filter) { reconcileSelection() }
        .onChange(of: store.items) {
            reconcileSelection()
        }
        .background(PickerKeyHandler(onKey: handleKey))
        .sheet(item: $editingItem) { item in
            EditClipSheet(item: item) { text, group, note, tags in
                store.update(id: item.id, text: text, group: group, note: note, tags: tags)
                editingItem = nil
            }
        }
        .frame(width: 440, height: 380)
    }

    private var groupTitle: String {
        if case .group(let name) = filter { return name }
        return "Groups"
    }

    private func filterButton(_ title: String, symbol: String, value: ClipFilter) -> some View {
        Button { filter = value } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: filter == value ? .semibold : .regular))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(filter == value ? Color.accentColor.opacity(0.14) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var menuChoices: [(id: String, title: String, symbol: String)] {
        let payload = filteredItems.first(where: { $0.id == selectedID })?.payload
        let image = payload.map { if case .image = $0 { return true }; return false } ?? false
        let file = payload.map { if case .file = $0 { return true }; return false } ?? false
        if isActioning {
            let extra: [(id: String, title: String, symbol: String)] = file ? [] : image
                ? [("extract-text", "Extract text and paste", "text.viewfinder")]
                : SearchEngine.allCases.map {
                (ActionType.search($0).id, "Search with \($0.rawValue)", "magnifyingglass")
            } + ConfigManager.shared.config.textRules.map {
                (ActionType.rule($0.id).id, $0.name, "text.badge.star")
            }
            return [("save-as", "Save As…", "square.and.arrow.down")] + extra + mediaActions(for: payload)
        }
        if file { return [] }
        return image
            ? ImageTransformer.allCases.map { ($0.id, $0.rawValue, "photo") }
            : TextTransformer.allCases.map { ($0.id, $0.rawValue, "textformat") }
    }

    private func mediaActions(for payload: ClipboardPayload?) -> [(id: String, title: String, symbol: String)] {
        guard let payload, case .file(let url) = payload,
              let type = UTType(filenameExtension: url.pathExtension) else { return [] }
        var actions: [(String, String, String)] = []
        if type.conforms(to: .audio) || type.conforms(to: .movie) {
            actions.append((ActionType.transcodeAudio.id, "Convert to M4A", "waveform"))
        }
        if type.conforms(to: .movie) {
            actions.append((ActionType.transcodeVideo.id, "Convert to MP4", "film"))
        }
        return actions
    }

    private var activeChoice: String {
        if isActioning { return actionType.id }
        if let item = filteredItems.first(where: { $0.id == selectedID }), case .image = item.payload {
            return imageTransformer.id
        }
        return textTransformer.id
    }

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { resetMenus() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .help("Back to clips")
                VStack(alignment: .leading, spacing: 3) {
                    Text(isActioning ? "Actions" : "Paste format")
                        .font(.system(size: 13, weight: .semibold))
                    Text(filteredItems.first(where: { $0.id == selectedID })?.preview ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            Divider().padding(.horizontal, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(menuChoices, id: \.id) { choice in
                            Button {
                                chooseMenuItem(choice.id)
                                pasteSelected()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: choice.symbol)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    Text(choice.title)
                                    Spacer()
                                    if choice.id == activeChoice {
                                        Image(systemName: "return").foregroundStyle(.secondary)
                                    }
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(choice.id == activeChoice ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(choice.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: activeChoice) { proxy.scrollTo(activeChoice) }
                .onAppear { proxy.scrollTo(activeChoice) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseMenuItem(_ id: String) {
        if isActioning {
            actionType = ([ActionType.saveAs, .extractText, .transcodeAudio, .transcodeVideo]
                + SearchEngine.allCases.map(ActionType.search)
                + ConfigManager.shared.config.textRules.map { .rule($0.id) }).first { $0.id == id } ?? .saveAs
        } else {
            if let transform = TextTransformer.allCases.first(where: { $0.id == id }) { textTransformer = transform }
            if let transform = ImageTransformer.allCases.first(where: { $0.id == id }) { imageTransformer = transform }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let code = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            if code == kVK_ANSI_F { resetMenus(); searchFocused = true; return true }
            if code == kVK_Delete && !searchFocused { deleteSelected(); return true }
            if code == kVK_ANSI_P, let selectedID { store.togglePin(id: selectedID); return true }
            if let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit), filteredItems.count >= digit {
                selectedID = filteredItems[digit - 1].id
                selectedItemIDs = []
                resetMenus()
                pasteSelected()
                return true
            }
            return false
        }
        if modifiers.contains(.option) || modifiers.contains(.control) { return false }
        if code == kVK_Escape {
            if isQuickLooking { isQuickLooking = false }
            else if isTransforming || isActioning { resetMenus() }
            else if searchFocused && !query.isEmpty { query = "" }
            else { onClose() }
            return true
        }
        if code == kVK_DownArrow || code == kVK_UpArrow {
            if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
            searchFocused = false
            let delta = code == kVK_DownArrow ? 1 : -1
            if isTransforming { cycleTransformer(delta) }
            else if isActioning { cycleAction(delta) }
            else { moveSelection(delta) }
            return true
        }
        if searchFocused { return false }
        if code == kVK_Return || code == kVK_ANSI_KeypadEnter { pasteSelected(); return true }
        if code == kVK_Tab { resetMenus(); searchFocused = true; return true }
        if code == kVK_Home { selectedID = filteredItems.first?.id; resetMenus(); return true }
        if code == kVK_End { selectedID = filteredItems.last?.id; resetMenus(); return true }
        if code == kVK_Space {
            if modifiers.contains(.shift) { toggleSelection() }
            else if selectedID != nil { isQuickLooking.toggle() }
            return true
        }
        if code == kVK_LeftArrow || code == kVK_RightArrow {
            let delta = code == kVK_RightArrow ? 1 : -1
            if isQuickLooking { moveSelection(delta) }
            else if isTransforming || isActioning { resetMenus() }
            else if selectedID != nil {
                let isFile = filteredItems.first(where: { $0.id == selectedID }).map {
                    if case .file = $0.payload { return true }; return false
                } ?? false
                isTransforming = delta > 0 && !isFile
                isActioning = delta < 0
                actionType = .saveAs
            }
            return true
        }
        if let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
            resetMenus()
            query += characters
            searchFocused = true
            return true
        }
        return false
    }

    private func resetMenus() {
        isTransforming = false
        isActioning = false
        textTransformer = .none
        imageTransformer = .none
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        let index = filteredItems.firstIndex(where: { $0.id == id }) ?? 0
        store.delete(id: id)
        selectedItemIDs.removeAll { $0 == id }
        selectedID = filteredItems.isEmpty ? nil : filteredItems[min(index, filteredItems.count - 1)].id
    }

    private func pasteSelected() {
        let textT = isTransforming ? textTransformer : .none
        let imageT = isTransforming ? imageTransformer : .none
        let action = isActioning ? actionType : nil
        
        if !selectedItemIDs.isEmpty {
            let itemsToPaste = selectedItemIDs.compactMap { id in store.items.first(where: { $0.id == id }) }
            onPaste(itemsToPaste, textT, imageT, action)
        } else if let selectedID, let item = filteredItems.first(where: { $0.id == selectedID }) {
            onPaste([item], textT, imageT, action)
        }
    }

    private func toggleSelection() {
        guard let selectedID else { return }
        if let index = selectedItemIDs.firstIndex(of: selectedID) {
            selectedItemIDs.remove(at: index)
        } else {
            selectedItemIDs.append(selectedID)
        }
    }

    private func cycleAction(_ delta: Int) {
        let payload = filteredItems.first(where: { $0.id == selectedID })?.payload
        let isImage = payload.map { if case .image = $0 { return true }; return false } ?? false
        let isFile = payload.map { if case .file = $0 { return true }; return false } ?? false
        let actions: [ActionType] = isImage ? [.saveAs, .extractText]
            : isFile ? [.saveAs] + mediaActions(for: payload).compactMap { id, _, _ in
                [ActionType.transcodeAudio, .transcodeVideo].first { $0.id == id }
            } : [.saveAs] + SearchEngine.allCases.map(ActionType.search)
                + ConfigManager.shared.config.textRules.map { .rule($0.id) }
        guard let currentIndex = actions.firstIndex(of: actionType) else { return }
        actionType = actions[wrappedIndex(currentIndex + delta, count: actions.count)]
    }

    private func cycleTransformer(_ delta: Int) {
        if let selectedID, let item = filteredItems.first(where: { $0.id == selectedID }), case .image = item.payload {
            let cases = ImageTransformer.allCases
            guard let currentIndex = cases.firstIndex(of: imageTransformer) else { return }
            imageTransformer = cases[wrappedIndex(currentIndex + delta, count: cases.count)]
        } else {
            let cases = TextTransformer.allCases
            guard let currentIndex = cases.firstIndex(of: textTransformer) else { return }
            textTransformer = cases[wrappedIndex(currentIndex + delta, count: cases.count)]
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedID }) ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: filteredItems.count)
        selectedID = filteredItems[nextIndex].id
    }

    private var selectionSummary: String {
        if !selectedItemIDs.isEmpty {
            return "\(selectedItemIDs.count) selected"
        }
        return "\(filteredItems.count) clips"
    }

    private func reconcileSelection() {
        let visibleIDs = Set(filteredItems.map(\.id))
        let existingIDs = Set(store.items.map(\.id))
        selectedItemIDs.removeAll { !existingIDs.contains($0) }
        if selectedID.map(visibleIDs.contains) != true {
            selectedID = filteredItems.first?.id
        }
    }

    private func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}

struct QuickLookOverlay: View {
    let item: ClipboardItem
    let onDismiss: () -> Void

    var isImagePayload: Bool {
        if case .image = item.payload { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .clearGlassSurface(radius: 24)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                HStack {
                    Text(item.sourceAppName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .liquidGlassButton()
                }

                GeometryReader { geo in
                    Group {
                        if case .image(let nsImage, _) = item.payload {
                            ScrollView([.horizontal, .vertical]) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                            }
                            .liquidGlassSurface(radius: 12, interactive: true)
                        } else if case .richText(let attrStr, _) = item.payload {
                            ScrollableTextPreview(attributedText: attrStr)
                                .liquidGlassSurface(radius: 12, interactive: true)
                        } else {
                            ScrollableTextPreview(attributedText: NSAttributedString(
                                string: item.payload.plainText,
                                attributes: [
                                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                                    .foregroundColor: NSColor.labelColor
                                ]
                            ))
                            .liquidGlassSurface(radius: 12, interactive: true)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                }
            }
            .padding(20)
            .liquidGlassSurface(radius: 22)
        }
    }
}

struct ScrollableTextPreview: NSViewRepresentable {
    let attributedText: NSAttributedString

    final class Coordinator {
        var source: NSAttributedString?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func displayText(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: result.length)
        guard range.length > 0 else { return result }

        var fonts: [(NSRange, NSFont)] = []
        result.enumerateAttribute(.font, in: range) { value, segment, _ in
            let sourceFont = value as? NSFont ?? NSFont.systemFont(ofSize: 13)
            let size = min(max(sourceFont.pointSize, 12), 18)
            let font = NSFont(descriptor: sourceFont.fontDescriptor, size: size)
                ?? NSFont.systemFont(ofSize: size)
            fonts.append((segment, font))
        }
        for (segment, font) in fonts {
            result.addAttribute(.font, value: font, range: segment)
        }
        result.removeAttribute(.backgroundColor, range: range)
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        return result
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.displayText(attributedText))
        context.coordinator.source = attributedText

        scrollView.documentView = textView


        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard context.coordinator.source?.isEqual(to: attributedText) != true else { return }
        textView.textStorage?.setAttributedString(Self.displayText(attributedText))
        context.coordinator.source = attributedText
        textView.scrollToBeginningOfDocument(nil)
    }
}

struct EditClipSheet: View {
    let item: ClipboardItem
    let onSave: (String, String, String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var group: String
    @State private var note: String
    @State private var tags: String

    init(item: ClipboardItem, onSave: @escaping (String, String, String, [String]) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.payload.plainText)
        _group = State(initialValue: item.group)
        _note = State(initialValue: item.note)
        _tags = State(initialValue: item.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Clip").font(.system(size: 18, weight: .semibold))
            if case .image = item.payload {} else if case .file = item.payload {} else {
                Text("Text").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            }
            TextField("Group", text: $group)
            TextField("Tags, separated by commas", text: $tags)
            TextField("Note", text: $note)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(text, group, note, tags.components(separatedBy: ","))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .liquidGlassButton()
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 380)
        .liquidGlassSurface(radius: 18)
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isMultiSelected: Bool
    let multiSelectIndex: Int?
    let isTransforming: Bool
    let isActioning: Bool
    @Binding var textTransformer: TextTransformer
    @Binding var imageTransformer: ImageTransformer
    @Binding var actionType: ActionType

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if case .image(let image, _) = item.payload {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if case .file = item.payload {
                    Image(systemName: "doc")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 36)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.preview.isEmpty ? "Whitespace" : item.preview)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.sourceAppName)
                    if !item.group.isEmpty {
                        Text("·")
                        Text(item.group)
                    }
                    Text("·")
                    Text(item.lastCopiedAt, style: .relative)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if isMultiSelected, let index = multiSelectIndex {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
            } else if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(isSelected ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.25) : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

struct PickerKeyHandler: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onKey = onKey
    }

    final class KeyView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      event.window === window else { return event }
                return self.onKey?(event) == true ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
