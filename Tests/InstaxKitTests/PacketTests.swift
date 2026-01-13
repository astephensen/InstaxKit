@testable import InstaxKit
import Testing

struct PacketTests {
  let encoder = PacketEncoder()
  let decoder = PacketDecoder()

  @Test func encodeDecodeVersionCommand() throws {
    let sessionTime: UInt32 = 12_345_678
    let pinCode: UInt16 = 1111

    let encoded = encoder.encodeCommand(
      type: .printerVersion,
      sessionTime: sessionTime,
      pinCode: pinCode
    )

    // Verify packet structure
    #expect(encoded[0] == PacketMode.command.rawValue)
    #expect(encoded[1] == PacketType.printerVersion.rawValue)

    // Verify checksum and end bytes
    #expect(encoded[encoded.count - 2] == 0x0D)
    #expect(encoded[encoded.count - 1] == 0x0A)

    // Decode and verify
    let decoded = try decoder.decode(encoded)
    #expect(decoded.header.mode == .command)
    #expect(decoded.header.type == .printerVersion)
    #expect(decoded.header.sessionTime == sessionTime)
    #expect(decoded.header.pinCode == pinCode)
  }

  @Test func encodeDecodeResponse() throws {
    let sessionTime: UInt32 = 87_654_321
    let battery = 5
    let prints = 10

    let encoded = encoder.encodeResponse(
      type: .printerVersion,
      sessionTime: sessionTime,
      returnCode: .ready,
      battery: battery,
      printsRemaining: prints
    )

    let decoded = try decoder.decode(encoded)
    #expect(decoded.header.mode == .response)
    #expect(decoded.header.type == .printerVersion)
    #expect(decoded.header.returnCode == .ready)
    #expect(decoded.header.battery == battery)
    #expect(decoded.header.printsRemaining == prints)
  }

  @Test func versionPayload() throws {
    let payload = VersionPayload(firmware: "01.02", hardware: "01.00")
    let encoded = payload.encode()

    let decoded = try VersionPayload.decode(from: encoded, mode: .response)
    #expect(decoded.firmware == "01.02")
    #expect(decoded.hardware == "01.00")
  }

  @Test func modelNamePayload() throws {
    let payload = ModelNamePayload(modelName: "SP-2")
    let encoded = payload.encode()

    let decoded = try ModelNamePayload.decode(from: encoded, mode: .response)
    #expect(decoded.modelName == "SP-2")
  }

  @Test func printCountPayload() throws {
    let payload = PrintCountPayload(printHistory: 12345)
    let encoded = payload.encode()

    let decoded = try PrintCountPayload.decode(from: encoded, mode: .response)
    #expect(decoded.printHistory == 12345)
  }

  @Test func prePrintPayload() throws {
    let payload = PrePrintPayload(commandNumber: 5, responseNumber: 5)
    let encoded = payload.encode()

    let decoded = try PrePrintPayload.decode(from: encoded, mode: .command)
    #expect(decoded.commandNumber == 5)
  }

  @Test func checksumValidation() throws {
    let encoded = encoder.encodeCommand(
      type: .reset,
      sessionTime: 100,
      pinCode: 1111
    )

    // Corrupt the checksum
    var corrupted = encoded
    corrupted[encoded.count - 4] ^= 0xFF

    #expect(throws: PacketError.invalidChecksum) {
      try decoder.decode(corrupted)
    }
  }

  @Test func invalidEndBytes() throws {
    let encoded = encoder.encodeCommand(
      type: .reset,
      sessionTime: 100,
      pinCode: 1111
    )

    // Corrupt end bytes
    var corrupted = encoded
    corrupted[encoded.count - 1] = 0x00

    #expect(throws: PacketError.invalidEndBytes) {
      try decoder.decode(corrupted)
    }
  }

  @Test func dataExtensions() {
    var data = Data()
    data.appendUInt16(0x1234)
    data.appendUInt32(0x5678_9ABC)

    #expect(data.uint16(at: 0) == 0x1234)
    #expect(data.uint32(at: 2) == 0x5678_9ABC)
  }

  @Test func responseCodes() {
    #expect(!ResponseCode.ready.isError)
    #expect(!ResponseCode.printing.isError)
    #expect(ResponseCode.filmEmpty.isError)
    #expect(ResponseCode.batteryEmpty.isError)
  }

  @Test func printerModel() {
    #expect(PrinterModel.sp2.imageWidth == 600)
    #expect(PrinterModel.sp2.imageHeight == 800)
    #expect(PrinterModel.sp2.totalImageBytes == 1_440_000)
    #expect(PrinterModel.sp2.segmentCount == 24)

    #expect(PrinterModel.sp3.imageWidth == 800)
    #expect(PrinterModel.sp3.imageHeight == 800)
    #expect(PrinterModel.sp3.totalImageBytes == 1_920_000)
    #expect(PrinterModel.sp3.segmentCount == 32)
  }
}
