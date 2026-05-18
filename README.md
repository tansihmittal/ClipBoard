# ClipboardApp

A lightweight, native macOS clipboard manager that lives in your menu bar. Store up to 200 clips, pin favourites, search instantly, and expand text snippets anywhere you type — all processed locally with no network access.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift 5](https://img.shields.io/badge/Swift-5.0-orange) ![MIT License](https://img.shields.io/badge/license-MIT-green)

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [First Launch & Permissions](#first-launch--permissions)
- [How to Use](#how-to-use)
  - [Clipboard History](#clipboard-history-1)
  - [Text Snippets](#text-snippets-1)
  - [Keyboard Shortcuts](#keyboard-shortcuts)
- [Building from Source](#building-from-source)
- [How it Works](#how-it-works)
- [Privacy & Data](#privacy--data)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### Clipboard History
- Automatically captures **text and images** copied from any app
- Stores up to **200 items** with smart deduplication
- **Pin items** to keep them at the top regardless of age
- **Full-text search** across all clips with multi-word AND filtering
- Auto-detects clip type: link, email, phone number, code, hex colour, or image
- Inline **colour swatch preview** for hex values (`#1DB954`, `rgba(...)`)
- Usage counter and relative timestamps per item

### Text Snippets
- Type a `/trigger` in **any app**, then press Space, Tab, or Enter to expand it
- Works in every app including Electron apps, web browsers, and terminals
- Create, edit, and delete snippets from the built-in Snippets tab

### Global Hotkey & Menu Bar
- **⌘⇧V** opens the clipboard popover from anywhere
- Runs as a menu bar app — no Dock icon, no clutter

---

## Requirements

- **macOS 14.0 (Sonoma)** or later
- **Xcode 15+** (if building from source)
- Two system permissions granted on first launch:
  - **Accessibility** — injects keystrokes for snippet expansion
  - **Input Monitoring** — detects `/trigger` sequences as you type

---

## Installation

### Option A — Download pre-built release

1. Go to the [Releases](../../releases) page and download the latest `.zip`.
2. Unzip and drag **ClipboardApp.app** to your `/Applications` folder.
3. **First launch:** macOS Gatekeeper will block the app because it is not notarised. Right-click (or Control-click) the app icon → **Open** → **Open**. You only need to do this once.

### Option B — Build from source

See [Building from Source](#building-from-source) below.

---

## First Launch & Permissions

ClipboardApp needs two macOS permissions to fully function. It will prompt you automatically, but here is what each one does and how to grant it if the prompt is missed:

### 1 — Accessibility

Required for the snippet expander to inject backspace and paste keystrokes into other apps.

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Click the **+** button, navigate to `/Applications`, and add **ClipboardApp**.
3. Make sure the toggle next to ClipboardApp is **on**.

### 2 — Input Monitoring

Required for ClipboardApp to detect `/trigger` sequences as you type in any app.

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Click the **+** button, navigate to `/Applications`, and add **ClipboardApp**.
3. Make sure the toggle next to ClipboardApp is **on**.

> You do **not** need to restart the app after granting permissions. The Snippets tab shows a green **Active** badge once both permissions are detected.

---

## How to Use

### Opening the App

Click the **clipboard icon** in the menu bar, or press **⌘⇧V** from any app. The popover opens above the menu bar icon.

---

### Clipboard History

Everything you copy is captured automatically — you do not need to do anything special.

**Browsing clips**

- Scroll through **Pinned** and **Recent** sections in the Clips tab.
- Click any item to copy it to the clipboard and close the popover.

**Searching**

- Click the search bar at the top (or press **Tab** to jump to it from the keyboard).
- Type any word or phrase — results update as you type.
- Use multiple words to narrow results: typing `git push` only shows items containing both words.
- Press **Escape** to clear the search.

**Keyboard navigation**

- **↑ / ↓** — move selection up or down the list.
- **↵ (Return)** — copy the selected item and close the popover.
- **Tab** — jump focus to the search bar.
- **Escape** — clear search query, or deselect the current item.

**Pinning an item**

- Hover over any clip row to reveal the action buttons on the right.
- Click the **pin icon** to pin the item. Pinned items appear at the top of the list and are never auto-removed.
- Click the pin icon again (shown as a pin-slash) to unpin.

**Deleting an item**

- Hover over the clip row → click the **trash icon**.

**Manually adding a clip**

- Click the **+** button in the top-right corner of the Clips tab.
- Type or paste any text → press **Return** or click **Save**.

**Clearing all recent clips**

- Click the **⋯** (ellipsis) menu in the top-right corner → **Clear recents**.
- Pinned items are never deleted by this action.

**Adding a new clip manually**

- Click the **+** icon in the header to open the add bar.
- Type or paste text and press **Return** to save.

---

### Text Snippets

Snippets let you type a short `/trigger` in any app and have it replaced with a longer piece of text automatically.

**Expanding a snippet**

1. In any app (Notes, Slack, a browser, your terminal — anywhere), type your trigger exactly, e.g. `/sig`.
2. Press **Space**, **Tab**, or **Enter** immediately after the trigger.
3. ClipboardApp deletes the trigger text and pastes the full expansion in its place.

> Both **Accessibility** and **Input Monitoring** permissions must be granted for expansion to work. Check the green **Active** badge in the Snippets tab.

**Creating a snippet**

1. Open ClipboardApp and switch to the **Snippets** tab.
2. Click the **+** button on the right side of the banner.
3. Fill in the fields:
   - **Trigger** — must start with `/`, e.g. `/addr`. Maximum 20 characters. Keep it short and unique.
   - **Description** *(optional)* — a label shown in the snippet list.
   - **Expansion** — the full text that will be pasted when the trigger fires.
4. Press **⌘Return** or click **Save Snippet**.

**Editing a snippet**

- Hover over any snippet row → click the **pencil icon**.
- Make your changes → **⌘Return** or **Save Snippet**.

**Copying a snippet expansion manually**

- Hover over a snippet row → click the **copy icon** (double-document).
- The expansion text is copied to the clipboard and the popover closes.

**Deleting a snippet**

- Hover over the snippet row → click the **trash icon**.

**Default snippets (first launch)**

The app ships with five example snippets to demonstrate the feature:

| Trigger | Description |
|---------|-------------|
| `/addr` | Home address placeholder |
| `/sig`  | Email signature |
| `/ty`   | Quick thank-you reply |
| `/mtg`  | Meeting invite with calendar link |
| `/lorem`| Lorem ipsum paragraph |

Edit or delete these and replace them with your own.

---

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘⇧V** | Open / close the clipboard popover (global, works in any app) |
| **Tab** | Focus the search bar |
| **↑ / ↓** | Move selection in the clips list |
| **↵** | Copy selected clip and close popover |
| **Escape** | Clear search / deselect / close add bar |
| **⌘Return** | Save snippet in the edit sheet |
| **Escape** | Cancel snippet edit sheet |

---

## Building from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/tanishmittal25/ClipboardApp.git
   cd ClipboardApp
   ```

2. **Open in Xcode**
   ```bash
   open ClipboardApp.xcodeproj
   ```

3. **Set your signing team**
   - Select the **ClipboardApp** target in the project navigator.
   - Go to **Signing & Capabilities**.
   - Under **Team**, choose your Apple ID (a free Apple Developer account works for local builds).

4. **Build and run**
   - Press **⌘R**, or go to **Product → Run**.
   - The app will appear in your menu bar immediately.

5. **Grant permissions when prompted**
   - Follow the [First Launch & Permissions](#first-launch--permissions) steps above.

**Archiving a release build**

To produce a distributable `.app`:
- **Product → Archive**
- In the Organiser window → **Distribute App → Direct Distribution → Export**
- Zip the exported `.app` and attach it to a GitHub Release.

> The app does **not** require sandboxing and must not be submitted to the Mac App Store — the App Store sandbox blocks the global event monitor and `CGEvent` injection that snippet expansion relies on.

---

## How it Works

| Component | Implementation |
|-----------|----------------|
| UI | SwiftUI on macOS 14, hosted in `NSPopover` |
| Reactive state | `ObservableObject` + Combine `CombineLatest` search pipeline |
| Clipboard monitoring | `NSPasteboard` polled every 0.5 s on a dedicated serial queue |
| Snippet detection | `NSEvent.addGlobalMonitorForEvents(.keyDown)` (requires Input Monitoring) |
| Snippet expansion | `CGEvent` backspace injection + `CGEvent` Cmd-V paste (requires Accessibility) |
| Global hotkey | Carbon `RegisterEventHotKey` — ⌘⇧V |
| Persistence | JSON written atomically to `~/Library/Application Support/ClipboardApp/`, debounced 0.5 s |
| Image storage | TIFF/PNG captured; JPEG-recompressed if > 512 KB; decoded back to TIFF on paste |
| Snippet lookup | O(1) `[String: Snippet]` dictionary rebuilt on every change |

---

## Privacy & Data

- All data is stored **entirely on your device** in `~/Library/Application Support/ClipboardApp/`.
- The app makes **zero network requests** — no analytics, no telemetry, no crash reporting.
- Input Monitoring is used **only** to detect `/trigger` sequences. Keystrokes are never logged, stored, or transmitted.
- To completely remove all app data: quit the app, delete `ClipboardApp.app`, and delete `~/Library/Application Support/ClipboardApp/`.

---

## Contributing

Pull requests are welcome. For significant changes, please open an issue first to discuss what you'd like to change.

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m "Add my feature"`
4. Push the branch: `git push origin feature/my-feature`
5. Open a Pull Request.

---

## License

[MIT](LICENSE) © 2025 Tanish Mittal
