import Foundation

/// Decodes packets received from Instax printers.
public struct PacketDecoder: Sendable {
  public init() {}

  /// Decode a packet from raw bytes.
  public func decode(_ data: Data) throws -> DecodedPacket {
    guard data.count >= 16 else {
      throw PacketError.invalidLength
    }

    // Decode header
    let mode = PacketMode(rawValue: data[0]) ?? .response
    guard let type = PacketType(rawValue: data[1]) else {
      throw PacketError.unknownPacketType
    }

    let length = data.uint16(at: 2)
    let sessionTime = data.uint32(at: 4)

    guard data.count >= length else {
      throw PacketError.invalidLength
    }

    // Validate checksum and end bytes
    try validatePacket(data, length: Int(length))

    let header: PacketHeader
    let payloadOffset: Int
    let payloadLength: Int

    if mode == .command {
      let pinCode = data.uint16(at: 8)
      header = PacketHeader(
        mode: mode,
        type: type,
        length: length,
        sessionTime: sessionTime,
        pinCode: pinCode
      )
      payloadOffset = 12
      payloadLength = Int(length) - 16
    } else {
      let returnCode = ResponseCode(rawValue: data[12])
      let ejecting = (data[14] >> 2) != 0
      let battery = Int((data[15] >> 4) & 0x07)
      let printsRemaining = Int(data[15] & 0x0F)

      header = PacketHeader(
        mode: mode,
        type: type,
        length: length,
        sessionTime: sessionTime,
        returnCode: returnCode,
        ejecting: ejecting,
        battery: battery,
        printsRemaining: printsRemaining
      )
      payloadOffset = 16
      payloadLength = Int(length) - 20
    }

    let payload = if payloadLength > 0, data.count > payloadOffset {
      Data(data[payloadOffset ..< (payloadOffset + payloadLength)])
    } else {
      Data()
    }

    return DecodedPacket(header: header, payload: payload)
  }

  private func validatePacket(_ data: Data, length: Int) throws {
    guard data.count >= length else {
      throw PacketError.invalidLength
    }

    // Check end bytes (CR LF)
    let checksumIndex = length - 4
    guard data[checksumIndex + 2] == 0x0D, data[checksumIndex + 3] == 0x0A else {
      throw PacketError.invalidEndBytes
    }

    // Validate checksum
    var sum = 0
    for i in 0 ..< checksumIndex {
      sum += Int(data[i])
    }

    let storedChecksum = (Int(data[checksumIndex]) << 8) | Int(data[checksumIndex + 1])
    let expectedResult = (sum + storedChecksum) & 0xFFFF

    guard expectedResult == 0xFFFF else {
      throw PacketError.invalidChecksum
    }
  }
}

/// A decoded packet with header and raw payload.
public struct DecodedPacket: Sendable {
  public let header: PacketHeader
  public let payload: Data

  public init(header: PacketHeader, payload: Data) {
    self.header = header
    self.payload = payload
  }

  /// Decode the payload as a specific type.
  public func decodePayload<T: PacketPayload>(_ type: T.Type) throws -> T {
    try T.decode(from: payload, mode: header.mode)
  }
}
