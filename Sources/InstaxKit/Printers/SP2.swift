import Foundation

/// Instax SP-2 printer interface (600x800 resolution).
public actor SP2: InstaxPrinter {
  public let model: PrinterModel = .sp2
  public let host: String
  public let port: UInt16
  public let pinCode: UInt16

  private let base: InstaxPrinterBase
  private let imageEncoder: InstaxImageEncoder

  public init(host: String = "192.168.0.251", port: UInt16 = 8080, pinCode: UInt16 = 1111) {
    self.host = host
    self.port = port
    self.pinCode = pinCode
    base = InstaxPrinterBase(model: .sp2, host: host, port: port, pinCode: pinCode)
    imageEncoder = InstaxImageEncoder(model: .sp2)
  }

  /// Get printer information.
  public func getInfo() async throws -> PrinterInfo {
    try await base.getInfo()
  }

  /// Print an image from a URL.
  public func print(imageAt url: URL, progress: @escaping @Sendable (PrintProgress) -> Void) async throws {
    let encodedData = try imageEncoder.encode(from: url)
    try await base.printImage(encodedData: encodedData, progress: progress)
  }

  /// Print an image from raw encoded bytes.
  public func print(encodedImage: Data, progress: @escaping @Sendable (PrintProgress) -> Void) async throws {
    try await base.printImage(encodedData: encodedImage, progress: progress)
  }
}
