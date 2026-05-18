import SwiftUI

// MARK: - Design tokens

private extension Color {
    static let ink        = Color.primary
    static let faint      = Color.primary.opacity(0.045)
    static let subtle     = Color.primary.opacity(0.09)
    static let muted      = Color.secondary.opacity(0.5)
    static let surface    = Color(NSColor.windowBackgroundColor)
    static let lifted     = Color(NSColor.controlBackgroundColor)
    static let appGreen   = Color(red: 0.18, green: 0.78, blue: 0.44)
    /// Background tint applied to search-match runs.
    static let searchHighlight = Color.yellow.opacity(0.38)
}

private let W: CGFloat = 400
private let H: CGFloat = 540

// MARK: - Tab

private enum Tab: String, CaseIterable {
    case clips    = "Clips"
    case snippets = "Snippets"
}

// MARK: - Root view

struct ClipboardView: View {
    @ObservedObject private var mgr = ClipboardManager.shared
    @State private var copiedID:   UUID?
    @State private var addText     = ""
    @State private var showAdd     = false
    @State private var selectedID: UUID?
    @State private var activeTab:  Tab = .clips

    @FocusState private var searchFocused: Bool
    @FocusState private var addFocused:    Bool

    private var items:  [ClipItem] { mgr.visibleItems }
    private var pinned: [ClipItem] { items.filter(\.isPinned) }
    private var recent: [ClipItem] { items.filter { !$0.isPinned } }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar

            ZStack {
                VStack(spacing: 0) {
                    searchBar
                    if showAdd { addBar.transition(.move(edge: .top).combined(with: .opacity)) }
                    clipList
                }
                .opacity(activeTab == .clips ? 1 : 0)
                .allowsHitTesting(activeTab == .clips)

                SnippetManagerView()
                    .opacity(activeTab == .snippets ? 1 : 0)
                    .allowsHitTesting(activeTab == .snippets)
            }
            .animation(.easeInOut(duration: 0.15), value: activeTab)

