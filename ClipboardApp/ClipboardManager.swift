import Foundation
import AppKit
import Combine
import SwiftUI

// MARK: - Snippet Model

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var trigger: String
    var expansion: String
    var description: String

    init(id: UUID = UUID(), trigger: String, expansion: String, description: String = "") {
        self.id          = id
        self.trigger     = trigger.hasPrefix("/") ? trigger : "/\(trigger)"
        self.expansion   = expansion
        self.description = description
    }
}

// MARK: - Clip Type

enum ClipType: String, Codable, CaseIterable {
    case link, email, phone, code, color, text, image

    static func detect(from text: String) -> ClipType {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("www.") { return .link }
        if t.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil { return .email }
        let phoneClean = t.filter { $0.isNumber || "+-() ".contains($0) }
        if phoneClean.count == t.count && t.filter(\.isNumber).count >= 7 { return .phone }
        if (t.hasPrefix("#") && (t.count == 4 || t.count == 7 || t.count == 9)) ||
           t.range(of: #"^rgba?\(\d"#, options: .regularExpression) != nil { return .color }
        let codeSignals = ["import ", "func ", "var ", "let ", "const ", "def ", "class ",
                           "return ", "npm ", "pip ", "git ", "sudo ", "->", "=> ", "#!/",
                           "struct ", "interface ", "public ", "private ", "async "]
        if codeSignals.contains(where: { t.contains($0) }) { return .code }
        return .text
    }

    var sfSymbol: String {
        switch self {
        case .link:  return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .text:  return "doc.text"
        case .image: return "photo"
        }
    }
}

// MARK: - Clip Item

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var imageData: Data?
    var date: Date
    var isPinned: Bool
    var type: ClipType
    var useCount: Int

    init(text: String, pinned: Bool = false) {
        self.id        = UUID()
        self.text      = text
        self.imageData = nil
        self.date      = Date()
        self.isPinned  = pinned
        self.type      = ClipType.detect(from: text)
        self.useCount  = 0
    }

    init(imageData: Data, pinned: Bool = false) {
        self.id        = UUID()
        self.text      = "Image (\(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)))"
        self.imageData = imageData
        self.date      = Date()
        self.isPinned  = pinned
        self.type      = .image
        self.useCount  = 0
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Manager

/// All `@Published` mutations and public methods must be called on the **main thread**.
/// The only exception is `checkClipboardOnQueue()` and `markCurrentChangeConsumed()`,
/// which run on `pasteboardQueue`. Thread ownership is documented per-property.
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    // Main-thread only.
    @Published var items: [ClipItem] = []
    @Published var searchQuery: String = ""
    @Published private(set) var visibleItems: [ClipItem] = []
    @Published var snippets: [Snippet] = [] {
        didSet { rebuildSnippetIndex() }
    }

    private var searchCancellable: AnyCancellable?
    private var pollTimer: Timer?

    // pasteboardQueue only — no lock needed as long as this invariant holds.
    private var lastChangeCount: Int = 0

    private let maxItems = 200
    // Max entries kept in the hex-colour cache. Evicted wholesale when exceeded
    // so we never hold on to hundreds of one-off colours from large code files.
    private let maxHexCacheSize = 256

    private let saveQueue      = DispatchQueue(label: "com.clipboardapp.save",       qos: .utility)
    private let pasteboardQueue = DispatchQueue(label: "com.clipboardapp.pasteboard", qos: .default)

    private var pendingItemSave:    DispatchWorkItem?
    private var pendingSnippetSave: DispatchWorkItem?

    // O(1) trigger → snippet lookup. Rebuilt whenever `snippets` changes.
    // Keys are pre-lowercased so comparison is just a Dictionary lookup.
    private var snippetIndex: [String: Snippet] = [:]

    // Colour parsing cache. Bounded by `maxHexCacheSize`.
    private var hexColorCache: [String: Color?] = [:]
    private var imageCache:    [UUID: NSImage]   = [:]

    // MARK: - URLs

    private static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in:  .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ClipboardApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let saveURL     = ClipboardManager.appSupportDir.appendingPathComponent("clips.json")
    private let snippetsURL = ClipboardManager.appSupportDir.appendingPathComponent("snippets.json")

    // MARK: - Init

    private init() {
        loadItems()
        loadSnippets()
        setupSearch()
    }

    // MARK: - Permissions

    func checkAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    // MARK: - Search pipeline

    private func setupSearch() {
        // Debounce only the query so new clip items appear instantly,
        // while rapid keystrokes don't re-filter on every character.
        searchCancellable = Publishers.CombineLatest(
            $items,
            $searchQuery.debounce(for: .milliseconds(60), scheduler: RunLoop.main)
        )
        .map { items, query -> [ClipItem] in
            guard !query.isEmpty else { return items }
            let words = query.lowercased().split(separator: " ").map(String.init)
            return items.filter { item in
                let lower = item.text.lowercased()
                return words.allSatisfy { lower.contains($0) }
            }
        }
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.visibleItems = $0 }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        pasteboardQueue.async { [weak self] in
            self?.lastChangeCount = NSPasteboard.general.changeCount
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pasteboardQueue.async { self?.checkClipboardOnQueue() }
        }
        if let t = pollTimer { RunLoop.main.add(t, forMode: .common) }
    }

