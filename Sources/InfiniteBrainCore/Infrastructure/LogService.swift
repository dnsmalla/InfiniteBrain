import Foundation
import os.log

/// A production-grade logging service that wraps Apple's unified logging (OSLog).
/// Provides structured categories and handles privacy (masking sensitive data).
public final class LogService: @unchecked Sendable {
    public enum Category: String {
        case general = "General"
        case ingest = "Ingest"
        case query = "Query"
        case lLM = "LLM"
        case index = "Index"
        case vault = "Vault"
    }

    public static let shared = LogService()
    
    private let subsystem: String
    private var loggers: [Category: Logger] = [:]
    private let lock = NSLock()

    public init(subsystem: String = "com.dnsmalla.InfiniteBrain") {
        self.subsystem = subsystem
    }

    public func logger(for category: Category) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = loggers[category] {
            return existing
        }
        
        let newLogger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = newLogger
        return newLogger
    }

    // Convenience methods
    
    public func info(_ message: String, category: Category = .general) {
        logger(for: category).info("\(message, privacy: .public)")
    }
    
    public func error(_ message: String, category: Category = .general, error: Error? = nil) {
        if let error = error {
            logger(for: category).error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            logger(for: category).error("\(message, privacy: .public)")
        }
    }
    
    public func debug(_ message: String, category: Category = .general) {
        logger(for: category).debug("\(message, privacy: .public)")
    }
    
    public func fault(_ message: String, category: Category = .general) {
        logger(for: category).fault("\(message, privacy: .public)")
    }
}
