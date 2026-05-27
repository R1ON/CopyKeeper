import AppKit
import Foundation

class ClipboardMonitor {
    weak var store: ClipboardStore?
    private var lastChangeCount: Int
    private var timer: Timer?

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if store?.ignoreNextChange == true {
            store?.ignoreNextChange = false
            return
        }

        guard let item = createItem(from: pb) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.store?.addItem(item)
        }
    }

    private func createItem(from pb: NSPasteboard) -> ClipboardItem? {
        let sourceApp = getSourceApp()

        // Check for image data first
        if let imageData = pb.data(forType: NSPasteboard.PasteboardType("public.png")) ?? pb.data(forType: .tiff) {
            guard let store = store else { return nil }
            let id = UUID()
            // Re-encode to compressed PNG (raw TIFF from the pasteboard is huge).
            let pngData = NSBitmapImageRep(data: imageData)?
                .representation(using: .png, properties: [:]) ?? imageData
            if let path = store.persistence.saveImage(pngData, id: id) {
                return ClipboardItem(id: id, type: .image, imagePath: path, sourceApp: sourceApp)
            }
        }

        // Check for string
        if let text = pb.string(forType: .string), !text.isEmpty {
            let type = detectType(text: text, sourceApp: sourceApp)
            let item = ClipboardItem(type: type, textContent: text, sourceApp: sourceApp)

            // For URLs, async fetch favicon + Open Graph preview image
            if type == .url, let url = URL(string: text), let host = url.host {
                let itemID = item.id
                let faviconURLString = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
                if let faviconURL = URL(string: faviconURLString) {
                    URLSession.shared.dataTask(with: faviconURL) { [weak self] data, _, _ in
                        guard let data = data, let self = self else { return }
                        DispatchQueue.main.async {
                            if let idx = self.store?.items.firstIndex(where: { $0.id == itemID }) {
                                self.store?.items[idx].sourceApp?.faviconData = data
                            }
                        }
                    }.resume()
                }
                fetchPreviewImage(for: url, itemID: itemID)
            }

            return item
        }

        return nil
    }

    private func fetchPreviewImage(for url: URL, itemID: UUID) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh) CopyKeeper", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            let html = String(decoding: data.prefix(400_000), as: UTF8.self)
            guard let imageURLString = self.parseOGImage(html),
                  let imageURL = URL(string: imageURLString, relativeTo: url) else { return }

            URLSession.shared.dataTask(with: imageURL) { [weak self] imgData, _, _ in
                guard let self = self, let imgData = imgData,
                      let store = self.store,
                      NSImage(data: imgData) != nil else { return }
                DispatchQueue.main.async {
                    guard let idx = store.items.firstIndex(where: { $0.id == itemID }) else { return }
                    if let path = store.persistence.saveImage(imgData, id: UUID()) {
                        store.items[idx].previewImagePath = path
                        store.persist()
                    }
                }
            }.resume()
        }.resume()
    }

    private func parseOGImage(_ html: String) -> String? {
        let patterns = [
            "<meta[^>]+property=[\"']og:image[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:image[\"']",
            "<meta[^>]+name=[\"']twitter:image[\"'][^>]+content=[\"']([^\"']+)[\"']"
        ]
        let range = NSRange(html.startIndex..., in: html)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { continue }
            let value = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func getSourceApp() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier
        let name = app.localizedName

        // Store the icon once per app (keyed by bundleID) instead of embedding
        // a copy in every item.
        if let bundleID,
           let icon = app.icon?.resized(to: NSSize(width: 32, height: 32)),
           let png = icon.tiffRepresentation.flatMap({
               NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
           }) {
            IconStore.shared.register(bundleID: bundleID, data: png)
        }

        return SourceApp(bundleID: bundleID, name: name)
    }

    private func detectType(text: String, sourceApp: SourceApp?) -> ContentType {
        // Color detection (hex / rgb / rgba / hsl / hsla)
        if looksLikeColor(text) {
            return .color
        }

        // URL detection
        if let url = URL(string: text), url.scheme != nil, url.host != nil {
            return .url
        }

        // Code detection
        if let bundleID = sourceApp?.bundleID {
            let codeApps = ["com.apple.dt.Xcode", "com.microsoft.VSCode",
                            "com.apple.Terminal", "com.googlecode.iterm2",
                            "com.sublimetext", "com.jetbrains"]
            let isCodeApp = codeApps.contains(where: { bundleID.contains($0) })
            if isCodeApp { return .code }
        }

        let codeKeywords = ["func ", "def ", "class ", "import ", "const ", "let ", "var ",
                            "function ", "return ", "{", "}", "//", "#include"]
        let keywordCount = codeKeywords.filter { text.contains($0) }.count
        if keywordCount >= 2 { return .code }

        return .text
    }
}
