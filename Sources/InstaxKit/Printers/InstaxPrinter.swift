import CoreGraphics
import Foundation

/// Unified Instax printer interface supporting SP-1, SP-2, and SP-3 models.
public actor InstaxPrinter {
  public let model: PrinterModel
  public let host: String
  public let port: UInt16
  public let pinCode: UInt16
  public let connectionTimeout: TimeInterval

  private let base: InstaxPrinterBase
  private let imageEncoder: InstaxImageEncoder

  public init(
    model: PrinterModel,
    host: String = "192.168.0.251",
    port: UInt16 = 8080,
    pinCode: UInt16 = 1111,
    connectionTimeout: TimeInterval = 5
  ) {
    self.model = model
    self.host = host
    self.port = port
    self.pinCode = pinCode
    self.connectionTimeout = connectionTimeout
    base = InstaxPrinterBase(
      model: model,
      host: host,
      port: port,
      pinCode: pinCode,
      connectionTimeout: connectionTimeout
    )
    imageEncoder = InstaxImageEncoder(model: model)
  }

  /// Get printer information.
  public func getInfo() async throws -> PrinterInfo {
    try await base.getInfo()
  }

  /// Print a CGImage.
  ///
  /// The image must be exactly the right size for the printer model:
  /// - SP-1: 480×640
  /// - SP-2: 600×800
  /// - SP-3: 800×800
  public func print(image: CGImage, progress: @escaping @Sendable (PrintProgress) -> Void) async throws {
    let encodedData = try imageEncoder.encode(image: image)
    try await base.printImage(encodedData: encodedData, progress: progress)
  }

  /// Print from raw encoded bytes.
  public func print(encodedImage: Data, progress: @escaping @Sendable (PrintProgress) -> Void) async throws {
    try await base.printImage(encodedData: encodedImage, progress: progress)
  }
}

/// Base implementation shared between printer models.
/// This is a class (not actor) because it's only accessed from within InstaxPrinter actor.
final class InstaxPrinterBase: @unchecked Sendable {
  let model: PrinterModel
  let host: String
  let port: UInt16
  let pinCode: UInt16
  let connectionTimeout: TimeInterval

  private let encoder = PacketEncoder()
  private let decoder = PacketDecoder()
  private var connection: SocketConnection?
  private var sessionTime: UInt32

  init(model: PrinterModel, host: String, port: UInt16, pinCode: UInt16, connectionTimeout: TimeInterval = 5) {
    self.model = model
    self.host = host
    self.port = port
    self.pinCode = pinCode
    self.connectionTimeout = connectionTimeout
    // Truncate to UInt32 range (the & 0xFFFFFFFF must happen before conversion)
    let timeMs = UInt64(Date().timeIntervalSince1970 * 1000)
    sessionTime = UInt32(timeMs & 0xFFFF_FFFF)
  }

  func connect() async throws {
    let conn = SocketConnection(host: host, port: port)
    try await conn.connect(timeout: connectionTimeout)
    connection = conn
  }

  func close() async {
    await connection?.close()
    connection = nil
  }

  func sendCommand(type: PacketType, payload: Data = Data()) async throws -> DecodedPacket {
    guard let connection else {
      throw ConnectionError.notConnected
    }

    let commandData = encoder.encodeCommand(
      type: type,
      sessionTime: sessionTime,
      pinCode: pinCode,
      payload: payload
    )

    try await connection.send(commandData)
    let responseData = try await connection.receive()
    return try decoder.decode(responseData)
  }

  func getPrinterVersion() async throws -> DecodedPacket {
    try await sendCommand(type: .printerVersion)
  }

  func getModelName() async throws -> DecodedPacket {
    try await sendCommand(type: .modelName)
  }

  func getPrintCount() async throws -> DecodedPacket {
    try await sendCommand(type: .printCount)
  }

  func getSpecifications() async throws -> DecodedPacket {
    try await sendCommand(type: .specifications)
  }

  func sendPrePrint(number: UInt16) async throws -> DecodedPacket {
    let payload = PrePrintPayload(commandNumber: number)
    return try await sendCommand(type: .prePrint, payload: payload.encode())
  }

  func sendLock(state: UInt8) async throws -> DecodedPacket {
    let payload = LockPayload(lockState: state)
    return try await sendCommand(type: .lockDevice, payload: payload.encode())
  }

  func sendReset() async throws -> DecodedPacket {
    try await sendCommand(type: .reset)
  }

  func sendPrepImage(length: UInt32) async throws -> DecodedPacket {
    let payload = PrepImagePayload(imageLength: length)
    return try await sendCommand(type: .prepImage, payload: payload.encode())
  }

