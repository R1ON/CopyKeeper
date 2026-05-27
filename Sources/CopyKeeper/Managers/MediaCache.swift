import AppKit
import ImageIO

// MARK: - IconStore
//
// App icons are identical across every item from the same app, so storing a
// copy inside each ClipboardItem bloated data.json. Instead we keep one PNG per
// bundle identifier here, in a small side file, and items just reference the
// bundleID. Decoded NSImages are memoised so the card row stays cheap.

final class IconStore {
    static let shared = IconStore()

    private var data: [String: Data] = [:]
    private let cache = NSCache<NSString, NSImage>()
    private let fileURL: URL
    private let saveQueue = DispatchQueue(label: "com.copykeeper.iconstore", qos: .utility)
    private var dirty = false

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        fileURL = appSupport.appendingPathComponent("CopyKeeper/appicons.json")
        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: raw) {
            data = decoded
        }
    }

    /// Store the icon for a bundle once; subsequent copies from the same app are free.
    func register(bundleID: String, data iconData: Data) {
        guard self.data[bundleID] == nil else { return }
        self.data[bundleID] = iconData
        scheduleSave()
    }

    func nsImage(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let raw = data[bundleID], let image = NSImage(data: raw) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private func scheduleSave() {
        dirty = true
        let snapshot = data
        saveQueue.async { [weak self] in
            guard let self = self, self.dirty else { return }
            self.dirty = false
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: self.fileURL, options: .atomic)
            }
        }
    }
}

// MARK: - ThumbnailCache
//
// Image/link cards only need a card-sized preview, but the originals can be
// several megabytes. Decode a downsampled thumbnail via ImageIO off the main
// thread and cache it, so scrolling doesn't re-decode full-resolution bitmaps.

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.copykeeper.thumbnails",
                                      qos: .userInitiated, attributes: .concurrent)

    func image(forPath path: String, maxPixel: CGFloat, completion: @escaping (NSImage?) -> Void) {
        let key = "\(path)@\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        queue.async { [weak self] in
            let image = ThumbnailCache.downsample(path: path, maxPixel: maxPixel)
            if let image { self?.cache.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    private static func downsample(path: String, maxPixel: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