    /// Runs exclusively on `pasteboardQueue`.
    private func checkClipboardOnQueue() {
        let pb          = NSPasteboard.general
        let changeCount = pb.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            var finalData = imageData
            if imageData.count > 512 * 1_024,
               let img    = NSImage(data: imageData),
               let tiff   = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let jpeg   = bitmap.representation(using: .jpeg,
                                                   properties: [.compressionFactor: 0.7]) {
                finalData = jpeg
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.isSameImageData(finalData,
                                            as: self.items.first(where: { $0.type == .image })?.imageData)
                else { return }
                self.addItem(imageData: finalData, fromClipboard: true)
            }
            return
        }

        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.items.first(where: { $0.type != .image })?.text != text
                else { return }
                self.addItem(text: text, fromClipboard: true)
            }
        }
    }

    // MARK: - CRUD

    func addItem(text: String, fromClipboard: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.removeAll { $0.text == trimmed && !$0.isPinned && $0.type != .image }
        let item     = ClipItem(text: trimmed)
        let insertAt = items.firstIndex(where: { !$0.isPinned }) ?? items.endIndex
        items.insert(item, at: insertAt)
        limitItems()
        saveItemsAsync()
    }

    func addItem(imageData: Data, fromClipboard: Bool = false) {
        items.removeAll { item in
            guard item.type == .image, !item.isPinned else { return false }
            return isSameImageData(imageData, as: item.imageData)
        }
        let item     = ClipItem(imageData: imageData)
        let insertAt = items.firstIndex(where: { !$0.isPinned }) ?? items.endIndex
        items.insert(item, at: insertAt)
        limitItems()
        saveItemsAsync()
    }

    private func limitItems() {
        let unpinnedIdx = items.indices.filter { !items[$0].isPinned }
        guard unpinnedIdx.count > maxItems else { return }
        let toRemove = unpinnedIdx.suffix(unpinnedIdx.count - maxItems)
        toRemove.forEach { imageCache.removeValue(forKey: items[$0].id) }
        items.remove(atOffsets: IndexSet(toRemove))
    }

    func copyToClipboard(_ item: ClipItem) {
        let imageData = item.imageData
        let text      = item.text
        pasteboardQueue.async { [weak self] in
            let pb = NSPasteboard.general
            pb.clearContents()
            if let data = imageData {
                // Stored data may be JPEG-compressed; re-encode via NSImage so
                // all receiving apps get a proper TIFF, not raw JPEG bytes.
                if let img = NSImage(data: data), let tiff = img.tiffRepresentation {
                    pb.setData(tiff, forType: .tiff)
                } else {
                    pb.setData(data, forType: .tiff)
                }
            } else {
                pb.setString(text, forType: .string)
            }
            self?.lastChangeCount = pb.changeCount
        }
        // Defer @Published mutation one tick to avoid "publishing from within
        // view updates" warnings triggered by tap-gesture callbacks.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let idx = self.items.firstIndex(of: item) {
                self.items[idx].useCount += 1
                self.items[idx].date = Date()
            }
            self.saveItemsAsync()
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].isPinned.toggle()
        reorder()
        saveItemsAsync()
    }

    func delete(_ item: ClipItem) {
        imageCache.removeValue(forKey: item.id)
        items.removeAll { $0.id == item.id }
        saveItemsAsync()
    }

    func clearAll() {
        items.filter { !$0.isPinned }.forEach { imageCache.removeValue(forKey: $0.id) }
        items.removeAll { !$0.isPinned }
        hexColorCache.removeAll()
        saveItemsAsync()
    }

    private func reorder() {
        let pinned   = items.filter(\.isPinned)
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + unpinned
    }

    // MARK: - Snippet CRUD

    func addSnippet(_ snippet: Snippet) {
        // Single mutation so `didSet` (index rebuild) fires exactly once.
        if let idx = snippets.firstIndex(where: {
            $0.trigger.lowercased() == snippet.trigger.lowercased()
        }) {
            snippets[idx] = snippet
        } else {
            snippets.append(snippet)
        }
        saveSnippetsAsync()
    }

    func updateSnippet(_ snippet: Snippet) {
        guard snippets.contains(where: { $0.id == snippet.id }) else { return }
        // Remove any other snippet that already owns this trigger (case-insensitive)
        // before writing, so the array never holds duplicate triggers.
        snippets.removeAll {
            $0.id != snippet.id &&
            $0.trigger.lowercased() == snippet.trigger.lowercased()
        }
        // Re-find the index after the potential removal above.
        if let newIdx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[newIdx] = snippet
        } else {
            snippets.append(snippet)
        }
        saveSnippetsAsync()
    }

    func deleteSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        saveSnippetsAsync()
    }

    /// O(1) exact trigger match used for expansion on Space/Tab/Enter.
    func snippetMatch(for input: String) -> Snippet? {
        snippetIndex[input.lowercased()]
    }

    /// Keep `snippetIndex` in sync with `snippets` whenever the array changes.
    private func rebuildSnippetIndex() {
        snippetIndex = Dictionary(
            snippets.map { ($0.trigger.lowercased(), $0) },
            uniquingKeysWith: { _, new in new }
        )
    }

    // MARK: - Cache helpers

    /// Prevents the clipboard monitor from recording the snippet expansion
    /// that the expander just wrote to the pasteboard.
    func markCurrentChangeConsumed() {
        pasteboardQueue.async { [weak self] in
            self?.lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    func cachedColor(for hex: String) -> Color? {
        if let idx = hexColorCache.index(forKey: hex) { return hexColorCache[idx].value }
        // Evict the whole cache when it hits the size cap to avoid unbounded
        // growth from large code files full of unique colour values.
        if hexColorCache.count >= maxHexCacheSize { hexColorCache.removeAll() }
        let result = parseHexColor(hex)
        hexColorCache[hex] = result
        return result
    }

    func cachedImage(for item: ClipItem) -> NSImage? {
        if let cached = imageCache[item.id] { return cached }
        guard let data = item.imageData, let image = NSImage(data: data) else { return nil }
        imageCache[item.id] = image
        return image
    }

    // MARK: - Private helpers

    private func parseHexColor(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        guard h.hasPrefix("#") else { return nil }
        h = String(h.dropFirst())
        guard h.count == 3 || h.count == 6 else { return nil }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard let val = UInt64(h, radix: 16) else { return nil }
        return Color(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }

    /// Reliable image dedup:
    /// - Same byte count  AND
    /// - Same first 128 bytes (header / magic bytes)  AND
    /// - Same last  64 bytes  (end-of-file marker / entropy tail)
    ///
    /// The combined check eliminates both false positives (different images
    /// that compress to the same size) and false negatives (re-encoded JPEGs
    /// with a marginally different size from the same source pixels).
    private func isSameImageData(_ a: Data, as b: Data?) -> Bool {
        guard let b, a.count == b.count else { return false }
        return a.prefix(128) == b.prefix(128) && a.suffix(64) == b.suffix(64)
    }

    // MARK: - Persistence (debounced 0.5 s)

    private func saveItemsAsync() {
        pendingItemSave?.cancel()
        let snapshot = items
        let url      = saveURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        pendingItemSave = work
        saveQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveSnippetsAsync() {
        pendingSnippetSave?.cancel()
        let snapshot = snippets
        let url      = snippetsURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        pendingSnippetSave = work
        saveQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func loadItems() {
        guard let data = try? Data(contentsOf: saveURL) else { seedDefaults(); return }
        if let saved = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = saved
        } else {
            // File exists but is corrupt — back it up so the user can recover it,
            // then start fresh rather than crashing or silently dropping data.
            let backup = saveURL.deletingPathExtension()
                .appendingPathExtension("corrupt.json")
            try? FileManager.default.moveItem(at: saveURL, to: backup)
            seedDefaults()
        }
    }

    private func loadSnippets() {
        guard let data = try? Data(contentsOf: snippetsURL) else { seedSnippets(); return }
        if let saved = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = saved          // didSet rebuilds index
        } else {
            let backup = snippetsURL.deletingPathExtension()
                .appendingPathExtension("corrupt.json")
            try? FileManager.default.moveItem(at: snippetsURL, to: backup)
            seedSnippets()
        }
    }

    // MARK: - Seed data

    private func seedDefaults() {
        items = [
            ClipItem(text: "https://github.com",                               pinned: true),
            ClipItem(text: "hello@example.com",                                pinned: true),
            ClipItem(text: "let greeting = \"Hello, World!\""),
            ClipItem(text: "+1 (415) 555-0192"),
            ClipItem(text: "#1DB954"),
            ClipItem(text: "Meeting at 3 pm in Conference Room B"),
        ]
    }

    private func seedSnippets() {
        snippets = [
            Snippet(trigger: "/addr",  expansion: "123 Main St, San Francisco, CA 94105",
                    description: "Home address"),
            Snippet(trigger: "/sig",   expansion: "Best regards,\nYour Name\nyour@email.com",
                    description: "Email signature"),
            Snippet(trigger: "/ty",    expansion: "Thank you for reaching out! I'll get back to you shortly.",
                    description: "Quick thanks"),
            Snippet(trigger: "/mtg",   expansion: "Let's find a time — here's my calendar: https://calendly.com/yourname",
                    description: "Meeting invite"),
            Snippet(trigger: "/lorem", expansion: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
                    description: "Lorem ipsum"),
        ]   // didSet fires, rebuilds index
    }
}
