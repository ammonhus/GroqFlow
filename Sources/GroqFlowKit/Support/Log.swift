import os

public enum Log {
    public static let app = Logger(subsystem: "com.ammon.groqflow", category: "app")
    public static let hotkey = Logger(subsystem: "com.ammon.groqflow", category: "hotkey")
    public static let audio = Logger(subsystem: "com.ammon.groqflow", category: "audio")
    public static let groq = Logger(subsystem: "com.ammon.groqflow", category: "groq")
}
