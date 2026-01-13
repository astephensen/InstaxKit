import Foundation

/// Header information common to all packets.
public struct PacketHeader: Sendable {
  public let mode: PacketMode
  public let type: PacketType
  public let length: UInt16
  public let sessionTime: UInt32

  // Command-specific fields
  public let pinCode: UInt16?

  // Response-specific fields
  public let returnCode: ResponseCode?
  public let ejecting: Bool
  public let battery: Int
  public let printsRemaining: Int

  public init(
    mode: PacketMode,
    type: PacketType,
    length: UInt16,
    sessionTime: UInt32,
    pinCode: UInt16? = nil,
    returnCode: ResponseCode? = nil,
    ejecting: Bool = false,
    battery: Int = 0,
    printsRemaining: Int = 0
  ) {
    self.mode = mode
    self.type = type
    self.length = length
    self.sessionTime = sessionTime
    self.pinCode = pinCode
    self.returnCode = returnCode
    self.ejecting = ejecting
    self.battery = battery
    self.printsRemaining = printsRemaining
  }
}

/// Protocol for all Instax packet payloads.
public protocol PacketPayload: Sendable {
  static var packetType: PacketType { get }
  func encode() -> Data
  static func decode(from data: Data, mode: PacketMode) throws -> Self
}

/// Empty payload for commands with no payload.
public struct EmptyPayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .reset

  public init() {}

  public func encode() -> Data { Data() }

  public static func decode(from data: Data, mode: PacketMode) throws -> EmptyPayload {
    EmptyPayload()
  }
}

/// Specifications response payload.
public struct SpecificationsPayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .specifications

  public let maxWidth: UInt16
  public let maxHeight: UInt16
  public let maxColors: UInt16
  public let maxMessageSize: UInt16

  public init(
    maxWidth: UInt16 = 600,
    maxHeight: UInt16 = 800,
    maxColors: UInt16 = 256,
    maxMessageSize: UInt16 = 60000
  ) {
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.maxColors = maxColors
    self.maxMessageSize = maxMessageSize
  }

  public func encode() -> Data {
    var data = Data()
    data.appendUInt16(maxWidth)
    data.appendUInt16(maxHeight)
    data.appendUInt16(maxColors)
    data.appendUInt16(0) // unknown1
    data.append(contentsOf: [0, 0, 0, 0]) // padding
    data.appendUInt16(maxMessageSize)
    data.append(0) // unknown2
    data.append(0) // padding
    data.appendUInt32(0) // unknown3
    data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // padding
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> SpecificationsPayload {
    guard data.count >= 8 else { throw PacketError.invalidPayload }
    return SpecificationsPayload(
      maxWidth: data.uint16(at: 0),
      maxHeight: data.uint16(at: 2),
      maxColors: data.uint16(at: 4),
      maxMessageSize: data.uint16(at: 12)
    )
  }
}

/// Version response payload.
public struct VersionPayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .printerVersion

  public let firmware: String
  public let hardware: String

  public init(firmware: String = "01.00", hardware: String = "01.00") {
    self.firmware = firmware
    self.hardware = hardware
  }

  public func encode() -> Data {
    var data = Data()
    data.appendUInt16(0) // unknown1
    data.appendUInt16(encodeVersion(firmware))
    data.appendUInt16(encodeVersion(hardware))
    data.append(contentsOf: [0, 0]) // padding
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> VersionPayload {
    guard data.count >= 6 else { throw PacketError.invalidPayload }
    let firmwareRaw = data.uint16(at: 2)
    let hardwareRaw = data.uint16(at: 4)
    return VersionPayload(
      firmware: formatVersion(firmwareRaw),
      hardware: formatVersion(hardwareRaw)
    )
  }

  private static func formatVersion(_ version: UInt16) -> String {
    let major = (version >> 8) & 0xFF
    let minor = version & 0xFF
    return String(format: "%02X.%02X", major, minor)
  }

  private func encodeVersion(_ version: String) -> UInt16 {
    let parts = version.split(separator: ".")
    guard parts.count == 2,
          let major = UInt16(parts[0], radix: 16),
          let minor = UInt16(parts[1], radix: 16)
    else {
      return 0x0100
    }
    return (major << 8) | minor
  }
}

/// Print count response payload.
public struct PrintCountPayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .printCount

  public let printHistory: UInt32

  public init(printHistory: UInt32 = 0) {
    self.printHistory = printHistory
  }

  public func encode() -> Data {
    var data = Data()
    data.appendUInt32(printHistory)
    data.append(contentsOf: [UInt8](repeating: 0, count: 12))
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> PrintCountPayload {
    guard data.count >= 4 else { throw PacketError.invalidPayload }
    return PrintCountPayload(printHistory: data.uint32(at: 0))
  }
}

/// Model name response payload.
public struct ModelNamePayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .modelName

  public let modelName: String

  public init(modelName: String = "SP-2") {
    self.modelName = modelName
  }

  public func encode() -> Data {
    var data = Data()
    let nameBytes = modelName.utf8.prefix(4)
    data.append(contentsOf: nameBytes)
    // Pad to 4 bytes
    while data.count < 4 {
      data.append(0)
    }
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> ModelNamePayload {
    guard data.count >= 4 else { throw PacketError.invalidPayload }
    let nameData = data.prefix(4)
    let name = String(data: Data(nameData), encoding: .ascii) ?? "????"
    return ModelNamePayload(modelName: name.trimmingCharacters(in: .init(charactersIn: "\0")))
  }
}

