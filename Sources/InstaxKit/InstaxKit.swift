/// InstaxKit - Swift library for Fujifilm Instax SP-2 and SP-3 printers.
///
/// Usage:
/// ```swift
/// let printer = SP2(host: "192.168.0.251")
/// let info = try await printer.getInfo()
/// print("Model: \(info.modelName), Battery: \(info.battery)")
///
/// try await printer.print(imageAt: imageURL) { progress in
///     print("\(progress.percentage)% - \(progress.message)")
/// }
/// ```

// Re-export public types
@_exported import Foundation

// Models
public typealias Printer = any InstaxPrinter

// Version info
public enum InstaxKit {
  public static let version = "1.0.0"

  /// Create a printer instance by model type.
  public static func printer(
    model: PrinterModel,
    host: String = "192.168.0.251",
    port: UInt16 = 8080,
    pinCode: UInt16 = 1111
  ) -> any InstaxPrinter {
    switch model {
    case .sp1:
      SP1(host: host, port: port, pinCode: pinCode)
    case .sp2:
      SP2(host: host, port: port, pinCode: pinCode)
    case .sp3:
      SP3(host: host, port: port, pinCode: pinCode)
    }
  }

  /// Auto-detect printer model and return appropriate instance.
  public static func detectPrinter(
    host: String = "192.168.0.251",
    port: UInt16 = 8080,
    pinCode: UInt16 = 1111
  ) async throws -> any InstaxPrinter {
    debugLog("Auto-detecting printer model at \(host):\(port)")

    // Use a temporary base instance to query the printer
    let base = InstaxPrinterBase(model: .sp2, host: host, port: port, pinCode: pinCode)

    do {
      try await base.connect()
      defer {
        Task { await base.close() }
      }

      let modelNamePacket = try await base.getModelName()
      let modelPayload = try modelNamePacket.decodePayload(ModelNamePayload.self)

      debugLog("Detected model: \(modelPayload.modelName)")

      // Parse model name to determine type
      let modelName = modelPayload.modelName.uppercased()
      let detectedModel: PrinterModel
      if modelName.contains("SP-1") || modelName.contains("SP1") {
        detectedModel = .sp1
      } else if modelName.contains("SP-2") || modelName.contains("SP2") {
        detectedModel = .sp2
      } else if modelName.contains("SP-3") || modelName.contains("SP3") {
        detectedModel = .sp3
      } else {
        throw PrinterDetectionError.unknownModel(modelPayload.modelName)
      }

      debugLog("Creating printer instance for \(detectedModel)")
      return printer(model: detectedModel, host: host, port: port, pinCode: pinCode)
    } catch {
      debugLog("Auto-detection failed: \(error)")
      throw error
    }
  }
}

/// Printer detection errors.
public enum PrinterDetectionError: Error, CustomStringConvertible {
  case unknownModel(String)

  public var description: String {
    switch self {
    case let .unknownModel(name):
      "Unknown printer model: \(name). Expected SP-1, SP-2, or SP-3."
    }
  }
}
