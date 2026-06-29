import Foundation
import AppKit

// MARK: - ContentType

enum ContentType: String, Codable, CaseIterable {
    case text
    case url
    case code
    case image
    case color
}

// MARK: - SourceApp

struct SourceApp: Codable, Equatable {
    var bundleID: String?
    var name: String?
    var iconData: Data?
    var tintColor: CodableColor?
    // Legacy: older items embedded favicon bytes here. New items reference a
    // deduplicated favicon by host via `faviconHost` + FaviconStore instead.
    var faviconData: Data?
    var faviconHost: String?

    init(bundleID: String? = nil,
         name: String? = nil,
         iconData: Data? = nil,
         tintColor: CodableColor? = nil,
         faviconData: Data? = nil,
         faviconHost: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.iconData = iconData
        self.tintColor = tintColor
        self.faviconData = faviconData
        self.faviconHost = faviconHost
    }
}

// MARK: - ClipboardItem

struct ClipboardItem: Codable, Identifiable, Equatable {
    var id: UUID
    var timestamp: Date
    var type: ContentType
    var textContent: String?
    var imagePath: String?
    var sourceApp: SourceApp?
    var groupIDs: [UUID]
    var customTitle: String?
    var previewImagePath: String?
    // Optional so older persisted items (without this key) decode cleanly.
    var pinned: Bool?
    // Content hash of the stored image, used to dedup identical screenshots.
    var imageHash: String?

    var isPinned: Bool { pinned ?? false }

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         type: ContentType,
         textContent: String? = nil,
         imagePath: String? = nil,
         sourceApp: SourceApp? = nil,
         groupIDs: [UUID] = [],
         customTitle: String? = nil,
         previewImagePath: String? = nil,
         pinned: Bool? = nil,
         imageHash: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.textContent = textContent
        self.imagePath = imagePath
        self.sourceApp = sourceApp
        self.groupIDs = groupIDs
        self.customTitle = customTitle
        self.previewImagePath = previewImagePath
        self.pinned = pinned
        self.imageHash = imageHash
    }
}
