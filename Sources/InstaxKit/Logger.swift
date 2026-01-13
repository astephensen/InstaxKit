import Foundation

/// Simple logger for debugging Instax communication.
public final class Logger: @unchecked Sendable {
  public static let shared = Logger()

  public var isEnabled: Bool = false

  private let lock = NSLock()

  private init() {}

  public func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    guard isEnabled else { return }
    lock.lock()
    defer { lock.unlock() }

    let filename = (file as NSString).lastPathComponent
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] [\(filename):\(line)] \(message)")
    fflush(stdout)
  }

  public func logPacket(_ label: String, data: Data) {
    guard isEnabled else { return }
    lock.lock()
    defer { lock.unlock() }

    let hex = data.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
    let truncated = data.count > 64 ? "... (\(data.count) bytes total)" : ""
    print("[PACKET] \(label): \(hex)\(truncated)")
    fflush(stdout)
  }
}

/// Convenience function for logging.
public func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
  Logger.shared.log(message, file: file, function: function, line: line)
}
