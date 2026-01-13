import ArgumentParser
import Foundation

@main
struct MockServerCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "instax-mock-server",
    abstract: "Mock Instax printer for testing"
  )

  @Option(name: .shortAndLong, help: "Port to listen on")
  var port: UInt16 = 8080

  @Option(name: .shortAndLong, help: "Battery level (0-7)")
  var battery: Int = 5

  @Option(name: .long, help: "Prints remaining (0-15)")
  var prints: Int = 10

  @Option(name: .shortAndLong, help: "Model name (SP-2 or SP-3)")
  var model: String = "SP-2"

  func run() async throws {
    print("Starting mock Instax printer...")
    print("  Port:     \(port)")
    print("  Model:    \(model)")
    print("  Battery:  \(battery)/7")
    print("  Prints:   \(prints)")
    print()

    let server = MockPrinter(
      port: port,
      battery: battery,
      printsRemaining: prints,
      modelName: model
    )

    try await server.start()

    print("Press Ctrl+C to stop")
    print()

    // Keep the server running indefinitely
    while true {
      try await Task.sleep(nanoseconds: 60_000_000_000)
    }
  }
}