            footer
        }
        .frame(width: W, height: H)
        .background(Color.surface)
        .onKeyPress(keys: [.tab]) { _ in
            guard !searchFocused && !addFocused else { return .ignored }
            searchFocused = true
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !searchFocused && !addFocused else { return .ignored }
            move(-1); return .handled
        }
        .onKeyPress(.downArrow) {
            guard !searchFocused && !addFocused else { return .ignored }
            move(1); return .handled
        }
        .onKeyPress(.return) {
            guard !searchFocused && !addFocused else { return .ignored }
            confirmSelection(); return .handled
        }
        .onKeyPress(.escape) {
            clearOrDeselect(); return .handled
        }
        // Clear stale selection whenever the item list changes (search results
        // shift, items are deleted, etc.) — prevents selectedID pointing at
        // an item that is no longer visible.
        .onChange(of: mgr.visibleItems) { _, newItems in
            if let id = selectedID, !newItems.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }
        // Reset transient UI whenever the popover closes so stale badges and
        // keyboard selection don't persist when the popover reopens.
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            copiedID   = nil
            selectedID = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "clipboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.appGreen)
            Text("Clipboard")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            Text("\(mgr.items.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.muted)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.subtle)
                .clipShape(Capsule())
            Divider().frame(height: 14).padding(.horizontal, 4)
            if activeTab == .clips {
                TinyBtn(icon: "plus", tooltip: "Add item") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        showAdd.toggle()
                    }
                    addFocused = showAdd
                }
            }
            Menu {
                Button("Clear recents") { withAnimation { mgr.clearAll() } }
                Divider()
                Button("Quit ClipboardApp") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let isActive = activeTab == tab
                HStack(spacing: 5) {
                    Image(systemName: tab == .clips ? "doc.on.clipboard" : "bolt.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isActive ? .appGreen : .muted)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Rectangle().fill(isActive ? Color.appGreen.opacity(0.08) : Color.clear))
                .overlay(
                    Rectangle()
                        .fill(isActive ? Color.appGreen : Color.clear)
                        .frame(height: 2)
                        .padding(.horizontal, 40),
                    alignment: .bottom
                )
                .scaleEffect(isActive ? 1.02 : 1.0)
                .animation(.spring(response: 0.3), value: activeTab)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activeTab = tab
                    }
                }
            }
        }
        .overlay(Rectangle().fill(Color.subtle).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(searchFocused ? .appGreen : .muted)
                .animation(.easeOut(duration: 0.15), value: searchFocused)
            TextField("Search clips…", text: $mgr.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .onKeyPress(.downArrow)  { move(1);  return .handled }
                .onKeyPress(.upArrow)    { move(-1); return .handled }
                .onKeyPress(.return) {
                    if selectedID != nil { confirmSelection() }
                    else if let first = items.first { copyItem(first) }
                    return .handled
                }
            if !mgr.searchQuery.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { mgr.searchQuery = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.faint)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(searchFocused ? Color.appGreen.opacity(0.4) : Color.clear,
                                lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    // MARK: - Add bar

    private var addBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.appGreen.opacity(0.7))
            TextField("Paste or type to save…", text: $addText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addFocused)
                .autocorrectionDisabled()
                .onSubmit { commitAdd() }
            if !addText.isEmpty {
                Button("Save") { commitAdd() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appGreen)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.appGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.lifted)
        .overlay(Rectangle().fill(Color.subtle).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - Clip list

    private var clipList: some View {
        // Compute once — each filter would otherwise run 3× per render.
        let pinnedItems = pinned
        let recentItems = recent
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if !pinnedItems.isEmpty {
                        SectionPill(label: "Pinned", count: pinnedItems.count)
                        ForEach(pinnedItems) { item in
                            clipRow(item: item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal:   .scale(scale: 0.9).combined(with: .opacity)
                                ))
                        }
                    }
                    if !recentItems.isEmpty {
                        SectionPill(label: "Recent", count: recentItems.count)
                        ForEach(recentItems) { item in
                            clipRow(item: item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal:   .scale(scale: 0.9).combined(with: .opacity)
                                ))
                        }
                    }
                    if items.isEmpty { emptyState }
                    Color.clear.frame(height: 8)
                }
                .padding(.top, 2)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func clipRow(item: ClipItem) -> some View {
        ClipRow(
            item:       item,
            nsImage:    item.type == .image ? ClipboardManager.shared.cachedImage(for: item) : nil,
            copiedID:   $copiedID,
            query:      mgr.searchQuery,
            isSelected: selectedID == item.id,
            onCopy:     { copyItem(item) },
            onPin:      { mgr.togglePin(item) },
            onDelete:   { mgr.delete(item) }
        )
        .id(item.id)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: mgr.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundColor(.muted)
            Text(mgr.searchQuery.isEmpty
                 ? "Nothing copied yet"
                 : "No results for \"\(mgr.searchQuery)\"")
                .font(.system(size: 12))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Circle().fill(Color.appGreen).frame(width: 5, height: 5)
                .padding(.trailing, 5)
            Text("\(mgr.items.count) clips · \(mgr.snippets.count) snippets")
                .font(.system(size: 10))
                .foregroundColor(.muted)
            Spacer()
            if activeTab == .clips {
                KbHint("↑↓", note: "select")
                KbHint("↵",  note: "copy").padding(.leading, 6)
                KbHint("Tab",note: "search").padding(.leading, 6)
                Rectangle().fill(Color.subtle).frame(width: 1, height: 10)
                    .padding(.horizontal, 8)
            }
            Text("⌘⇧V")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(Rectangle().fill(Color.subtle).frame(height: 0.5), alignment: .top)
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        let n = items.count
        guard n > 0 else { return }
        // If selectedID is stale (item was deleted / search results shifted),
        // snap to the first or last item instead of computing a bad index.
        if let id = selectedID, let cur = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[max(0, min(n - 1, cur + delta))].id
        } else {
            selectedID = items[delta >= 0 ? 0 : n - 1].id
        }
    }

    private func confirmSelection() {
        guard let id   = selectedID,
              let item = items.first(where: { $0.id == id })
        else { selectedID = nil; return }
        copyItem(item)
    }

    private func clearOrDeselect() {
        if showAdd {
            withAnimation(.spring(response: 0.28)) { showAdd = false }
            addFocused = false
            return
        }
        if !mgr.searchQuery.isEmpty { mgr.searchQuery = ""; return }
        if selectedID != nil { selectedID = nil; return }
        // Nothing left to dismiss — close the popover itself.
        NotificationCenter.default.post(name: .closePopoverRequest, object: nil)
    }

    private func copyItem(_ item: ClipItem) {
        mgr.copyToClipboard(item)
        withAnimation(.spring(response: 0.3)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .closePopoverRequest, object: nil)
        }
    }

    private func commitAdd() {
        let t = addText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        mgr.addItem(text: t)
        addText    = ""
        addFocused = false
        withAnimation(.spring(response: 0.28)) { showAdd = false }
    }
}

// MARK: - Snippet Manager View

