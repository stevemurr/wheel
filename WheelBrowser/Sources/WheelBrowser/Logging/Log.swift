import Foundation
import os.log

// MARK: - Log Level

public enum LogLevel: Int, Comparable, CustomStringConvertible {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

// MARK: - Log Entry

public struct LogEntry {
    public let timestamp: Date
    public let level: LogLevel
    public let category: Log.Category
    public let message: String

    public init(level: LogLevel, category: Log.Category, message: String) {
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
    }
}

// MARK: - Log Sink Protocol

public protocol LogSink: AnyObject {
    /// Minimum level this sink will process
    var minimumLevel: LogLevel { get set }

    /// Process a log entry
    func log(_ entry: LogEntry)
}

// MARK: - Console Sink

public final class ConsoleSink: LogSink {
    public var minimumLevel: LogLevel
    public var showTimestamp: Bool
    public var useEmoji: Bool

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public init(minimumLevel: LogLevel = .debug, showTimestamp: Bool = true, useEmoji: Bool = true) {
        self.minimumLevel = minimumLevel
        self.showTimestamp = showTimestamp
        self.useEmoji = useEmoji
    }

    public func log(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }

        var parts: [String] = []

        if showTimestamp {
            parts.append(dateFormatter.string(from: entry.timestamp))
        }

        if useEmoji {
            parts.append(levelEmoji(entry.level))
        } else {
            parts.append("[\(entry.level)]")
        }

        parts.append("[\(entry.category.rawValue)]")
        parts.append(entry.message)

        print(parts.joined(separator: " "))
    }

    private func levelEmoji(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

// MARK: - OS Log Sink

public final class OSLogSink: LogSink {
    public var minimumLevel: LogLevel

    private let subsystem: String
    private var loggers: [Log.Category: Logger] = [:]
    private let lock = NSLock()

    public init(subsystem: String = "com.wheel.browser", minimumLevel: LogLevel = .debug) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
    }

    public func log(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }

        let logger = getLogger(for: entry.category)
        let message = "[\(entry.category.rawValue)] \(entry.message)"

        switch entry.level {
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }
    }

    private func getLogger(for category: Log.Category) -> Logger {
        lock.lock()
        defer { lock.unlock() }

        if let existing = loggers[category] {
            return existing
        }

        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = logger
        return logger
    }
}

// MARK: - File Sink

public final class FileSink: LogSink {
    public var minimumLevel: LogLevel

    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let lock = NSLock()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    public init?(path: String, minimumLevel: LogLevel = .debug) {
        self.minimumLevel = minimumLevel
        self.fileURL = URL(fileURLWithPath: path)

        // Create file if needed
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        do {
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
        } catch {
            return nil
        }
    }

    deinit {
        try? fileHandle?.close()
    }

    public func log(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }

        let line = "\(dateFormatter.string(from: entry.timestamp)) [\(entry.level)] [\(entry.category.rawValue)] \(entry.message)\n"

        lock.lock()
        defer { lock.unlock() }

        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}

// MARK: - Log (Main Interface)

public enum Log {
    // MARK: - Categories

    public enum Category: String {
        case agent = "Agent"
        case adBlock = "AdBlock"
        case browser = "Browser"
        case chat = "Chat"
        case darkMode = "DarkMode"
        case downloads = "Downloads"
        case history = "History"
        case linkPreview = "LinkPreview"
        case mcp = "MCP"
        case newTabPage = "NewTabPage"
        case omniBar = "OmniBar"
        case overlay = "Overlay"
        case screenshot = "Screenshot"
        case search = "SemanticSearch"
        case settings = "Settings"
        case services = "Services"
        case tabs = "Tabs"
        case widgets = "Widgets"
        case workspace = "Workspace"
    }

    // MARK: - Sink Management

    private static var sinks: [LogSink] = []
    private static let lock = NSLock()

    public static func addSink(_ sink: LogSink) {
        lock.lock()
        defer { lock.unlock() }
        sinks.append(sink)
    }

