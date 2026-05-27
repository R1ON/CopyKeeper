import Foundation

// MARK: - RetentionPeriod

enum RetentionPeriod: String, Codable, CaseIterable, Identifiable {
    case oneHour = "1 час"
    case tenHours = "10 часов"
    case oneDay = "1 день"
    case oneWeek = "1 неделя"
    case oneMonth = "1 месяц"
    case oneYear = "1 год"
    case never = "Никогда"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .oneHour:  return Loc.s("1 час", "1 hour")
        case .tenHours: return Loc.s("10 часов", "10 hours")
        case .oneDay:   return Loc.s("1 день", "1 day")
        case .oneWeek:  return Loc.s("1 неделя", "1 week")
        case .oneMonth: return Loc.s("1 месяц", "1 month")
        case .oneYear:  return Loc.s("1 год", "1 year")
        case .never:    return Loc.s("Никогда", "Never")
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .oneHour:  return 60 * 60
        case .tenHours: return 60 * 60 * 10
        case .oneDay:   return 60 * 60 * 24
        case .oneWeek:  return 60 * 60 * 24 * 7
        case .oneMonth: return 60 * 60 * 24 * 30
        case .oneYear:  return 60 * 60 * 24 * 365
        case .never:    return nil
        }
    }
}

// MARK: - ClipboardGroup

struct ClipboardGroup: Codable, Identifiable {
    var id: UUID
    var name: String
    var retention: RetentionPeriod
    var itemIDs: [UUID]
    var isDefault: Bool
    var colorIndex: Int?
    var emoji: String?

    init(id: UUID = UUID(),
         name: String,
         retention: RetentionPeriod = .never,
         itemIDs: [UUID] = [],
         isDefault: Bool = false,
         colorIndex: Int? = nil,
         emoji: String? = nil) {
        self.id = id
        self.name = name
        self.retention = retention
        self.itemIDs = itemIDs
        self.isDefault = isDefault
        self.colorIndex = colorIndex
        self.emoji = emoji
    }
}
