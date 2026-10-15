import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case unread, reading, read

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unread: "待读"
        case .reading: "在读"
        case .read: "已读"
        }
    }

    var systemImage: String {
        switch self {
        case .unread: "tray"
        case .reading: "book"
        case .read: "checkmark.circle"
        }
    }
}
