import CoreGraphics
import Foundation

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(UIKit)
  import UIKit
#endif

/// Encodes images for Instax printers.
///
/// Images must be provided at the exact size for the printer model:
/// - SP-1: 480×640
/// - SP-2: 600×800
/// - SP-3: 800×800
public struct InstaxImageEncoder: Sendable {
  public let model: PrinterModel

  public init(model: PrinterModel) {
    self.model = model
  }

  /// Encode a CGImage for transmission to the printer.
  ///
  /// The image must be exactly the right size for the printer model.
  /// - Throws: `ImageError.invalidDimensions` if the image is not the correct size
  public func encode(image: CGImage) throws -> Data {
    let expectedWidth = model.imageWidth
    let expectedHeight = model.imageHeight

    guard image.width == expectedWidth && image.height == expectedHeight else {
      throw ImageError.invalidDimensions(
        expected: (expectedWidth, expectedHeight),
        actual: (image.width, image.height)
      )
    }

    if model == .sp1 {
      return encodeAsJPEG(image)
    }

    return encodeChannelSeparated(image)
  }

  /// Encode in channel-separated format (SP-2, SP-3)
  private func encodeChannelSeparated(_ image: CGImage) -> Data {
    let width = model.imageWidth
    let height = model.imageHeight

    guard let dataProvider = image.dataProvider,
          let pixelData = dataProvider.data as Data?
    else {
      return Data()
    }

    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow

    let totalBytes = width * height * 3
    var encodedBytes = [UInt8](repeating: 0, count: totalBytes)

    if model == .sp3 {
      // SP-3: 90° CW rotation during encoding
      // Output (w,h) ← Source (h, size-1-w)
      // Loop order optimized: source reads sequential within rows, target writes sequential within columns
      for w in 0 ..< width {
        let srcRow = height - 1 - w
        let srcRowBase = srcRow * bytesPerRow
        let targetBase = w * height * 3

        for h in 0 ..< height {
          let srcOffset = srcRowBase + h * bytesPerPixel
          encodedBytes[targetBase + h] = pixelData[srcOffset]
          encodedBytes[targetBase + height + h] = pixelData[srcOffset + 1]
          encodedBytes[targetBase + height * 2 + h] = pixelData[srcOffset + 2]
        }
      }
    } else {
      // SP-2: No rotation
      for h in 0 ..< height {
        let srcRowBase = h * bytesPerRow

        for w in 0 ..< width {
          let srcOffset = srcRowBase + w * bytesPerPixel
          let targetBase = w * height * 3
          encodedBytes[targetBase + h] = pixelData[srcOffset]
          encodedBytes[targetBase + height + h] = pixelData[srcOffset + 1]
          encodedBytes[targetBase + height * 2 + h] = pixelData[srcOffset + 2]
        }
      }
    }

    return Data(encodedBytes)
  }

  /// Encode as JPEG (SP-1)
  private func encodeAsJPEG(_ image: CGImage) -> Data {
    #if canImport(AppKit)
      let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
      guard let tiffData = nsImage.tiffRepresentation,
        let bitmapImage = NSBitmapImageRep(data: tiffData),
        let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
      else {
        return Data()
      }
      return jpegData
    #elseif canImport(UIKit)
      let uiImage = UIImage(cgImage: image)
      return uiImage.jpegData(compressionQuality: 0.9) ?? Data()
    #else
      return Data()
    #endif
  }

  /// Decode image data back to a CGImage (for testing/preview).
  public func decode(_ data: Data) throws -> CGImage {
    let width = model.imageWidth
    let height = model.imageHeight

    guard data.count == width * height * 3 else {
      throw ImageError.invalidData
    }

    var pixels = [UInt8](repeating: 255, count: width * height * 4) // RGBA

    if model == .sp3 {
      // SP-3: Reverse 90° CW rotation (apply 90° CCW)
      // Decoded (w,h) ← Encoded (size-1-h, w)
      for h in 0 ..< height {
        for w in 0 ..< width {
          let encW = height - 1 - h
          let encH = w
          let sourceBase = encW * height * 3
          let targetOffset = (h * width + w) * 4

          pixels[targetOffset] = data[sourceBase + encH]
          pixels[targetOffset + 1] = data[sourceBase + height + encH]
          pixels[targetOffset + 2] = data[sourceBase + height * 2 + encH]
          pixels[targetOffset + 3] = 255
        }
      }
    } else {
      // SP-2: No rotation
      for h in 0 ..< height {
        for w in 0 ..< width {
          let sourceBase = w * height * 3
          let targetOffset = (h * width + w) * 4

          pixels[targetOffset] = data[sourceBase + h]
          pixels[targetOffset + 1] = data[sourceBase + height + h]
          pixels[targetOffset + 2] = data[sourceBase + height * 2 + h]
          pixels[targetOffset + 3] = 255
        }
      }
    }

    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
      let decodedImage = context.makeImage()
    else {
      throw ImageError.processingFailed
    }

    return decodedImage
  }
}

/// Image processing errors.
public enum ImageError: Error, Sendable {
  case invalidDimensions(expected: (Int, Int), actual: (Int, Int))
  case processingFailed
  case invalidData
}
