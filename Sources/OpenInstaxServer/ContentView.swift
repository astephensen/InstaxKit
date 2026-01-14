import InstaxKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject var viewModel: ServerViewModel

  var body: some View {
    HStack(spacing: 0) {
      // Polaroid Preview
      PolaroidView(
        image: viewModel.lastReceivedImage,
        printerModel: viewModel.printerModel
      )
      .padding(40)
      .background(Color(nsColor: .windowBackgroundColor))

      // Controls Sidebar
      ControlsSidebar()
        .frame(width: 280)
        .background(Color(nsColor: .controlBackgroundColor))
    }
  }
}

struct ControlsSidebar: View {
  @EnvironmentObject var viewModel: ServerViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Header
      VStack(alignment: .leading, spacing: 4) {
        Text("OpenInstax Server")
          .font(.headline)
        Text("Mock Printer Simulator")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.bottom, 8)

      Divider()

      // Server Status
      GroupBox("Server") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Circle()
              .fill(viewModel.isRunning ? Color.green : Color.red)
              .frame(width: 10, height: 10)
            Text(viewModel.isRunning ? "Running" : "Stopped")
              .font(.subheadline)
            Spacer()
            Text("Port \(String(viewModel.port))")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          if viewModel.isRunning {
            Text(viewModel.lastActivity)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(2)

            if viewModel.connectionCount > 0 {
              Text("\(viewModel.connectionCount) client(s) connected")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          HStack {
            Button(viewModel.isRunning ? "Stop" : "Start") {
              if viewModel.isRunning {
                viewModel.stopServer()
              } else {
                viewModel.startServer()
              }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .green)
          }
        }
        .padding(.vertical, 8)
      }

      // Printer Model
      GroupBox("Printer Model") {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Model", selection: $viewModel.printerModel) {
            Text("SP-1 (480×640)").tag(PrinterModel.sp1)
            Text("SP-2 (600×800)").tag(PrinterModel.sp2)
            Text("SP-3 (800×800)").tag(PrinterModel.sp3)
          }
          .pickerStyle(.radioGroup)
          .disabled(viewModel.isRunning)

          if viewModel.isRunning {
            Text("Stop server to change model")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, 8)
      }

      // Printer Status
      GroupBox("Printer Status") {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Battery Level")
              .font(.caption)
              .foregroundColor(.secondary)
            HStack {
              Slider(value: Binding(
                get: { Double(viewModel.batteryLevel) },
                set: {
                  viewModel.batteryLevel = Int($0)
                  viewModel.updateServerSettings()
                }
              ), in: 0 ... 7, step: 1)
              Text("\(viewModel.batteryLevel)/7")
                .font(.caption)
                .frame(width: 30)
            }
            BatteryIndicator(level: viewModel.batteryLevel)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Prints Remaining")
              .font(.caption)
              .foregroundColor(.secondary)
            HStack {
              Slider(value: Binding(
                get: { Double(viewModel.printsRemaining) },
                set: {
                  viewModel.printsRemaining = Int($0)
                  viewModel.updateServerSettings()
                }
              ), in: 0 ... 10, step: 1)
              Text("\(viewModel.printsRemaining)")
                .font(.caption)
                .frame(width: 30)
            }
          }
        }
        .padding(.vertical, 8)
      }

      Spacer()

      // Info
      VStack(alignment: .leading, spacing: 4) {
        Text("Connect using:")
          .font(.caption)
          .foregroundColor(.secondary)
        Text("Host: 127.0.0.1")
          .font(.system(.caption, design: .monospaced))
        Text("Port: \(String(viewModel.port))")
          .font(.system(.caption, design: .monospaced))
      }
      .padding(.top, 16)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }
}

struct BatteryIndicator: View {
  let level: Int

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0 ..< 7, id: \.self) { index in
        RoundedRectangle(cornerRadius: 2)
          .fill(index < level ? batteryColor : Color.gray.opacity(0.3))
          .frame(width: 20, height: 12)
      }
    }
  }

  var batteryColor: Color {
    if level <= 1 {
      return .red
    } else if level <= 3 {
      return .orange
    } else {
      return .green
    }
  }
}

#Preview {
  ContentView()
    .environmentObject(ServerViewModel())
    .frame(width: 700, height: 600)
}
