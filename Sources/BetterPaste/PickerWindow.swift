import AppKit
import Carbon
import SwiftUI


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
    case search(SearchEngine)

    var id: String {
        switch self {
        case .saveAs:
            return "save-as"
        case .search(let engine):
            return "search-\(engine.id)"
        }
    }

    var categoryID: String {
        switch self {
        case .saveAs:
            return "save-as"
        case .search:
            return "search"
        }
    }

    var categoryTitle: String {
        switch self {
        case .saveAs:
            return "Save As..."
        case .search:
            return "Search"
        }
    }

    var detailTitle: String? {
        switch self {
        case .saveAs:
            return nil
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
    
    var id: String { rawValue }
    
    func transform(_ text: String) -> String {
        switch self {
        case .none: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titlecase: return text.capitalized
        case .plainText: return text
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
    @ObservedObject var store: ClipboardHistoryStore
    let onPaste: ([ClipboardItem], TextTransformer, ImageTransformer, ActionType?) -> Void
    let onClose: () -> Void

    @State private var selectedID: ClipboardItem.ID?
    @State private var query = ""
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
        guard !query.isEmpty else { return store.visibleItems }
        return store.items.filter { $0.preview.localizedCaseInsensitiveContains(query) || $0.sourceAppName.localizedCaseInsensitiveContains(query) }
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
            .liquidGlassSurface(radius: 18, interactive: true)
            .liquidGlassID("search", in: namespace)

            if filteredItems.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Your clipboard starts here" : "No matching clips", systemImage: "doc.on.clipboard", description: Text(query.isEmpty ? "Copy some text or an image, then open Better Paste." : "Try different words or an app name."))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .liquidGlassSurface(radius: 18)
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
                            Button("Select / Deselect") { selectedID = item.id; toggleSelection() }
                            Button("Save As…") { onPaste([item], .none, .none, .saveAs) }
                            if case .image = item.payload {} else {
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
                    .liquidGlassSurface(radius: 18)
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
                Text(isTransforming || isActioning ? "← → Choose · Esc Back" : "← Actions · → Format")
                Text("↵ Paste")
                Spacer()
                Text(selectionSummary)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .liquidGlassSurface(radius: 14)
            .liquidGlassID("footer", in: namespace)
            }
            .padding(10)
        }
        .clearGlassSurface(radius: 24)
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
        .onChange(of: store.visibleItems) {
            reconcileSelection()
        }
        .background(PickerKeyHandler(onKey: handleKey))
        .frame(width: 440, height: 380)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let code = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            if code == kVK_ANSI_F { searchFocused = true; return true }
            if code == kVK_Delete && !searchFocused { deleteSelected(); return true }
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
            resetMenus()
            moveSelection(code == kVK_DownArrow ? 1 : -1)
            return true
        }
        if searchFocused { return false }
        if code == kVK_Return || code == kVK_ANSI_KeypadEnter { pasteSelected(); return true }
        if code == kVK_Tab { searchFocused = true; return true }
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
            else if isTransforming { cycleTransformer(delta) }
            else if isActioning { cycleAction(delta) }
            else if selectedID != nil {
                isTransforming = delta > 0
                isActioning = delta < 0
                actionType = .saveAs
            }
            return true
        }
        if let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
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
        let isImage = filteredItems.first(where: { $0.id == selectedID }).map { if case .image = $0.payload { return true }; return false } ?? false
        let actions: [ActionType] = isImage ? [.saveAs] : [.saveAs] + SearchEngine.allCases.map(ActionType.search)
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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView


        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !textView.attributedString().isEqual(to: attributedText) {
            textView.textStorage?.setAttributedString(attributedText)
            textView.scrollToBeginningOfDocument(nil)
        }
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
    @Namespace private var rowGlassNamespace

    var isImagePayload: Bool {
        if case .image = item.payload { return true }
        return false
    }

    var body: some View {
        LiquidGlassContainer(spacing: 8) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                    if case .image(let nsImage, _) = item.payload {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if case .richText = item.payload {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .secondary.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .liquidGlassSurface(radius: 8, interactive: true)
                            .liquidGlassID("richtext-icon", in: rowGlassNamespace)
                    } else {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .secondary.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .liquidGlassSurface(radius: 8, interactive: true)
                            .liquidGlassID("text-icon", in: rowGlassNamespace)
                    }
                    
                    if isMultiSelected, let idx = multiSelectIndex {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 14, height: 14)
                            .overlay(Text("\(idx + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                            .offset(x: 10, y: -10)
                    }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        let displayPreview = (isSelected && isTransforming && textTransformer != .none && !isImagePayload) ? textTransformer.transform(item.preview) : item.preview
                        Text(displayPreview.isEmpty ? "Whitespace" : displayPreview)
                            .lineLimit(isSelected ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 8) {
                            Text(item.sourceAppName)
                            Text(item.lastCopiedAt, style: .relative)
                            if item.copyCount > 1 {
                                Text("\(item.copyCount)x")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            
                if isSelected && isActioning {
                    actionMenu
                } else if isSelected && isTransforming {
                    transformMenu
                }
            }
            .padding(.vertical, isActioning || isTransforming ? 8 : 7)
            .padding(.horizontal, 10)
            .liquidGlassSurface(radius: 14, interactive: true)
            .liquidGlassID(isSelected ? "selected-row" : "row", in: rowGlassNamespace)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selectionFill)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selectionStroke, lineWidth: selectionLineWidth)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
    }

    private var selectionFill: Color {
        if isSelected && isMultiSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isMultiSelected {
            return Color.green.opacity(0.12)
        }
        return .clear
    }

    private var selectionStroke: Color {
        if isSelected && isMultiSelected {
            return Color.green.opacity(0.85)
        }
        if isSelected {
            return Color.accentColor.opacity(0.72)
        }
        if isMultiSelected {
            return Color.green.opacity(0.72)
        }
        return Color(nsColor: .separatorColor).opacity(0.28)
    }

    private var selectionLineWidth: CGFloat {
        isSelected || isMultiSelected ? 1.6 : 0.8
    }

    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Actions:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                ForEach(isImagePayload ? ["save-as"] : ["save-as", "search"], id: \.self) { category in
                    let selected = actionType.categoryID == category
                    Text(category == "save-as" ? "Save As..." : "Search")
                        .font(.system(size: 11, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .liquidGlassSurface(radius: 9, interactive: true, tint: selected ? Color.accentColor.opacity(0.30) : nil)
                        .liquidGlassID("action-\(category)", in: rowGlassNamespace)
                        .onTapGesture { actionType = category == "save-as" ? .saveAs : .search(.google) }
                }
            }

            if case .search(let selectedEngine) = actionType {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("With:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            ForEach(SearchEngine.allCases) { engine in
                                let selected = selectedEngine == engine
                                Text(engine.rawValue)
                                    .font(.system(size: 11, weight: selected ? .bold : .medium))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .liquidGlassSurface(radius: 9, interactive: true, tint: selected ? Color.accentColor.opacity(0.30) : nil)
                                    .liquidGlassID("search-\(engine.id)", in: rowGlassNamespace)
                                    .id(engine.id)
                                    .onTapGesture { actionType = .search(engine) }
                            }
                        }
                    }
                    .onChange(of: selectedEngine) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(selectedEngine.id, anchor: .center)
                        }
                    }
                    .onAppear { proxy.scrollTo(selectedEngine.id, anchor: .center) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .padding(.leading, 40)
        .padding(.bottom, 2)
        .animation(.easeInOut(duration: 0.18), value: actionType.id)
    }

    private var transformMenu: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if isImagePayload {
                        ForEach(ImageTransformer.allCases) { t in
                            Text(t.rawValue)
                                .font(.system(size: 11, weight: imageTransformer == t ? .bold : .medium))
                                .foregroundStyle(imageTransformer == t ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .liquidGlassSurface(radius: 9, interactive: true, tint: imageTransformer == t ? Color.accentColor.opacity(0.30) : nil)
                                .liquidGlassID("image-transform-\(t.id)", in: rowGlassNamespace)
                                .id(t.id)
                                .onTapGesture { imageTransformer = t }
                        }
                    } else {
                        ForEach(TextTransformer.allCases) { t in
                            Text(t.rawValue)
                                .font(.system(size: 11, weight: textTransformer == t ? .bold : .medium))
                                .foregroundStyle(textTransformer == t ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .liquidGlassSurface(radius: 9, interactive: true, tint: textTransformer == t ? Color.accentColor.opacity(0.30) : nil)
                                .liquidGlassID("text-transform-\(t.id)", in: rowGlassNamespace)
                                .id(t.id)
                                .onTapGesture { textTransformer = t }
                        }
                    }
                }
            }
            .onChange(of: isImagePayload ? imageTransformer.id : textTransformer.id) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(isImagePayload ? imageTransformer.id : textTransformer.id, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(isImagePayload ? imageTransformer.id : textTransformer.id, anchor: .center)
            }
        }
        .padding(.leading, 40)
        .padding(.bottom, 2)
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