/// Pre-print command payload.
public struct PrePrintPayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .prePrint

  public let commandNumber: UInt16
  public let responseNumber: UInt16

  public init(commandNumber: UInt16, responseNumber: UInt16 = 0) {
    self.commandNumber = commandNumber
    self.responseNumber = responseNumber
  }

  public func encode() -> Data {
    var data = Data()
    data.append(contentsOf: [0, 0]) // padding
    data.appendUInt16(commandNumber)
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> PrePrintPayload {
    if mode == .command {
      guard data.count >= 4 else { throw PacketError.invalidPayload }
      return PrePrintPayload(commandNumber: data.uint16(at: 2))
    } else {
      guard data.count >= 4 else { throw PacketError.invalidPayload }
      return PrePrintPayload(
        commandNumber: data.uint16(at: 0),
        responseNumber: data.uint16(at: 2)
      )
    }
  }
}

/// Printer lock command payload.
public struct LockPayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .lockDevice

  public let lockState: UInt8

  public init(lockState: UInt8) {
    self.lockState = lockState
  }

  public func encode() -> Data {
    var data = Data()
    data.append(lockState)
    data.append(contentsOf: [0, 0, 0]) // padding
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> LockPayload {
    guard !data.isEmpty else { throw PacketError.invalidPayload }
    return LockPayload(lockState: data[0])
  }
}

/// Prep image command payload.
public struct PrepImagePayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .prepImage

  public let format: UInt8
  public let options: UInt8
  public let imageLength: UInt32
  public let maxLength: UInt16

  public init(format: UInt8 = 16, options: UInt8 = 0, imageLength: UInt32, maxLength: UInt16 = 60000) {
    self.format = format
    self.options = options
    self.imageLength = imageLength
    self.maxLength = maxLength
  }

  public func encode() -> Data {
    var data = Data()
    data.append(format)
    data.append(options)
    data.appendUInt32(imageLength)
    data.append(contentsOf: [0, 0, 0, 0, 0, 0]) // padding
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> PrepImagePayload {
    if mode == .command {
      guard data.count >= 6 else { throw PacketError.invalidPayload }
      return PrepImagePayload(
        format: data[0],
        options: data[1],
        imageLength: data.uint32(at: 2)
      )
    } else {
      guard data.count >= 4 else { throw PacketError.invalidPayload }
      return PrepImagePayload(
        imageLength: 0,
        maxLength: data.uint16(at: 2)
      )
    }
  }
}

/// Send image command payload.
public struct SendImagePayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .sendImage

  public let sequenceNumber: UInt32
  public let imageData: Data

  public init(sequenceNumber: UInt32, imageData: Data = Data()) {
    self.sequenceNumber = sequenceNumber
    self.imageData = imageData
  }

  public func encode() -> Data {
    var data = Data()
    data.appendUInt32(sequenceNumber)
    data.append(imageData)
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> SendImagePayload {
    if mode == .command {
      guard data.count >= 4 else { throw PacketError.invalidPayload }
      let seq = data.uint32(at: 0)
      let imageData = data.count > 4 ? Data(data.dropFirst(4)) : Data()
      return SendImagePayload(sequenceNumber: seq, imageData: imageData)
    } else {
      guard data.count >= 4 else { throw PacketError.invalidPayload }
      return SendImagePayload(sequenceNumber: UInt32(data[3]))
    }
  }
}

/// Lock state response payload.
public struct LockStatePayload: PacketPayload, Sendable {
  public static let packetType: PacketType = .setLockState

  public let value: UInt32

  public init(value: UInt32 = 0) {
    self.value = value
  }

  public func encode() -> Data {
    var data = Data()
    data.appendUInt32(value)
    return data
  }

  public static func decode(from data: Data, mode: PacketMode) throws -> LockStatePayload {
    guard data.count >= 4 else { throw PacketError.invalidPayload }
    return LockStatePayload(value: data.uint32(at: 0))
  }
}

/// Packet encoding/decoding errors.
public enum PacketError: Error, Sendable {
  case invalidLength
  case invalidChecksum
  case invalidEndBytes
  case invalidPayload
  case unknownPacketType
}

// MARK: - Data Extensions for Binary Operations

extension Data {
  func uint16(at offset: Int) -> UInt16 {
    guard count >= offset + 2 else { return 0 }
    return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
  }

  func uint32(at offset: Int) -> UInt32 {
    guard count >= offset + 4 else { return 0 }
    return (UInt32(self[offset]) << 24) |
      (UInt32(self[offset + 1]) << 16) |
      (UInt32(self[offset + 2]) << 8) |
      UInt32(self[offset + 3])
  }

  mutating func appendUInt16(_ value: UInt16) {
    append(UInt8((value >> 8) & 0xFF))
    append(UInt8(value & 0xFF))
  }

  mutating func appendUInt32(_ value: UInt32) {
    append(UInt8((value >> 24) & 0xFF))
    append(UInt8((value >> 16) & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
    append(UInt8(value & 0xFF))
  }
}
