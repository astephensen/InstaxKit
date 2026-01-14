# InstaxKit

A Swift library and CLI tool for printing to Fujifilm Instax SP-1, SP-2, and SP-3 printers.

## Acknowledgements

This project is a Swift rewrite of [instax_api](https://github.com/jpwsutton/instax_api) by [James Sutton](https://github.com/jpwsutton). Huge thanks to James for reverse-engineering the Instax printer protocol and creating the original Python implementation.

SP-1 printer support is based on the work by [cool2man](https://github.com/cool2man/instax_api) who added SP-1 compatibility to the original Python implementation.

## Requirements

- macOS 13+ or iOS 16+
- Swift 5.9+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/astephensen/InstaxKit.git", from: "1.0.0")
]
```

### Build the CLI

```bash
git clone https://github.com/astephensen/InstaxKit.git
cd InstaxKit
swift build -c release
```

The binary will be at `.build/release/instax`.

## CLI Usage

### Print an image

```bash
# Auto-detect printer model (default)
instax print photo.jpg

# Specify printer model explicitly
instax print photo.jpg --printer sp1
instax print photo.jpg --printer sp2
instax print photo.jpg --printer sp3

# With custom settings
instax print photo.jpg --host 192.168.0.251 --pin 1234

# Rotate image 90 degrees clockwise
instax print photo.jpg --rotate 90

# Enable debug output
instax print photo.jpg --verbose
```

### Get printer info

```bash
# Auto-detect printer model
instax info

# Specify printer model explicitly
instax info --printer sp3 --host 192.168.0.251
```

Example output:
```
Printer Information
-------------------
Model:           SP-2
Firmware:        01.05
Hardware:        00.00
Battery:         5/7 (75%)
Prints Left:     8
Total Prints:    142
Max Resolution:  600x800
```

## Library Usage

InstaxKit is designed for easy integration into iOS and macOS apps.

### Auto-detect printer model

```swift
import InstaxKit

// Automatically detect SP-1, SP-2, or SP-3
let printer = try await InstaxKit.detectPrinter(host: "192.168.0.251")
try await printer.print(imageAt: imageURL) { progress in
  print("\(progress.percentage)% - \(progress.message)")
}
```

### Basic printing

```swift
import InstaxKit

// SP-1 (480x640, JPEG encoding)
let printer = InstaxPrinter(model: .sp1)

// SP-2 (600x800)
let printer = InstaxPrinter(model: .sp2)

// SP-3 (800x800, square)
let printer = InstaxPrinter(model: .sp3)

try await printer.print(imageAt: imageURL) { progress in
  print("\(progress.percentage)% - \(progress.message)")
}
```

### Get printer status

```swift
let printer = InstaxPrinter(model: .sp3, host: "192.168.0.251", pinCode: 1111)
let info = try await printer.getInfo()

print("Battery: \(info.batteryPercentage)%")
print("Prints remaining: \(info.printsRemaining)")
print("Total prints: \(info.totalPrints)")
```

### Using the factory method

```swift
let printer = InstaxKit.printer(model: .sp2, host: "192.168.0.251")
let info = try await printer.getInfo()
```

### Print with progress UI (SwiftUI)

```swift
struct PrintView: View {
  @State private var progress = 0
  @State private var message = "Ready"

  var body: some View {
    VStack {
      ProgressView(value: Double(progress), total: 100)
      Text(message)
      Button("Print") { Task { await printPhoto() } }
    }
  }

  func printPhoto() async {
    let printer = InstaxPrinter(model: .sp2)
    do {
      try await printer.print(imageAt: photoURL) { update in
        Task { @MainActor in
          progress = update.percentage
          message = update.message
        }
      }
    } catch {
      message = "Error: \(error.localizedDescription)"
    }
  }
}
```

### Print from CGImage

```swift
let printer = InstaxPrinter(model: .sp2)
let cgImage: CGImage = // ... your image

try await printer.print(image: cgImage) { progress in
  print(progress.message)
}
```

### Image encoding only

If you need to encode an image without printing:

```swift
let encoder = InstaxImageEncoder(model: .sp2)
let encodedData = try encoder.encode(from: imageURL, rotation: .clockwise90)

// Later, print the pre-encoded data
try await printer.print(encodedImage: encodedData) { _ in }
```

## Connecting to the Printer

1. Turn on your Instax printer
2. Connect to its WiFi network (SSID starts with `INSTAX-`)
3. The printer's IP is typically `192.168.0.251`
4. Default PIN is `1111`

### Tips

- Enable DHCP on your computer if you have a static IP configured
- The printer auto-shutdowns after ~10 minutes of inactivity
- SP-1 prints at 480x640 (uses JPEG encoding)
- SP-2 prints at 600x800
- SP-3 prints at 800x800 (square)

## Development

### Run tests

```bash
swift test
```

### Mock server

For testing without a physical printer:

```bash
# Start mock SP-2 printer (default)
swift run instax-mock-server --port 8080

# Start mock SP-1 printer
swift run instax-mock-server --port 8080 --model sp1

# Start mock SP-3 printer
swift run instax-mock-server --port 8080 --model sp3

# Custom battery and prints
swift run instax-mock-server --battery 3 --prints 5
```

Then point the CLI at localhost:

```bash
instax print photo.jpg --host 127.0.0.1

# Or let it auto-detect the mock printer model
instax print photo.jpg --host 127.0.0.1
```

## License

MIT

## See Also

- [instax_api](https://github.com/jpwsutton/instax_api) - The original Python implementation by James Sutton
