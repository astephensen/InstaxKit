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
    case .sp2:
      SP2(host: host, port: port, pinCode: pinCode)
    case .sp3:
      SP3(host: host, port: port, pinCode: pinCode)
    }
  }
}
