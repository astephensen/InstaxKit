import Foundation
import Network

/// Actor managing TCP socket connection to Instax printers.
public actor SocketConnection {
  private var connection: NWConnection?
  private let host: String
  private let port: UInt16
  private let queue = DispatchQueue(label: "com.instaxkit.socket")

  public init(host: String, port: UInt16 = 8080) {
    self.host = host
    self.port = port
  }

  /// Connect to the printer.
  public func connect(timeout: TimeInterval = 5) async throws {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw ConnectionError.connectionFailed("Invalid port: \(port)")
    }

    let endpoint = NWEndpoint.hostPort(
      host: NWEndpoint.Host(host),
      port: nwPort
    )

    let parameters = NWParameters.tcp
    parameters.prohibitedInterfaceTypes = [.cellular]

    let connection = NWConnection(to: endpoint, using: parameters)
    self.connection = connection

    return try await withCheckedThrowingContinuation { continuation in
      let completionState = CompletionState()

      @Sendable func complete(with result: Result<Void, Error>) {
        guard completionState.tryComplete() else { return }
        continuation.resume(with: result)
      }

      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          complete(with: .success(()))
        case let .failed(error):
          complete(with: .failure(ConnectionError.connectionFailed(error.localizedDescription)))
        case .cancelled:
          complete(with: .failure(ConnectionError.cancelled))
        default:
          break
        }
      }

      connection.start(queue: self.queue)

      // Timeout
      Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        connection.cancel()
        complete(with: .failure(ConnectionError.timeout))
      }
    }
  }

  /// Send data to the printer.
  public func send(_ data: Data) async throws {
    guard let connection else {
      throw ConnectionError.notConnected
    }

    Logger.shared.logPacket("SEND", data: data)

    return try await withCheckedThrowingContinuation { continuation in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error {
          continuation.resume(throwing: ConnectionError.sendFailed(error.localizedDescription))
        } else {
          continuation.resume()
        }
      })
    }
  }

  /// Receive data from the printer.
  public func receive(timeout: TimeInterval = 5) async throws -> Data {
    guard let connection else {
      throw ConnectionError.notConnected
    }

    // First, read the header to get the packet length
    let headerData = try await receiveExact(4, from: connection, timeout: timeout)
    let packetLength = Int((UInt16(headerData[2]) << 8) | UInt16(headerData[3]))

    // Read the rest of the packet
    let remainingLength = packetLength - 4
    guard remainingLength > 0 else {
      return headerData
    }

    let remainingData = try await receiveExact(remainingLength, from: connection, timeout: timeout)
    let fullPacket = headerData + remainingData

    Logger.shared.logPacket("RECV", data: fullPacket)
    return fullPacket
  }

  private func receiveExact(_ length: Int, from connection: NWConnection, timeout: TimeInterval) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let completionState = CompletionState()

      @Sendable func complete(with result: Result<Data, Error>) {
        guard completionState.tryComplete() else { return }
        continuation.resume(with: result)
      }

      connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
        if let error {
          complete(with: .failure(ConnectionError.receiveFailed(error.localizedDescription)))
        } else if let data, data.count >= length {
          complete(with: .success(data))
        } else if let data {
          complete(with: .failure(ConnectionError.incompleteData(expected: length, received: data.count)))
        } else {
          complete(with: .failure(ConnectionError.noData))
        }
      }

      // Timeout
      Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        complete(with: .failure(ConnectionError.timeout))
      }
    }
  }

  /// Close the connection.
  public func close() {
    if let connection {
      switch connection.state {
      case .cancelled, .failed:
        // Already terminated, don't cancel again
        break
      default:
        connection.cancel()
      }
    }
    connection = nil
  }

  /// Check if connected.
  public var isConnected: Bool {
    guard let connection else { return false }
    return connection.state == .ready
  }
}

/// Thread-safe completion state tracker for continuations.
private final class CompletionState: @unchecked Sendable {
  private let lock = NSLock()
  private var didComplete = false

  /// Attempts to mark as complete. Returns true if this is the first call, false otherwise.
  func tryComplete() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !didComplete else { return false }
    didComplete = true
    return true
  }
}

/// Connection errors.
public enum ConnectionError: Error, Sendable, CustomStringConvertible {
  case notConnected
  case connectionFailed(String)
  case sendFailed(String)
  case receiveFailed(String)
  case timeout
  case cancelled
  case noData
  case incompleteData(expected: Int, received: Int)

  public var description: String {
    switch self {
    case .notConnected:
      "Not connected to printer"
    case let .connectionFailed(message):
      "Connection failed: \(message)"
    case let .sendFailed(message):
      "Send failed: \(message)"
    case let .receiveFailed(message):
      "Receive failed: \(message)"
    case .timeout:
      "Operation timed out"
    case .cancelled:
      "Connection cancelled"
    case .noData:
      "No data received"
    case let .incompleteData(expected, received):
      "Incomplete data: expected \(expected) bytes, received \(received)"
    }
  }
}
