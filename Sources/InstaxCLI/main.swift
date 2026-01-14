import ArgumentParser
import Foundation
import InstaxKit

@main
struct InstaxCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "instax",
    abstract: "Instax printer control utility",
    version: InstaxKit.version,
    subcommands: [PrintCommand.self, InfoCommand.self]
  )
}

struct PrintCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "print",
    abstract: "Print an image"
  )

  @Argument(help: "Path to the image file")
  var imagePath: String

  @Option(name: .shortAndLong, help: "Printer model (sp2, sp3, or auto)")
  var printer: String?

  @Option(name: .long, help: "Printer IP address")
  var host: String = "192.168.0.251"

  @Option(name: .long, help: "Printer port")
  var port: UInt16 = 8080

  @Option(name: .long, help: "PIN code")
  var pin: UInt16 = 1111

  @Flag(name: .shortAndLong, help: "Enable verbose debug output")
  var verbose: Bool = false

  func run() async throws {
    if verbose {
      Logger.shared.isEnabled = true
    }

    let imageURL = URL(fileURLWithPath: imagePath)

    guard FileManager.default.fileExists(atPath: imagePath) else {
      throw ValidationError("Image file not found: \(imagePath)")
    }

    let printerInstance: any InstaxPrinter

    if let printer, printer.lowercased() != "auto" {
      let model: PrinterModel
      switch printer.lowercased() {
      case "sp2", "2":
        model = .sp2
      case "sp3", "3":
        model = .sp3
      default:
        throw ValidationError("Unknown printer model: \(printer). Use 'sp2', 'sp3', or 'auto'.")
      }
      print("Printing to Instax \(printer.uppercased()) at \(host):\(port)")
      printerInstance = InstaxKit.printer(model: model, host: host, port: port, pinCode: pin)
    } else {
      print("Auto-detecting printer at \(host):\(port)...")
      printerInstance = try await InstaxKit.detectPrinter(host: host, port: port, pinCode: pin)
      let info = try await printerInstance.getInfo()
      print("Detected: \(info.modelName)")
    }

    do {
      try await printerInstance.print(imageAt: imageURL) { progress in
        printProgress(progress)
      }
    } catch {
      print("\nError: \(error)")
      throw ExitCode.failure
    }
  }

  private func printProgress(_ progress: PrintProgress) {
    let bar = makeProgressBar(percentage: progress.percentage)
    print("\r\(bar) \(progress.percentage)% - \(progress.message)", terminator: "")
    fflush(stdout)

    if progress.percentage == 100 {
      print() // New line at the end
    }
  }

  private func makeProgressBar(percentage: Int, width: Int = 30) -> String {
    let filled = percentage * width / 100
    let empty = width - filled
    return "[" + String(repeating: "=", count: filled) + String(repeating: " ", count: empty) + "]"
  }
}

struct InfoCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Get printer information"
  )

  @Option(name: .shortAndLong, help: "Printer model (sp2, sp3, or auto)")
  var printer: String?

  @Option(name: .long, help: "Printer IP address")
  var host: String = "192.168.0.251"

  @Option(name: .long, help: "Printer port")
  var port: UInt16 = 8080

  @Option(name: .long, help: "PIN code")
  var pin: UInt16 = 1111

  @Flag(name: .shortAndLong, help: "Enable verbose debug output")
  var verbose: Bool = false

  func run() async throws {
    if verbose {
      Logger.shared.isEnabled = true
    }

    let printerInstance: any InstaxPrinter

    if let printer, printer.lowercased() != "auto" {
      let model: PrinterModel
      switch printer.lowercased() {
      case "sp2", "2":
        model = .sp2
      case "sp3", "3":
        model = .sp3
      default:
        throw ValidationError("Unknown printer model: \(printer). Use 'sp2', 'sp3', or 'auto'.")
      }
      print("Connecting to Instax \(printer.uppercased()) at \(host):\(port)...")
      printerInstance = InstaxKit.printer(model: model, host: host, port: port, pinCode: pin)
    } else {
      print("Auto-detecting printer at \(host):\(port)...")
      printerInstance = try await InstaxKit.detectPrinter(host: host, port: port, pinCode: pin)
    }

    do {
      let info = try await printerInstance.getInfo()
      print()
      print("Printer Information")
      print("-------------------")
      print("Model:           \(info.modelName)")
      print("Firmware:        \(info.firmware)")
      print("Hardware:        \(info.hardware)")
      print("Battery:         \(info.battery)/7 (\(info.batteryPercentage)%)")
      print("Prints Left:     \(info.printsRemaining)")
      print("Total Prints:    \(info.totalPrints)")
      print("Max Resolution:  \(info.maxWidth)x\(info.maxHeight)")
    } catch {
      print("\nError: \(error)")
      throw ExitCode.failure
    }
  }
}