  func sendImageSegment(sequence: UInt32, data: Data) async throws -> DecodedPacket {
    let payload = SendImagePayload(sequenceNumber: sequence, imageData: data)
    return try await sendCommand(type: .sendImage, payload: payload.encode())
  }

  func sendType83() async throws -> DecodedPacket {
    try await sendCommand(type: .type83)
  }

  func sendType195() async throws -> DecodedPacket {
    try await sendCommand(type: .type195)
  }

  func sendLockState() async throws -> DecodedPacket {
    try await sendCommand(type: .setLockState)
  }

  func getInfo() async throws -> PrinterInfo {
    debugLog("Getting printer info...")
    try await connect()

    defer {
      Task { await close() }
    }

    let version = try await getPrinterVersion()
    let modelName = try await getModelName()
    let specs = try await getSpecifications()
    let printCount = try await getPrintCount()

    let versionPayload = try version.decodePayload(VersionPayload.self)
    let modelPayload = try modelName.decodePayload(ModelNamePayload.self)
    let specsPayload = try specs.decodePayload(SpecificationsPayload.self)
    let countPayload = try printCount.decodePayload(PrintCountPayload.self)

    return PrinterInfo(
      modelName: modelPayload.modelName,
      firmware: versionPayload.firmware,
      hardware: versionPayload.hardware,
      battery: version.header.battery,
      printsRemaining: version.header.printsRemaining,
      totalPrints: countPayload.printHistory,
      maxWidth: specsPayload.maxWidth,
      maxHeight: specsPayload.maxHeight
    )
  }

  func printImage(encodedData: Data, progress: @escaping @Sendable (PrintProgress) -> Void) async throws {
    let segmentSize = model.segmentSize
    let totalSegments = (encodedData.count + segmentSize - 1) / segmentSize // Ceiling division

    // Phase 1: Send pre-print commands
    progress(PrintProgress(stage: .connecting, percentage: 0, message: "Connecting to printer..."))
    try await connect()

    progress(PrintProgress(stage: .sendingPrePrint, percentage: 10, message: "Sending pre-print commands..."))
    for i in 1 ... 8 {
      _ = try await sendPrePrint(number: UInt16(i))
    }
    await close()

    // Phase 2: Lock printer
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await connect()
    progress(PrintProgress(stage: .locking, percentage: 20, message: "Locking printer..."))
    _ = try await sendLock(state: 1)
    await close()

    // Phase 3: Reset printer
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await connect()
    progress(PrintProgress(stage: .resetting, percentage: 30, message: "Resetting printer..."))
    _ = try await sendReset()
    await close()

    // Phase 4: Send image
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await connect()
    progress(PrintProgress(stage: .preparingImage, percentage: 40, message: "Preparing image..."))
    _ = try await sendPrepImage(length: UInt32(encodedData.count))

    for segment in 0 ..< totalSegments {
      let start = segment * segmentSize
      let end = min(start + segmentSize, encodedData.count)
      let segmentData = encodedData[start ..< end]

      let percentage = 40 + (segment * 30 / totalSegments)
      progress(PrintProgress(
        stage: .sendingImage(segment: segment + 1, total: totalSegments),
        percentage: percentage,
        message: "Sending image segment \(segment + 1)/\(totalSegments)..."
      ))

      _ = try await sendImageSegment(sequence: UInt32(segment), data: Data(segmentData))
    }

    progress(PrintProgress(stage: .initiatingPrint, percentage: 70, message: "Initiating print..."))
    _ = try await sendType83()
    await close()

    // Phase 5: Wait for print to complete
    // The printer may close connections or refuse them while actively printing.
    // This is normal behavior, so we handle connection errors gracefully here.
    progress(PrintProgress(stage: .waitingForPrint, percentage: 90, message: "Waiting for print..."))

    do {
      try await Task.sleep(nanoseconds: 1_000_000_000)
      try await connect()
      _ = try await sendLockState()
      _ = try await getPrinterVersion()
      _ = try await getModelName()

      let success = try await waitForPrintComplete(timeout: 30)
      await close()

      if !success {
        progress(PrintProgress(stage: .error("Timed out"), percentage: 100, message: "Print timed out"))
        throw PrintError.timeout
      }
    } catch is ConnectionError {
      // Connection errors after print initiation are normal - printer is busy printing
      await close()
    }

    progress(PrintProgress(stage: .complete, percentage: 100, message: "Print complete!"))
  }

  private func waitForPrintComplete(timeout: Int) async throws -> Bool {
    for _ in 0 ..< timeout {
      do {
        let status = try await sendType195()
        if status.header.returnCode == .ready {
          return true
        }
      } catch {
        // Connection errors during polling are normal - printer closes connection when done
        return true
      }
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    return false
  }
}

/// Print-related errors.
public enum PrintError: Error, Sendable {
  case timeout
  case printerError(ResponseCode)
  case encodingFailed
}
