import OSLog

/// App-wide loggers. Never interpolate user data (URLs, IDs, names) without `privacy: .private`.
enum Log {
    private static let subsystem = "br.com.casareel.app"

    static let bootstrap = Logger(subsystem: subsystem, category: "bootstrap")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
}