struct SnippetManagerView: View {
    @ObservedObject private var mgr = ClipboardManager.shared
    @State private var editingSnippet:  Snippet?
    @State private var isCreatingNew    = false
    @State private var copiedSnippetID: UUID?
    @State private var accessibilityOK  = AXIsProcessTrusted() && CGPreflightListenEventAccess()
    // Stored as @State so the timer subscription is created once and held
    // stable across re-renders, preventing a new 2-second clock on every pass.
    @State private var permissionTimer  =
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            permissionBanner

            if mgr.snippets.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundColor(.muted)
                    Text("No snippets yet.\nTap + to create one.")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(mgr.snippets) { snippet in
                            SnippetRow(
                                snippet:  snippet,
                                isCopied: copiedSnippetID == snippet.id,
                                onCopy:   { copySnippet(snippet) },
                                onEdit: {
                                    isCreatingNew  = false
                                    editingSnippet = snippet
                                },
                                onDelete: {
                                    withAnimation(.spring(response: 0.3)) {
                                        mgr.deleteSnippet(snippet)
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .scale(scale: 0.9).combined(with: .opacity)
                            ))
                        }
                        Color.clear.frame(height: 8)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditSheet(snippet: snippet, isNew: isCreatingNew) { saved in
                if isCreatingNew { mgr.addSnippet(saved) } else { mgr.updateSnippet(saved) }
                editingSnippet = nil
            } onCancel: {
                editingSnippet = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            copiedSnippetID = nil
        }
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
                .foregroundColor(.appGreen)
            Text("Type /trigger then Space to expand")
                .font(.system(size: 11))
                .foregroundColor(.muted)
            Spacer()
            permissionBadge
            TinyBtn(icon: "plus", tooltip: "New snippet") {
                isCreatingNew  = true
                editingSnippet = Snippet(trigger: "/", expansion: "", description: "")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(accessibilityOK ? Color.appGreen.opacity(0.06)
                                    : Color.orange.opacity(0.05))
        .overlay(Rectangle().fill(Color.subtle).frame(height: 0.5), alignment: .bottom)
        .onAppear  { refreshPermission() }
        .onReceive(permissionTimer) { _ in refreshPermission() }
    }

    @ViewBuilder
    private var permissionBadge: some View {
        if accessibilityOK {
            HStack(spacing: 3) {
                Circle().fill(Color.appGreen).frame(width: 5, height: 5)
                Text("Active")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.appGreen)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.appGreen.opacity(0.1))
            .clipShape(Capsule())
        } else {
            Button {
                if !CGPreflightListenEventAccess() {
                    AppDelegate.openInputMonitoringSettings()
                } else {
                    AppDelegate.openAccessibilitySettings()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(!CGPreflightListenEventAccess()
                         ? "Needs Input Monitoring"
                         : "Needs Accessibility")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Toggle ClipboardApp on in the System Settings page that opens")
        }
    }

    // MARK: - Actions

    private func refreshPermission() {
        accessibilityOK = AXIsProcessTrusted() && CGPreflightListenEventAccess()
    }

    private func copySnippet(_ snippet: Snippet) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snippet.expansion, forType: .string)
        // Mark consumed so the monitor doesn't record this as a new clip.
        ClipboardManager.shared.markCurrentChangeConsumed()
        withAnimation { copiedSnippetID = snippet.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .closePopoverRequest, object: nil)
        }
    }
}

// MARK: - Snippet row

