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

struct SourceApp: Codable {
    var bundleID: String?
    var name: String?
    var iconData: Data?
    var tintColor: CodableColor?
    var faviconData: Data?

    init(bundleID: String? = nil,
         name: String? = nil,
         iconData: Data? = nil,
         tintColor: CodableColor? = nil,
         faviconData: Data? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.iconData = iconData
        self.tintColor = tintColor
        self.faviconData = faviconData
    }
}

// MARK: - ClipboardItem

struct ClipboardItem: Codable, Identifiable {
    var id: UUID
    var timestamp: Date
    var type: ContentType
    var textContent: String?
    var imagePath: String?
    var sourceApp: SourceApp?
    var groupIDs: [UUID]
    var customTitle: String?
    var previewImagePath: String?

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         type: ContentType,
         textContent: String? = nil,
         imagePath: String? = nil,
         sourceApp: SourceApp? = nil,
         groupIDs: [UUID] = [],
         customTitle: String? = nil,
         previewImagePath: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.textContent = textContent
        self.imagePath = imagePath
        self.sourceApp = sourceApp
        self.groupIDs = groupIDs
        self.customTitle = customTitle
        self.previewImagePath = previewImagePath
    }
}
