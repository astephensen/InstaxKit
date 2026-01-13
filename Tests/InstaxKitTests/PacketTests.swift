@testable import InstaxKit
import XCTest

final class PacketTests: XCTestCase {
  let encoder = PacketEncoder()
  let decoder = PacketDecoder()

  func testEncodeDecodeVersionCommand() throws {
    let sessionTime: UInt32 = 12_345_678
    let pinCode: UInt16 = 1111

    let encoded = encoder.encodeCommand(
      type: .printerVersion,
      sessionTime: sessionTime,
      pinCode: pinCode
    )

    // Verify packet structure
    XCTAssertEqual(encoded[0], PacketMode.command.rawValue)
    XCTAssertEqual(encoded[1], PacketType.printerVersion.rawValue)

    // Verify checksum and end bytes
    XCTAssertEqual(encoded[encoded.count - 2], 0x0D)
    XCTAssertEqual(encoded[encoded.count - 1], 0x0A)

    // Decode and verify
    let decoded = try decoder.decode(encoded)
    XCTAssertEqual(decoded.header.mode, .command)
    XCTAssertEqual(decoded.header.type, .printerVersion)
    XCTAssertEqual(decoded.header.sessionTime, sessionTime)
    XCTAssertEqual(decoded.header.pinCode, pinCode)
  }

  func testEncodeDecodeResponse() throws {
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
    XCTAssertEqual(decoded.header.mode, .response)
    XCTAssertEqual(decoded.header.type, .printerVersion)
    XCTAssertEqual(decoded.header.returnCode, .ready)
    XCTAssertEqual(decoded.header.battery, battery)
    XCTAssertEqual(decoded.header.printsRemaining, prints)
  }

  func testVersionPayload() throws {
    let payload = VersionPayload(firmware: "01.02", hardware: "01.00")
    let encoded = payload.encode()

    let decoded = try VersionPayload.decode(from: encoded, mode: .response)
    XCTAssertEqual(decoded.firmware, "01.02")
    XCTAssertEqual(decoded.hardware, "01.00")
  }

  func testModelNamePayload() throws {
    let payload = ModelNamePayload(modelName: "SP-2")
    let encoded = payload.encode()

    let decoded = try ModelNamePayload.decode(from: encoded, mode: .response)
    XCTAssertEqual(decoded.modelName, "SP-2")
  }

  func testPrintCountPayload() throws {
    let payload = PrintCountPayload(printHistory: 12345)
    let encoded = payload.encode()

    let decoded = try PrintCountPayload.decode(from: encoded, mode: .response)
    XCTAssertEqual(decoded.printHistory, 12345)
  }

  func testPrePrintPayload() throws {
    let payload = PrePrintPayload(commandNumber: 5, responseNumber: 5)
    let encoded = payload.encode()

    let decoded = try PrePrintPayload.decode(from: encoded, mode: .command)
    XCTAssertEqual(decoded.commandNumber, 5)
  }

  func testChecksumValidation() throws {
    let encoded = encoder.encodeCommand(
      type: .reset,
      sessionTime: 100,
      pinCode: 1111
    )

    // Corrupt the checksum
    var corrupted = encoded
    corrupted[encoded.count - 4] ^= 0xFF

    XCTAssertThrowsError(try decoder.decode(corrupted)) { error in
      XCTAssertEqual(error as? PacketError, .invalidChecksum)
    }
  }

  func testInvalidEndBytes() throws {
    let encoded = encoder.encodeCommand(
      type: .reset,
      sessionTime: 100,
      pinCode: 1111
    )

    // Corrupt end bytes
    var corrupted = encoded
    corrupted[encoded.count - 1] = 0x00

    XCTAssertThrowsError(try decoder.decode(corrupted)) { error in
      XCTAssertEqual(error as? PacketError, .invalidEndBytes)
    }
  }

  func testDataExtensions() {
    var data = Data()
    data.appendUInt16(0x1234)
    data.appendUInt32(0x5678_9ABC)

    XCTAssertEqual(data.uint16(at: 0), 0x1234)
    XCTAssertEqual(data.uint32(at: 2), 0x5678_9ABC)
  }

  func testResponseCodes() {
    XCTAssertFalse(ResponseCode.ready.isError)
    XCTAssertFalse(ResponseCode.printing.isError)
    XCTAssertTrue(ResponseCode.filmEmpty.isError)
    XCTAssertTrue(ResponseCode.batteryEmpty.isError)
  }

  func testPrinterModel() {
    XCTAssertEqual(PrinterModel.sp2.imageWidth, 600)
    XCTAssertEqual(PrinterModel.sp2.imageHeight, 800)
    XCTAssertEqual(PrinterModel.sp2.totalImageBytes, 1_440_000)
    XCTAssertEqual(PrinterModel.sp2.segmentCount, 24)

    XCTAssertEqual(PrinterModel.sp3.imageWidth, 800)
    XCTAssertEqual(PrinterModel.sp3.imageHeight, 800)
    XCTAssertEqual(PrinterModel.sp3.totalImageBytes, 1_920_000)
    XCTAssertEqual(PrinterModel.sp3.segmentCount, 32)
  }
}
