import AppKit
import Combine
import Foundation
import InstaxKit
import Network

@MainActor
class ServerViewModel: ObservableObject {
  @Published var printerModel: PrinterModel = .sp2
  @Published var batteryLevel: Int = 5
  @Published var printsRemaining: Int = 10
  @Published var isRunning: Bool = false
  @Published var port: UInt16 = 8080
  @Published var lastReceivedImage: NSImage?
  @Published var connectionCount: Int = 0
  @Published var lastActivity: String = "Waiting for connection..."

  private var server: MockServer?

  var modelName: String {
    printerModel.displayName
  }

  var imageWidth: Int {
    printerModel.imageWidth
  }

  var imageHeight: Int {
    printerModel.imageHeight
  }

  func startServer() {
    guard !isRunning else { return }

    server = MockServer(
      port: port,
      model: printerModel,
      battery: batteryLevel,
      printsRemaining: printsRemaining,
      onImageReceived: { [weak self] imageData in
        Task { @MainActor in
          self?.handleReceivedImage(imageData)
        }
      },
      onActivity: { [weak self] message in
        Task { @MainActor in
          self?.lastActivity = message
        }
      },
      onConnectionChange: { [weak self] count in
        Task { @MainActor in
          self?.connectionCount = count
        }
      }
    )

    Task {
      do {
        try await server?.start()
        isRunning = true
        lastActivity = "Server started on port \(port)"
      } catch {
        lastActivity = "Failed to start: \(error.localizedDescription)"
      }
    }
  }

  func stopServer() {
    Task {
      await server?.stop()
      server = nil
      isRunning = false
      lastActivity = "Server stopped"
      connectionCount = 0
    }
  }

  func updateServerSettings() {
    if isRunning {
      Task {
        await server?.updateSettings(
          battery: batteryLevel,
          printsRemaining: printsRemaining
        )
      }
    }
  }

  private func handleReceivedImage(_ data: Data) {
    // Decode the image based on printer model
    let encoder = InstaxImageEncoder(model: printerModel)

    // For SP-1, the data is JPEG
    if printerModel == .sp1 {
      if let image = NSImage(data: data) {
        lastReceivedImage = image
        lastActivity = "Received JPEG image (\(data.count) bytes)"
      }
    } else {
      // For SP-2/SP-3, decode the channel-separated format
      do {
        let cgImage = try encoder.decode(data)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        lastReceivedImage = NSImage(cgImage: cgImage, size: size)
        lastActivity = "Received image (\(data.count) bytes)"
      } catch {
        lastActivity = "Failed to decode image: \(error)"
      }
    }
  }
}
