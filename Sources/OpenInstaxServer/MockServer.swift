import Foundation
import InstaxKit
import Network

/// Mock server wrapper with callbacks for UI updates.
actor MockServer {
  private let port: UInt16
  private let model: PrinterModel
  private var battery: Int
  private var printsRemaining: Int

  private let onImageReceived: @Sendable (Data) -> Void
  private let onActivity: @Sendable (String) -> Void
  private let onConnectionChange: @Sendable (Int) -> Void

  private var listener: NWListener?
  private var connections: [NWConnection] = []
  private let queue = DispatchQueue(label: "com.openinstax.mockserver")

  private let encoder = PacketEncoder()
  private let decoder = PacketDecoder()

  private var receivedImageData = Data()
  private var expectedImageLength: UInt32 = 0

  init(
    port: UInt16,
    model: PrinterModel,
    battery: Int,
    printsRemaining: Int,
    onImageReceived: @escaping @Sendable (Data) -> Void,
    onActivity: @escaping @Sendable (String) -> Void,
    onConnectionChange: @escaping @Sendable (Int) -> Void
  ) {
    self.port = port
    self.model = model
    self.battery = battery
    self.printsRemaining = printsRemaining
    self.onImageReceived = onImageReceived
    self.onActivity = onActivity
    self.onConnectionChange = onConnectionChange
  }

  func updateSettings(battery: Int, printsRemaining: Int) {
    self.battery = battery
    self.printsRemaining = printsRemaining
  }

  func start() throws {
    let parameters = NWParameters.tcp
    listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

    listener?.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.onActivity("Listening on port \(self.port)")
      case let .failed(error):
        self.onActivity("Listener failed: \(error)")
      default:
        break
      }
    }

    listener?.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      Task {
        await self.handleConnection(connection)
      }
    }

    listener?.start(queue: queue)
  }

  func stop() {
    listener?.cancel()
    listener = nil
    for connection in connections {
      connection.cancel()
    }
    connections.removeAll()
  }

  private func handleConnection(_ connection: NWConnection) {
    connections.append(connection)
    onConnectionChange(connections.count)

    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.onActivity("Client connected")
        Task {
          await self.receiveData(from: connection)
        }
      case .cancelled:
        Task {
          await self.removeConnection(connection)
        }
        self.onActivity("Client disconnected")
      case let .failed(error):
        Task {
          await self.removeConnection(connection)
        }
        self.onActivity("Connection failed: \(error)")
      default:
        break
      }
    }

    connection.start(queue: queue)
  }

  private func removeConnection(_ connection: NWConnection) {
    connections.removeAll { $0 === connection }
    onConnectionChange(connections.count)
  }

  private func receiveData(from connection: NWConnection) async {
    while true {
      do {
        let data = try await receivePacket(from: connection)
        let response = try await handlePacket(data)
        connection.send(content: response, completion: .contentProcessed { _ in })
      } catch {
        break
      }
    }
  }

  private func receivePacket(from connection: NWConnection) async throws -> Data {
    let header = try await receiveExact(4, from: connection)
    let length = Int((UInt16(header[2]) << 8) | UInt16(header[3]))
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

  private var modelName: String {
    switch model {
    case .sp1: "SP-1"
    case .sp2: "SP-2"
    case .sp3: "SP-3"
    }
  }

  private func handlePacket(_ data: Data) async throws -> Data {
    let packet = try decoder.decode(data)
    let sessionTime = packet.header.sessionTime

    switch packet.header.type {
    case .printerVersion:
      onActivity("→ Printer version request")
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
      onActivity("→ Model name request")
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
      onActivity("→ Print count request")
      let payload = PrintCountPayload(printHistory: 100)
      return encoder.encodeResponse(
        type: .printCount,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining,
        payload: payload.encode()
      )

    case .specifications:
      onActivity("→ Specifications request")
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
      onActivity("→ Pre-print \(prePrint.commandNumber)")
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
      onActivity("→ Lock device")
      return encoder.encodeResponse(
        type: .lockDevice,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .reset:
      onActivity("→ Reset")
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
      onActivity("→ Preparing for \(expectedImageLength) bytes")
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
      let percent = expectedImageLength > 0 ? Int(Double(receivedImageData.count) / Double(expectedImageLength) * 100) : 0
      onActivity("→ Image segment \(imagePacket.sequenceNumber) (\(percent)%)")
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
      onActivity("→ Print initiated!")
      if receivedImageData.count > 0 {
        onImageReceived(receivedImageData)
      }
      return encoder.encodeResponse(
        type: .type83,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .type195:
      onActivity("→ Status check")
      return encoder.encodeResponse(
        type: .type195,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )

    case .setLockState:
      onActivity("→ Lock state")
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
      onActivity("→ Unknown command: \(packet.header.type)")
      return encoder.encodeResponse(
        type: packet.header.type,
        sessionTime: sessionTime,
        returnCode: .ready,
        battery: battery,
        printsRemaining: printsRemaining
      )
    }
  }
}

enum MockServerError: Error {
  case noData
}
