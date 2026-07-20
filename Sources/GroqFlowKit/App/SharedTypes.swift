import Foundation

// Foundation contracts. Every module codes against these types.
// Do not modify without updating the implementation plan.

public enum DictationMode: Equatable, Sendable {
    case pushToTalk
    case handsFree
    case command
}

public enum DictationState: Equatable, Sendable {
    case idle
    case recording(DictationMode)
    case processing(DictationMode)
    case inserting
}

public enum HotkeyChoice: String, Codable, CaseIterable, Sendable {
    case rightOption
    case rightCommand
    case fn
    case f5

    public var keyCode: Int64 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .fn: return 63
        case .f5: return 96
        }
    }

    // fn and f5 arrive as different event types than the pure modifiers
    public var isModifier: Bool {
        switch self {
        case .rightOption, .rightCommand, .fn: return true
        case .f5: return false
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .fn: return "fn / Globe"
        case .f5: return "F5"
        }
    }
}

public enum StyleCategory: String, Codable, CaseIterable, Sendable {
    case personalMessaging
    case workMessaging
    case email
    case code
    case other

    public var displayName: String {
        switch self {
        case .personalMessaging: return "Personal Messaging"
        case .workMessaging: return "Work Messaging"
        case .email: return "Email"
        case .code: return "Coding"
        case .other: return "Everything Else"
        }
    }
}

public enum StylePreset: String, Codable, CaseIterable, Sendable {
    case veryCasual
    case casual
    case excited
    case formal

    public var displayName: String {
        switch self {
        case .veryCasual: return "Very Casual"
        case .casual: return "Casual"
        case .excited: return "Excited"
        case .formal: return "Formal"
        }
    }
}

public struct AppContext: Equatable, Sendable {
    public let bundleID: String?
    public let appName: String?
    public let precedingText: String?
    public let category: StyleCategory

    public init(bundleID: String?, appName: String?, precedingText: String?, category: StyleCategory) {
        self.bundleID = bundleID
        self.appName = appName
        self.precedingText = precedingText
        self.category = category
    }

    public static let empty = AppContext(bundleID: nil, appName: nil, precedingText: nil, category: .other)
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var starred: Bool
    public var misspelling: String?

    public init(id: UUID = UUID(), text: String, starred: Bool = false, misspelling: String? = nil) {
        self.id = id
        self.text = text
        self.starred = starred
        self.misspelling = misspelling
    }
}

public struct Snippet: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var trigger: String
    public var body: String

    public init(id: UUID = UUID(), trigger: String, body: String) {
        self.id = id
        self.trigger = trigger
        self.body = body
    }
}

public struct TranscriptRecord: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var date: Date
    public var raw: String
    public var formatted: String
    public var bundleID: String?
    public var appName: String?
    public var durationMs: Int
    public var mode: String    // "pushToTalk" | "handsFree" | "command"
    public var status: String  // "ok" | "failed"

    public init(id: Int64 = 0, date: Date = Date(), raw: String, formatted: String,
                bundleID: String?, appName: String?, durationMs: Int, mode: String, status: String) {
        self.id = id
        self.date = date
        self.raw = raw
        self.formatted = formatted
        self.bundleID = bundleID
        self.appName = appName
        self.durationMs = durationMs
        self.mode = mode
        self.status = status
    }
}
