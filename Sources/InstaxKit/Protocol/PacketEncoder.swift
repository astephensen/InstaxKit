import Foundation

/// Encodes packets for transmission to Instax printers.
public struct PacketEncoder: Sendable {
  public init() {}

  /// Encode a command packet.
  public func encodeCommand(
    type: PacketType,
    sessionTime: UInt32,
    pinCode: UInt16,
    payload: Data = Data()
  ) -> Data {
    let payloadLength = 16 + payload.count
    var packet = Data()

    // Header
    packet.append(PacketMode.command.rawValue)
    packet.append(type.rawValue)
    packet.appendUInt16(UInt16(payloadLength))
    packet.appendUInt32(sessionTime)
    packet.appendUInt16(pinCode)
    packet.append(0) // padding
    packet.append(0) // padding

    // Payload
    packet.append(payload)

    // Checksum and end bytes
    let checksum = calculateChecksum(packet)
    packet.append(UInt8((checksum >> 8) & 0xFF))
    packet.append(UInt8(checksum & 0xFF))
    packet.append(0x0D) // CR
    packet.append(0x0A) // LF

    return packet
  }

  /// Encode a response packet (for mock server).
  public func encodeResponse(
    type: PacketType,
    sessionTime: UInt32,
    returnCode: ResponseCode,
    battery: Int,
    printsRemaining: Int,
    payload: Data = Data()
  ) -> Data {
    let payloadLength = 20 + payload.count
    var packet = Data()

    // Header
    packet.append(PacketMode.response.rawValue)
    packet.append(type.rawValue)
    packet.appendUInt16(UInt16(payloadLength))
    packet.appendUInt32(sessionTime)
    packet.append(contentsOf: [0, 0, 0, 0]) // reserved
    packet.append(returnCode.rawValue)
    packet.append(0) // unknown
    packet.append(0) // ejecting
    packet.append(encodeBatteryAndPrints(battery: battery, prints: printsRemaining))

    // Payload
    packet.append(payload)

    // Checksum and end bytes
    let checksum = calculateChecksum(packet)
    packet.append(UInt8((checksum >> 8) & 0xFF))
    packet.append(UInt8(checksum & 0xFF))
    packet.append(0x0D) // CR
    packet.append(0x0A) // LF

    return packet
  }

  private func encodeBatteryAndPrints(battery: Int, prints: Int) -> UInt8 {
    UInt8((battery << 4) | (prints & 0x0F))
  }

  private func calculateChecksum(_ data: Data) -> UInt16 {
    var sum = 0
    for byte in data {
      sum += Int(byte)
    }
    return UInt16((sum ^ -1) & 0xFFFF)
  }
}
