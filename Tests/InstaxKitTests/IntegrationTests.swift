@testable import InstaxKit
import Testing

struct IntegrationTests {
  // Note: These tests require a mock server or real printer to be running
  // They are marked with .disabled by default

  @Test(.disabled("Requires mock server running on localhost:8080"))
  func autoDetectPrinter() async throws {
    let printer = try await InstaxKit.detectPrinter(host: "127.0.0.1", port: 8080, pinCode: 1111)
    let info = try await printer.getInfo()

    // Should detect either SP-2 or SP-3
    #expect(info.modelName.contains("SP-2") || info.modelName.contains("SP-3"))
  }

  @Test(.disabled("Requires mock server running on localhost:8080"))
  func getPrinterInfo() async throws {
    let printer = InstaxPrinter(model: .sp2, host: "127.0.0.1", port: 8080, pinCode: 1111)
    let info = try await printer.getInfo()

    #expect(!info.modelName.isEmpty)
    #expect(!info.firmware.isEmpty)
    #expect(info.battery >= 0)
    #expect(info.battery <= 7)
  }
}
