import AppKit
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
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case .base64Encode: return text.data(using: .utf8)?.base64EncodedString() ?? text
        case .camelCase, .snakeCase, .kebabCase:
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
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
        pasteTargetApp = NSWorkspace.shared.frontmostApplication
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
            if let target = self.pasteTargetApp {
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
        let visible = store.visibleItems
        guard !query.isEmpty else { return visible }
        return visible.filter { $0.preview.localizedCaseInsensitiveContains(query) || $0.sourceAppName.localizedCaseInsensitiveContains(query) }
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
                ContentUnavailableView("No Clipboard Items", systemImage: "doc.on.clipboard")
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
                            textTransformer: textTransformer,
                            imageTransformer: imageTransformer,
                            actionType: actionType
                        )
                        .id(item.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
                        .onTapGesture {
                            selectedID = item.id
                            pasteSelected()
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .liquidGlassSurface(radius: 18)
                    .onChange(of: selectedID) {
                        if let selectedID {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Label("Move", systemImage: "arrow.up.arrow.down")
                Label("Actions", systemImage: "arrow.left.arrow.right")
                Label("Preview", systemImage: "space")
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
        .focusable()
        .onKeyPress { keyPress in
            if keyPress.key == .space {
                if isQuickLooking {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isQuickLooking = false
                    }
                } else if keyPress.modifiers.contains(.shift) {
                    toggleSelection()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isQuickLooking = true
                    }
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if isQuickLooking {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isQuickLooking = false
                }
                return .handled
            }
            if isTransforming || isActioning {
                isTransforming = false
                isActioning = false
                return .handled
            }
            onClose()
            return .handled
        }
        .onKeyPress(.return) {
            if isQuickLooking {
                withAnimation(.easeInOut(duration: 0.15)) { isQuickLooking = false }
            }
            pasteSelected()
            return .handled
        }
        .onKeyPress(.delete) {
            if isQuickLooking { return .ignored }
            if let id = selectedID {
                store.delete(id: id)
                selectedItemIDs.removeAll { $0 == id }
                selectedID = filteredItems.first?.id
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if isQuickLooking {
                moveSelection(1)
                return .handled
            }
            if isTransforming {
                cycleTransformer(1)
            } else if isActioning {
                cycleAction(1)
            } else {
                isTransforming = true
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if isQuickLooking {
                moveSelection(-1)
                return .handled
            }
            if isTransforming {
                cycleTransformer(-1)
            } else if isActioning {
                cycleAction(-1)
            } else {
                actionType = .saveAs
                isActioning = true
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "l")) { _ in
            guard query.isEmpty else { return .ignored }
            if isQuickLooking {
                moveSelection(1)
                return .handled
            }
            if isTransforming {
                cycleTransformer(1)
            } else if isActioning {
                cycleAction(1)
            } else {
                isTransforming = true
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "h")) { _ in
            guard query.isEmpty else { return .ignored }
            if isQuickLooking {
                moveSelection(-1)
                return .handled
            }
            if isTransforming {
                cycleTransformer(-1)
            } else if isActioning {
                cycleAction(-1)
            } else {
                actionType = .saveAs
                isActioning = true
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isQuickLooking {
                moveSelection(1)
                return .handled
            }
            if isTransforming || isActioning { isTransforming = false; isActioning = false }
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isQuickLooking {
                moveSelection(-1)
                return .handled
            }
            if isTransforming || isActioning { isTransforming = false; isActioning = false }
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "j")) { _ in
            guard query.isEmpty else { return .ignored }
            if isQuickLooking {
                moveSelection(1)
                return .handled
            }
            if isTransforming || isActioning { isTransforming = false; isActioning = false }
            moveSelection(1)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "k")) { _ in
            guard query.isEmpty else { return .ignored }
            if isQuickLooking {
                moveSelection(-1)
                return .handled
            }
            if isTransforming || isActioning { isTransforming = false; isActioning = false }
            moveSelection(-1)
            return .handled
        }
        .frame(width: 440, height: 380)
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
        let actions: [ActionType] = [.saveAs] + SearchEngine.allCases.map(ActionType.search)
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
        if selectedItemIDs.count > 1 {
            return "\(selectedItemIDs.count) selected"
        }
        return "\(filteredItems.count) clips"
    }

    private func reconcileSelection() {
        let visibleIDs = Set(filteredItems.map(\.id))
        selectedItemIDs.removeAll { !visibleIDs.contains($0) }
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

        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !textView.attributedString().isEqual(to: attributedText) {
            textView.textStorage?.setAttributedString(attributedText)
            textView.scrollToBeginningOfDocument(nil)
        }
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
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
    let textTransformer: TextTransformer
    let imageTransformer: ImageTransformer
    let actionType: ActionType
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
                ForEach(["save-as", "search"], id: \.self) { category in
                    let selected = actionType.categoryID == category
                    Text(category == "save-as" ? "Save As..." : "Search")
                        .font(.system(size: 11, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .liquidGlassSurface(radius: 9, interactive: true, tint: selected ? Color.accentColor.opacity(0.30) : nil)
                        .liquidGlassID("action-\(category)", in: rowGlassNamespace)
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
