import Foundation
import InstaxKit
import Network

/// Mock Instax printer for testing without hardware.
public actor MockPrinter {
  private let port: UInt16
  private var listener: NWListener?
  private var connections: [NWConnection] = []
  private let queue = DispatchQueue(label: "com.instaxkit.mockserver")

  public var battery: Int = 5
  public var printsRemaining: Int = 10
  public var totalPrints: UInt32 = 100
  public let model: PrinterModel

  private let encoder = PacketEncoder()
  private let decoder = PacketDecoder()

  private var receivedImageData = Data()
  private var expectedImageLength: UInt32 = 0

  public init(port: UInt16 = 8080, battery: Int = 5, printsRemaining: Int = 10, model: PrinterModel = .sp2) {
    self.port = port
    self.battery = battery
    self.printsRemaining = printsRemaining
    self.model = model
  }

  private var modelName: String {
    switch model {
    case .sp1: "SP-1"
    case .sp2: "SP-2"
    case .sp3: "SP-3"
    }
  }

  /// Start the mock server.
  public func start() async throws {
    let parameters = NWParameters.tcp
    listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

    listener?.stateUpdateHandler = { state in
      switch state {
      case .ready:
        print("Mock printer listening on port \(self.port)")
      case let .failed(error):
        print("Listener failed: \(error)")
      default:
        break
      }
    }

    listener?.newConnectionHandler = { [weak self] connection in
      Task { [weak self] in
        await self?.handleConnection(connection)
      }
    }

    listener?.start(queue: queue)
  }

  /// Stop the mock server.
  public func stop() {
    listener?.cancel()
    listener = nil
    for connection in connections {
      connection.cancel()
    }
    connections.removeAll()
  }

  private func handleConnection(_ connection: NWConnection) {
    connections.append(connection)

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        print("Client connected")
        Task { [weak self] in
          await self?.receiveData(from: connection)
        }
      case let .failed(error):
        print("Connection failed: \(error)")
      case .cancelled:
        print("Client disconnected")
      default:
        break
      }
    }

    connection.start(queue: queue)
  }

  private func receiveData(from connection: NWConnection) async {
    while true {
      do {
        let data = try await receivePacket(from: connection)
        let response = try await handlePacket(data)
        connection.send(content: response, completion: .contentProcessed { error in
          if let error {
            print("Send error: \(error)")
          }
        })
      } catch {
        print("Receive error: \(error)")
        break
      }
    }
  }

  private func receivePacket(from connection: NWConnection) async throws -> Data {
    // First read 4 bytes to get length
    let header = try await receiveExact(4, from: connection)
    let length = Int((UInt16(header[2]) << 8) | UInt16(header[3]))

    // Read the rest
    let remaining = try await receiveExact(length - 4, from: connection)
    return header + remaining
  }

  private func receiveExact(_ count: Int, from connection: NWConnection) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let data {
          continuation.resume(returning: data)
        } else {
          continuation.resume(throwing: MockServerError.noData)
        }
      }
    }
  }

  private func handlePacket(_ data: Data) async throws -> Data {
    let packet = try decoder.decode(data)
    let sessionTime = packet.header.sessionTime

    print("Received: \(packet.header.type)")

    switch packet.header.type {
    case .printerVersion:
      let payload = VersionPayload(firmware: "01.02", hardware: "01.00")
      return encoder.encodeResponse(
        type: .printerVersion,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: payload.encode()
      )

    case .modelName:
      let payload = ModelNamePayload(modelName: modelName)
      return encoder.encodeResponse(
        type: .modelName,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: payload.encode()
      )

    case .printCount:
      let payload = PrintCountPayload(printHistory: totalPrints)
      return encoder.encodeResponse(
        type: .printCount,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: payload.encode()
      )

    case .specifications:
      let payload = SpecificationsPayload(
        maxWidth: UInt16(model.imageWidth),
        maxHeight: UInt16(model.imageHeight),
        maxColors: 256,
        maxMessageSize: UInt16(model.segmentSize)
      )
      return encoder.encodeResponse(
        type: .specifications,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: payload.encode()
      )

    case .prePrint:
      let prePrint = try packet.decodePayload(PrePrintPayload.self)
      let response = PrePrintPayload(commandNumber: prePrint.commandNumber, responseNumber: prePrint.commandNumber)
      return encoder.encodeResponse(
        type: .prePrint,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: response.encode()
      )

    case .lockDevice:
      return encoder.encodeResponse(
        type: .lockDevice,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .reset:
      receivedImageData = Data()
      return encoder.encodeResponse(
        type: .reset,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .prepImage:
      let prep = try packet.decodePayload(PrepImagePayload.self)
      expectedImageLength = prep.imageLength
      receivedImageData = Data()
      print("Preparing for image of \(expectedImageLength) bytes (\(model) printer)")
      let response = PrepImagePayload(imageLength: prep.imageLength, maxLength: UInt16(model.segmentSize))
      return encoder.encodeResponse(
        type: .prepImage,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: response.encode()
      )

    case .sendImage:
      let imagePacket = try packet.decodePayload(SendImagePayload.self)
      receivedImageData.append(imagePacket.imageData)
      print(
        "Received segment \(imagePacket.sequenceNumber), total: \(receivedImageData.count)/\(expectedImageLength) bytes"
      )
      let response = SendImagePayload(sequenceNumber: imagePacket.sequenceNumber)
      return encoder.encodeResponse(
        type: .sendImage,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: response.encode()
      )

    case .type83:
      print("Print initiated! Received \(receivedImageData.count) bytes of image data")
      // Save the image if we received a complete one
      if receivedImageData.count > 0 {
        await saveReceivedImage()
      }
      return encoder.encodeResponse(
        type: .type83,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .type195:
      return encoder.encodeResponse(
        type: .type195,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .setLockState:
      let payload = LockStatePayload(value: 0)
      return encoder.encodeResponse(
        type: .setLockState,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: payload.encode()
      )

    default:
      return encoder.encodeResponse(
        type: packet.header.type,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )
    }
  }

  private func saveReceivedImage() async {
    let documentsPath = FileManager.default.currentDirectoryPath
    let filename = "received_image_\(Date().timeIntervalSince1970).raw"
    let filepath = (documentsPath as NSString).appendingPathComponent(filename)

    do {
      try receivedImageData.write(to: URL(fileURLWithPath: filepath))
      print("Saved received image to: \(filepath)")
    } catch {
      print("Failed to save image: \(error)")
    }
  }
}

enum MockServerError: Error {
  case noData
  case invalidPacket
}
