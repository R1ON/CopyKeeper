import Foundation
import os

private let log = Logger(subsystem: "com.copykeeper", category: "persistence")

// MARK: - StoreData

struct StoreData: Codable {
    var items: [ClipboardItem]
    var groups: [ClipboardGroup]
}

// MARK: - PersistenceManager

class PersistenceManager {
    let imagesDirectory: URL
    let dataFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CopyKeeper", isDirectory: true)
        imagesDirectory = appDir.appendingPathComponent("images", isDirectory: true)
        dataFileURL = appDir.appendingPathComponent("data.json")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    func save(_ data: StoreData) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: dataFileURL, options: .atomic)
            return true
        } catch {
            log.error("save error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func load() -> StoreData? {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: dataFileURL)
            return try decoder.decode(StoreData.self, from: data)
        } catch {
            log.error("load error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveImage(_ data: Data, id: UUID) -> String? {
        let url = imagesDirectory.appendingPathComponent("\(id.uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            log.error("saveImage error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func cacheSizeBytes() -> Int64 {
        var total: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dataFileURL.path),
           let size = attrs[.size] as? Int64 {
            total += size
        }
        if let files = try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let size = values.fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    func fileSize(atPath path: String) -> Int64 {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            return size
        }
        return 0
    }

    func deleteImage(atPath path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    func deleteAllImages(exceptPaths: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: imagesDirectory,
                                                                        includingPropertiesForKeys: nil) else { return }
        for file in files {
            if !exceptPaths.contains(file.path) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
