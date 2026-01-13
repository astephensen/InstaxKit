import Foundation

/// Information about an Instax printer.
public struct PrinterInfo: Sendable {
  public let modelName: String
  public let firmware: String
  public let hardware: String
  public let battery: Int
  public let printsRemaining: Int
  public let totalPrints: UInt32
  public let maxWidth: UInt16
  public let maxHeight: UInt16

  public init(
    modelName: String,
    firmware: String,
    hardware: String,
    battery: Int,
    printsRemaining: Int,
    totalPrints: UInt32,
    maxWidth: UInt16,
    maxHeight: UInt16
  ) {
    self.modelName = modelName
    self.firmware = firmware
    self.hardware = hardware
    self.battery = battery
    self.printsRemaining = printsRemaining
    self.totalPrints = totalPrints
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
  }

  public var batteryPercentage: Int {
    // Battery level is 0-7, convert to percentage
    min(100, battery * 15)
  }
}

/// Progress information during printing.
public struct PrintProgress: Sendable {
  public let stage: PrintStage
  public let percentage: Int
  public let message: String

  public init(stage: PrintStage, percentage: Int, message: String) {
    self.stage = stage
    self.percentage = percentage
    self.message = message
  }
}

/// Stages of the print process.
public enum PrintStage: Sendable {
  case connecting
  case sendingPrePrint
  case locking
  case resetting
  case preparingImage
  case sendingImage(segment: Int, total: Int)
  case initiatingPrint
  case waitingForPrint
  case complete
  case error(String)
}

/// Printer model types.
public enum PrinterModel: Sendable {
  case sp2
  case sp3

  public var imageWidth: Int {
    switch self {
    case .sp2: 600
    case .sp3: 800
    }
  }

  public var imageHeight: Int {
    switch self {
    case .sp2: 800
    case .sp3: 800
    }
  }

  public var totalImageBytes: Int {
    imageWidth * imageHeight * 3
  }

  public var segmentCount: Int {
    totalImageBytes / 60000
  }
}