    public static func removeSink(_ sink: LogSink) {
        lock.lock()
        defer { lock.unlock() }
        sinks.removeAll { $0 === sink }
    }

    public static func removeAllSinks() {
        lock.lock()
        defer { lock.unlock() }
        sinks.removeAll()
    }

    // MARK: - Logging Methods

    private static func dispatch(_ entry: LogEntry) {
        lock.lock()
        let currentSinks = sinks
        lock.unlock()

        for sink in currentSinks {
            sink.log(entry)
        }
    }

    public static func debug(_ message: String, category: Category) {
        dispatch(LogEntry(level: .debug, category: category, message: message))
    }

    public static func info(_ message: String, category: Category) {
        dispatch(LogEntry(level: .info, category: category, message: message))
    }

    public static func warning(_ message: String, category: Category) {
        dispatch(LogEntry(level: .warning, category: category, message: message))
    }

    public static func error(_ message: String, category: Category) {
        dispatch(LogEntry(level: .error, category: category, message: message))
    }

    public static func error(_ message: String, error: Error, category: Category) {
        dispatch(LogEntry(level: .error, category: category, message: "\(message): \(error.localizedDescription)"))
    }

    // MARK: - Convenience (Category-specific)

    public enum Agent {
        public static func debug(_ message: String) { Log.debug(message, category: .agent) }
        public static func info(_ message: String) { Log.info(message, category: .agent) }
        public static func warning(_ message: String) { Log.warning(message, category: .agent) }
        public static func error(_ message: String) { Log.error(message, category: .agent) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .agent) }
    }

    public enum AdBlock {
        public static func debug(_ message: String) { Log.debug(message, category: .adBlock) }
        public static func info(_ message: String) { Log.info(message, category: .adBlock) }
        public static func warning(_ message: String) { Log.warning(message, category: .adBlock) }
        public static func error(_ message: String) { Log.error(message, category: .adBlock) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .adBlock) }
    }

    public enum Browser {
        public static func debug(_ message: String) { Log.debug(message, category: .browser) }
        public static func info(_ message: String) { Log.info(message, category: .browser) }
        public static func warning(_ message: String) { Log.warning(message, category: .browser) }
        public static func error(_ message: String) { Log.error(message, category: .browser) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .browser) }
    }

    public enum Chat {
        public static func debug(_ message: String) { Log.debug(message, category: .chat) }
        public static func info(_ message: String) { Log.info(message, category: .chat) }
        public static func warning(_ message: String) { Log.warning(message, category: .chat) }
        public static func error(_ message: String) { Log.error(message, category: .chat) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .chat) }
    }

    public enum DarkMode {
        public static func debug(_ message: String) { Log.debug(message, category: .darkMode) }
        public static func info(_ message: String) { Log.info(message, category: .darkMode) }
        public static func warning(_ message: String) { Log.warning(message, category: .darkMode) }
        public static func error(_ message: String) { Log.error(message, category: .darkMode) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .darkMode) }
    }

    public enum Downloads {
        public static func debug(_ message: String) { Log.debug(message, category: .downloads) }
        public static func info(_ message: String) { Log.info(message, category: .downloads) }
        public static func warning(_ message: String) { Log.warning(message, category: .downloads) }
        public static func error(_ message: String) { Log.error(message, category: .downloads) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .downloads) }
    }

    public enum History {
        public static func debug(_ message: String) { Log.debug(message, category: .history) }
        public static func info(_ message: String) { Log.info(message, category: .history) }
        public static func warning(_ message: String) { Log.warning(message, category: .history) }
        public static func error(_ message: String) { Log.error(message, category: .history) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .history) }
    }

    public enum LinkPreview {
        public static func debug(_ message: String) { Log.debug(message, category: .linkPreview) }
        public static func info(_ message: String) { Log.info(message, category: .linkPreview) }
        public static func warning(_ message: String) { Log.warning(message, category: .linkPreview) }
        public static func error(_ message: String) { Log.error(message, category: .linkPreview) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .linkPreview) }
    }

    public enum MCP {
        public static func debug(_ message: String) { Log.debug(message, category: .mcp) }
        public static func info(_ message: String) { Log.info(message, category: .mcp) }
        public static func warning(_ message: String) { Log.warning(message, category: .mcp) }
        public static func error(_ message: String) { Log.error(message, category: .mcp) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .mcp) }
    }

    public enum NewTabPage {
        public static func debug(_ message: String) { Log.debug(message, category: .newTabPage) }
        public static func info(_ message: String) { Log.info(message, category: .newTabPage) }
        public static func warning(_ message: String) { Log.warning(message, category: .newTabPage) }
        public static func error(_ message: String) { Log.error(message, category: .newTabPage) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .newTabPage) }
    }

    public enum OmniBar {
        public static func debug(_ message: String) { Log.debug(message, category: .omniBar) }
        public static func info(_ message: String) { Log.info(message, category: .omniBar) }
        public static func warning(_ message: String) { Log.warning(message, category: .omniBar) }
        public static func error(_ message: String) { Log.error(message, category: .omniBar) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .omniBar) }
    }

    public enum Overlay {
        public static func debug(_ message: String) { Log.debug(message, category: .overlay) }
        public static func info(_ message: String) { Log.info(message, category: .overlay) }
        public static func warning(_ message: String) { Log.warning(message, category: .overlay) }
        public static func error(_ message: String) { Log.error(message, category: .overlay) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .overlay) }
    }

    public enum Screenshot {
        public static func debug(_ message: String) { Log.debug(message, category: .screenshot) }
        public static func info(_ message: String) { Log.info(message, category: .screenshot) }
        public static func warning(_ message: String) { Log.warning(message, category: .screenshot) }
        public static func error(_ message: String) { Log.error(message, category: .screenshot) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .screenshot) }
    }

    public enum Search {
        public static func debug(_ message: String) { Log.debug(message, category: .search) }
        public static func info(_ message: String) { Log.info(message, category: .search) }
        public static func warning(_ message: String) { Log.warning(message, category: .search) }
        public static func error(_ message: String) { Log.error(message, category: .search) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .search) }
    }

    public enum Settings {
        public static func debug(_ message: String) { Log.debug(message, category: .settings) }
        public static func info(_ message: String) { Log.info(message, category: .settings) }
        public static func warning(_ message: String) { Log.warning(message, category: .settings) }
        public static func error(_ message: String) { Log.error(message, category: .settings) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .settings) }
    }

    public enum Services {
        public static func debug(_ message: String) { Log.debug(message, category: .services) }
        public static func info(_ message: String) { Log.info(message, category: .services) }
        public static func warning(_ message: String) { Log.warning(message, category: .services) }
        public static func error(_ message: String) { Log.error(message, category: .services) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .services) }
    }

    public enum Tabs {
        public static func debug(_ message: String) { Log.debug(message, category: .tabs) }
        public static func info(_ message: String) { Log.info(message, category: .tabs) }
        public static func warning(_ message: String) { Log.warning(message, category: .tabs) }
        public static func error(_ message: String) { Log.error(message, category: .tabs) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .tabs) }
    }

    public enum Widgets {
        public static func debug(_ message: String) { Log.debug(message, category: .widgets) }
        public static func info(_ message: String) { Log.info(message, category: .widgets) }
        public static func warning(_ message: String) { Log.warning(message, category: .widgets) }
        public static func error(_ message: String) { Log.error(message, category: .widgets) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .widgets) }
    }

    public enum Workspace {
        public static func debug(_ message: String) { Log.debug(message, category: .workspace) }
        public static func info(_ message: String) { Log.info(message, category: .workspace) }
        public static func warning(_ message: String) { Log.warning(message, category: .workspace) }
        public static func error(_ message: String) { Log.error(message, category: .workspace) }
        public static func error(_ message: String, error: Error) { Log.error(message, error: error, category: .workspace) }
    }
}
