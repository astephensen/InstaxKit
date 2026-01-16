import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
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

  @Option(name: .shortAndLong, help: "Printer model (sp1, sp2, sp3, or auto)")
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

    let printerInstance: InstaxPrinter

    if let printer, printer.lowercased() != "auto" {
      guard let model = PrinterModel(fromInput: printer) else {
        throw ValidationError("Unknown printer model: \(printer). Use 'sp1', 'sp2', 'sp3', or 'auto'.")
      }
      print("Printing to Instax \(model.displayName) at \(host):\(port)")
      printerInstance = InstaxKit.printer(model: model, host: host, port: port, pinCode: pin)
    } else {
      print("Auto-detecting printer at \(host):\(port)...")
      printerInstance = try await InstaxKit.detectPrinter(host: host, port: port, pinCode: pin)
      let info = try await printerInstance.getInfo()
      print("Detected: \(info.modelName)")
    }

    // Load and prepare image
    let model = await printerInstance.model
    guard let preparedImage = loadAndPrepareImage(url: imageURL, for: model) else {
      print("Error: Failed to load or prepare image")
      throw ExitCode.failure
    }

    do {
      try await printerInstance.print(image: preparedImage) { progress in
        printProgress(progress)
      }
    } catch {
      print("\nError: \(error)")
      throw ExitCode.failure
    }
  }

  /// Load image from URL and resize to printer dimensions
  private func loadAndPrepareImage(url: URL, for model: PrinterModel) -> CGImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      return nil
    }

    let targetWidth = model.imageWidth
    let targetHeight = model.imageHeight

    // Calculate aspect-fill dimensions
    let sourceWidth = CGFloat(sourceImage.width)
    let sourceHeight = CGFloat(sourceImage.height)
    let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)
    let sourceAspect = sourceWidth / sourceHeight

    let scale: CGFloat
    if sourceAspect > targetAspect {
      scale = CGFloat(targetHeight) / sourceHeight
    } else {
      scale = CGFloat(targetWidth) / sourceWidth
    }

    let scaledWidth = sourceWidth * scale
    let scaledHeight = sourceHeight * scale
    let offsetX = (scaledWidth - CGFloat(targetWidth)) / 2
    let offsetY = (scaledHeight - CGFloat(targetHeight)) / 2

    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: targetHeight,
      bitsPerComponent: 8,
      bytesPerRow: targetWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    context.draw(sourceImage, in: CGRect(x: -offsetX, y: -offsetY, width: scaledWidth, height: scaledHeight))

    return context.makeImage()
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

  @Option(name: .shortAndLong, help: "Printer model (sp1, sp2, sp3, or auto)")
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

    let printerInstance: InstaxPrinter

    if let printer, printer.lowercased() != "auto" {
      guard let model = PrinterModel(fromInput: printer) else {
        throw ValidationError("Unknown printer model: \(printer). Use 'sp1', 'sp2', 'sp3', or 'auto'.")
      }
      print("Connecting to Instax \(model.displayName) at \(host):\(port)...")
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
