import AppKit
import Foundation
import CryptoKit

class ClipboardMonitor {
    weak var store: ClipboardStore?
    private var lastChangeCount: Int
    private var timer: Timer?
    // Heavy decoding/encoding runs here so the main-thread timer tick stays cheap.
    private let processQueue = DispatchQueue(label: "com.copykeeper.monitor", qos: .userInitiated)

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

        // Snapshot the pasteboard + frontmost app on the main thread (both must
        // be touched here), then hand the heavy work off to a background queue.
        let sourceApp = getSourceApp()
        let imageData = pb.data(forType: NSPasteboard.PasteboardType("public.png")) ?? pb.data(forType: .tiff)
        let text = pb.string(forType: .string)
        guard let persistence = store?.persistence else { return }

        processQueue.async { [weak self] in
            guard let self,
                  let item = self.buildItem(imageData: imageData, text: text,
                                            sourceApp: sourceApp, persistence: persistence)
            else { return }
            DispatchQueue.main.async { self.store?.addItem(item) }
        }
    }

    private func buildItem(imageData: Data?, text: String?,
                           sourceApp: SourceApp?, persistence: PersistenceManager) -> ClipboardItem? {
        // Check for image data first
        if let imageData {
            let id = UUID()
            // Re-encode to compressed PNG (raw TIFF from the pasteboard is huge).
            let pngData = NSBitmapImageRep(data: imageData)?
                .representation(using: .png, properties: [:]) ?? imageData
            let hash = Self.sha256Hex(pngData)
            if let path = persistence.saveImage(pngData, id: id) {
                return ClipboardItem(id: id, type: .image, imagePath: path,
                                     sourceApp: sourceApp, imageHash: hash)
            }
            return nil
        }

        // Check for string
        if let text = text, !text.isEmpty {
            let type = detectType(text: text, sourceApp: sourceApp)
            var item = ClipboardItem(type: type, textContent: text, sourceApp: sourceApp)

            // For URLs, async fetch favicon + Open Graph preview image
            if type == .url,
               let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let host = url.host {
                let itemID = item.id
                if FaviconStore.shared.contains(host: host) {
                    // Already cached — reference it immediately.
                    if item.sourceApp == nil { item.sourceApp = SourceApp() }
                    item.sourceApp?.faviconHost = host
                } else if let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
                    URLSession.shared.dataTask(with: faviconURL) { [weak self] data, _, _ in
                        guard let data = data, NSImage(data: data) != nil,
                              let self = self else { return }
                        FaviconStore.shared.register(host: host, data: data)
                        DispatchQueue.main.async {
                            guard let store = self.store,
                                  let idx = store.items.firstIndex(where: { $0.id == itemID }) else { return }
                            if store.items[idx].sourceApp == nil { store.items[idx].sourceApp = SourceApp() }
                            store.items[idx].sourceApp?.faviconHost = host
                            store.persist()
                        }
                    }.resume()
                }
                fetchPreviewImage(for: url, itemID: itemID)
            }

            return item
        }

        return nil
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        // a copy in every item. Skip the resize + PNG re-encode entirely once
        // we already have it — this runs on every clipboard change.
        if let bundleID, !IconStore.shared.contains(bundleID: bundleID),
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

        // URL detection: must be a single whitespace-free http(s) URL, so a
        // sentence that merely contains a link isn't misclassified.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
           let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
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
