import CoreGraphics
import Foundation
import ImageIO

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(UIKit)
  import UIKit
#endif


/// Encodes images for Instax printers.
public struct InstaxImageEncoder: Sendable {
  public let model: PrinterModel

  public init(model: PrinterModel) {
    self.model = model
  }

  /// Load and encode an image from a file URL.
  public func encode(from url: URL) throws -> Data {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      throw ImageError.loadFailed
    }

    let fittedImage = try fitImage(cgImage)
    return encodeForTransmission(fittedImage)
  }

  /// Encode a CGImage directly.
  public func encode(image: CGImage) throws -> Data {
    let fittedImage = try fitImage(image)
    return encodeForTransmission(fittedImage)
  }

  private func fitImage(_ image: CGImage) throws -> CGImage {
    let targetWidth = model.imageWidth
    let targetHeight = model.imageHeight

    // Calculate aspect-fit dimensions
    let sourceWidth = CGFloat(image.width)
    let sourceHeight = CGFloat(image.height)
    let targetSize = CGSize(width: targetWidth, height: targetHeight)

    let widthRatio = targetSize.width / sourceWidth
    let heightRatio = targetSize.height / sourceHeight

    // Use the larger ratio to ensure we cover the target (aspect-fill for cropping)
    let scale = max(widthRatio, heightRatio)

    let scaledWidth = sourceWidth * scale
    let scaledHeight = sourceHeight * scale

    // Center crop
    let x = (scaledWidth - targetSize.width) / 2
    let y = (scaledHeight - targetSize.height) / 2

    // Create context with white background
    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: targetHeight,
      bitsPerComponent: 8,
      bytesPerRow: targetWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      throw ImageError.contextCreationFailed
    }

    // Fill with white background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

    // Draw scaled and centered image
    let drawRect = CGRect(x: -x, y: -y, width: scaledWidth, height: scaledHeight)
    context.draw(image, in: drawRect)

    guard let resultImage = context.makeImage() else {
      throw ImageError.processingFailed
    }

    return resultImage
  }

  private func encodeForTransmission(_ image: CGImage) -> Data {
    // SP-1 uses JPEG encoding instead of channel-separated format
    if model == .sp1 {
      return encodeAsJPEG(image)
    }

    let outputWidth = model.imageWidth
    let outputHeight = model.imageHeight

    // Get raw pixel data
    guard let dataProvider = image.dataProvider,
          let pixelData = dataProvider.data as Data?
    else {
      return Data()
    }

    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow

    // Create output buffer: width * height * 3 (RGB only)
    let totalBytes = outputWidth * outputHeight * 3
    var encodedBytes = [UInt8](repeating: 0, count: totalBytes)

    // Encode in channel-separated format
    for h in 0 ..< outputHeight {
      for w in 0 ..< outputWidth {
        let srcOffset = h * bytesPerRow + w * bytesPerPixel

        let r = pixelData[srcOffset]
        let g = pixelData[srcOffset + 1]
        let b = pixelData[srcOffset + 2]

        // Target encoding formula (channel-separated, column-major)
        let redTarget = ((w * outputHeight) * 3) + (outputHeight * 0) + h
        let greenTarget = ((w * outputHeight) * 3) + (outputHeight * 1) + h
        let blueTarget = ((w * outputHeight) * 3) + (outputHeight * 2) + h

        encodedBytes[redTarget] = r
        encodedBytes[greenTarget] = g
        encodedBytes[blueTarget] = b
      }
    }

    return Data(encodedBytes)
  }

  /// Encode image as JPEG (for SP-1)
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

    // Reverse the channel-separated encoding back to raw pixels
    var pixels = [UInt8](repeating: 255, count: width * height * 4) // RGBA

    for h in 0 ..< height {
      for w in 0 ..< width {
        let redSource = ((w * height) * 3) + (height * 0) + h
        let greenSource = ((w * height) * 3) + (height * 1) + h
        let blueSource = ((w * height) * 3) + (height * 2) + h

        let targetOffset = (h * width + w) * 4
        pixels[targetOffset] = data[redSource]
        pixels[targetOffset + 1] = data[greenSource]
        pixels[targetOffset + 2] = data[blueSource]
        pixels[targetOffset + 3] = 255 // Alpha
      }
    }

    guard let pixelContext = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
      let decodedImage = pixelContext.makeImage()
    else {
      throw ImageError.processingFailed
    }

    return decodedImage
  }
}

/// Image processing errors.
public enum ImageError: Error, Sendable {
  case loadFailed
  case contextCreationFailed
  case processingFailed
  case invalidData
}