private struct SnippetRow: View {
    let snippet:  Snippet
    let isCopied: Bool
    let onCopy:   () -> Void
    let onEdit:   () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(snippet.trigger)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.appGreen)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.appGreen.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(minWidth: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.description.isEmpty ? snippet.expansion : snippet.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ink)
                    .lineLimit(1)
                if !snippet.description.isEmpty {
                    Text(snippet.expansion)
                        .font(.system(size: 10.5))
                        .foregroundColor(.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isCopied {
                CopiedBadge()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if hovered {
                HStack(spacing: 2) {
                    RowBtn(icon: "pencil",     color: .appGreen) { onEdit() }
                    RowBtn(icon: "doc.on.doc", color: nil)       { onCopy() }
                    RowBtn(icon: "trash",      color: .red)      { onDelete() }
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(hovered ? Color.faint : Color.clear)
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onCopy() }
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .animation(.spring(response: 0.28),   value: isCopied)
    }
}

// MARK: - Snippet edit sheet

struct SnippetEditSheet: View {
    @State private var snippet: Snippet
    let isNew:    Bool
    let onSave:   (Snippet) -> Void
    let onCancel: () -> Void

    @FocusState private var triggerFocused: Bool
    @FocusState private var expansionFocused: Bool

    init(snippet: Snippet, isNew: Bool,
         onSave: @escaping (Snippet) -> Void,
         onCancel: @escaping () -> Void) {
        _snippet      = State(initialValue: snippet)
        self.isNew    = isNew
        self.onSave   = onSave
        self.onCancel = onCancel
    }

    private var trimmedTrigger:   String { snippet.trigger.trimmingCharacters(in: .whitespaces) }
    private var trimmedExpansion: String { snippet.expansion.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { trimmedTrigger.count > 1 && !trimmedExpansion.isEmpty }
    /// Show a red border when the trigger has been touched but is still invalid.
    private var triggerIsInvalid: Bool { !triggerFocused && trimmedTrigger.count <= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Snippet" : "Edit Snippet")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            // Trigger field
            VStack(alignment: .leading, spacing: 5) {
                Label("Trigger", systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.muted)
                TextField("/shortcut", text: $snippet.trigger)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(Color.faint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(triggerIsInvalid
                                    ? Color.red.opacity(0.5)
                                    : Color.clear, lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    .focused($triggerFocused)
                    .onChange(of: snippet.trigger) { _, val in
                        var v = val.hasPrefix("/") ? val : "/" + val
                        if v.count > AppDelegate.K.maxTriggerLength {
                            v = String(v.prefix(AppDelegate.K.maxTriggerLength))
                        }
                        if v != val { snippet.trigger = v }
                    }
                Text("Type this in any app then press Space to expand. Must start with /")
                    .font(.system(size: 10))
                    .foregroundColor(triggerIsInvalid ? .red.opacity(0.7) : .muted)
                    .animation(.easeOut(duration: 0.15), value: triggerIsInvalid)
            }

            // Description field
            VStack(alignment: .leading, spacing: 5) {
                Label("Description (optional)", systemImage: "text.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.muted)
                TextField("e.g. Home address", text: $snippet.description)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color.faint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Expansion field
            VStack(alignment: .leading, spacing: 5) {
                Label("Expansion", systemImage: "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.muted)
                TextEditor(text: $snippet.expansion)
                    .font(.system(size: 12.5))
                    .frame(height: 90)
                    .padding(6)
                    .focused($expansionFocused)
                    .background(Color.faint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.subtle, lineWidth: 1)
                    )
            }

            // Action buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                Spacer()
                Button("Save Snippet") {
                    guard canSave else { return }
                    var toSave = snippet
                    toSave.trigger   = trimmedTrigger
                    toSave.expansion = trimmedExpansion
                    onSave(toSave)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(canSave ? Color.appGreen : Color.muted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeOut(duration: 0.12), value: canSave)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(Color.surface)
        .onAppear {
            if isNew { triggerFocused = true }
            else     { expansionFocused = true }
        }
    }
}

// MARK: - Clip row

struct ClipRow: View {
    let item:       ClipItem
    let nsImage:    NSImage?
    @Binding var copiedID: UUID?
    let query:      String
    let isSelected: Bool
    let onCopy:     () -> Void
    let onPin:      () -> Void
    let onDelete:   () -> Void

    @State private var hovered = false

    private var copied: Bool { copiedID == item.id }
    private var hot:    Bool { isSelected || hovered }

    var body: some View {
        HStack(spacing: 10) {
            typeBadge

            VStack(alignment: .leading, spacing: 2) {
                if item.type == .image, let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 160, maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.subtle, lineWidth: 0.5))
                        .padding(.vertical, 4)
                } else {
                    highlightedText
                        .foregroundColor(copied ? .muted : .ink)
                        .lineLimit(2)
                        .animation(.easeOut(duration: 0.15), value: copied)
                }

                HStack(spacing: 5) {
                    Text(item.date.relativeString)
                    if item.useCount > 1 {
                        Text("·")
                        Text("used \(item.useCount)×")
                    }
                }
                .font(.system(size: 9.5))
                .foregroundColor(.muted)
            }

            Spacer(minLength: 0)

            ZStack {
                if copied {
                    CopiedBadge()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else if isSelected && !hovered {
                    Text("↵")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.appGreen.opacity(0.75))
                        .transition(.opacity)
                } else if hovered {
                    rowActions
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .frame(width: 68, alignment: .trailing)
            .animation(.easeInOut(duration: 0.11), value: hovered)
            .animation(.spring(response: 0.28),    value: copied)
            .animation(.easeOut(duration: 0.1),    value: isSelected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onCopy() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var typeBadge: some View {
        if item.type == .color,
           let swatch = ClipboardManager.shared.cachedColor(for: item.text) {
            RoundedRectangle(cornerRadius: 5)
                .fill(swatch)
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(badgeColor.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: item.type.sfSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(badgeColor)
            }
        }
    }

    /// Builds a Text view with yellow highlights on every match of `query`.
    /// Uses character-distance arithmetic so highlighting is safe for all
    /// Unicode, including emoji and multi-scalar grapheme clusters.
    private var highlightedText: some View {
        let text = item.text
        let font: Font = item.type == .code
            ? .system(size: 12, design: .monospaced)
            : .system(size: 12.5)

        let q = query.lowercased()
        guard !q.isEmpty, text.lowercased().contains(q) else {
            return Text(text).font(font)
        }

        var result      = AttributedString(text)
        let lower       = text.lowercased()
        var searchStart = lower.startIndex

        while let matchRange = lower.range(of: q, range: searchStart..<lower.endIndex) {
            let startOffset = lower.distance(from: lower.startIndex, to: matchRange.lowerBound)
            let matchLength = lower.distance(from: matchRange.lowerBound, to: matchRange.upperBound)

            // Walk the AttributedString by character count, never by raw indices,
            // so we cross grapheme-cluster boundaries correctly.
            var attrIdx  = result.startIndex
            var walked   = 0

            // Advance to match start, clamped to endIndex.
            while walked < startOffset && attrIdx < result.endIndex {
                result.characters.formIndex(after: &attrIdx)
                walked += 1
            }
            let attrLo = attrIdx

            // Advance to match end, clamped to endIndex.
            walked = 0
            while walked < matchLength && attrIdx < result.endIndex {
                result.characters.formIndex(after: &attrIdx)
                walked += 1
            }
            let attrHi = attrIdx

            if attrLo < attrHi {
                result[attrLo..<attrHi].backgroundColor = Color.searchHighlight
                result[attrLo..<attrHi].foregroundColor = Color.primary
            }
            searchStart = matchRange.upperBound
        }

        return Text(result).font(font)
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            RowBtn(icon: item.isPinned ? "pin.slash" : "pin",
                   color: item.isPinned ? .orange : nil) {
                withAnimation(.spring(response: 0.25)) { onPin() }
            }
            RowBtn(icon: "trash", color: .red) {
                withAnimation(.easeOut(duration: 0.18)) { onDelete() }
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(
                copied     ? Color.appGreen.opacity(0.07) :
                isSelected ? Color.appGreen.opacity(0.10) :
                hovered    ? Color.faint : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected && !copied
                            ? Color.appGreen.opacity(0.28) : Color.clear,
                            lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hot)
            .animation(.spring(response: 0.28), value: copied)
    }

    private var badgeColor: Color {
        if item.isPinned { return .orange }
        switch item.type {
        case .link:  return Color(red: 0.22, green: 0.53, blue: 1.0)
        case .email: return Color(red: 1.0,  green: 0.60, blue: 0.1)
        case .phone: return .green
        case .code:  return Color(red: 0.60, green: 0.33, blue: 0.98)
        case .color: return Color(red: 0.95, green: 0.35, blue: 0.60)
        case .text:  return .secondary
        case .image: return .purple
        }
    }
}

// MARK: - Section pill

private struct SectionPill: View {
    let label: String
    let count: Int
    var body: some View {
        HStack(spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.muted)
                .kerning(0.9)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.muted.opacity(0.7))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.subtle)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Copied badge

struct CopiedBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Text("Copied")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.appGreen)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.appGreen.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Row action button

struct RowBtn: View {
    let icon:   String
    var color:  Color? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(hovered ? (color ?? .ink) : .muted)
                .frame(width: 26, height: 26)
                .background(hovered ? (color ?? Color.ink).opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .scaleEffect(hovered ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovered)
    }
}

// MARK: - Tiny header button

struct TinyBtn: View {
    let icon:    String
    let tooltip: String
    let action:  () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(hovered ? Color.faint : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .scaleEffect(hovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hovered)
        .help(tooltip)
    }
}

// MARK: - Keyboard hint chip

private struct KbHint: View {
    let key:  String
    let note: String
    init(_ key: String, note: String) { self.key = key; self.note = note }
    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.muted)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(Color.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(note)
                .font(.system(size: 9))
                .foregroundColor(Color.muted.opacity(0.65))
        }
    }
}

// MARK: - Date extension

extension Date {
    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    var relativeString: String {
        // Use abs() to handle future dates from clock skew without showing
        // confusing negative values like "-1m ago".
        let d = abs(Date().timeIntervalSince(self))
        if d < 60    { return "just now" }
        if d < 3_600 { return "\(Int(d / 60))m ago" }
        if d < 86_400 { return "\(Int(d / 3_600))h ago" }
        return Date.shortFormatter.string(from: self)
    }
}
