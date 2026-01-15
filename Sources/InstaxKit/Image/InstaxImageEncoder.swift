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
  public func encode(from url: URL, orientation: InstaxOrientation = .portrait) throws -> Data {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      throw ImageError.loadFailed
    }

    // Get EXIF orientation and apply it
    let exifOrientation = getOrientation(from: imageSource)
    let processedImage = applyOrientation(cgImage, orientation: exifOrientation)

    // Resize and crop to fit the target dimensions for this orientation
    let fittedImage = try fitImage(processedImage, for: orientation)

    // Encode for transmission (rotation is applied during encoding)
    return encodeForTransmission(fittedImage, for: orientation)
  }

  /// Encode a CGImage directly.
  public func encode(image: CGImage, orientation: InstaxOrientation = .portrait) throws -> Data {
    // Resize and crop to fit the target dimensions for this orientation
    let fittedImage = try fitImage(image, for: orientation)

    // Encode for transmission (rotation is applied during encoding)
    return encodeForTransmission(fittedImage, for: orientation)
  }

  private func getOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32
    else {
      return .up
    }
    return CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
  }

  private func applyOrientation(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
    guard orientation != .up else { return image }

    let width = image.width
    let height = image.height

    var transform = CGAffineTransform.identity
    var newSize = CGSize(width: width, height: height)

    switch orientation {
    case .up, .upMirrored:
      break
    case .down, .downMirrored:
      transform = transform.translatedBy(x: CGFloat(width), y: CGFloat(height))
      transform = transform.rotated(by: .pi)
    case .left, .leftMirrored:
      newSize = CGSize(width: height, height: width)
      transform = transform.translatedBy(x: CGFloat(height), y: 0)
      transform = transform.rotated(by: .pi / 2)
    case .right, .rightMirrored:
      newSize = CGSize(width: height, height: width)
      transform = transform.translatedBy(x: 0, y: CGFloat(width))
      transform = transform.rotated(by: -.pi / 2)
    }

    switch orientation {
    case .upMirrored, .downMirrored:
      transform = transform.translatedBy(x: CGFloat(width), y: 0)
      transform = transform.scaledBy(x: -1, y: 1)
    case .leftMirrored, .rightMirrored:
      transform = transform.translatedBy(x: CGFloat(height), y: 0)
      transform = transform.scaledBy(x: -1, y: 1)
    default:
      break
    }

    guard let context = CGContext(
      data: nil,
      width: Int(newSize.width),
      height: Int(newSize.height),
      bitsPerComponent: image.bitsPerComponent,
      bytesPerRow: 0,
      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: image.bitmapInfo.rawValue
    ) else {
      return image
    }

    context.concatenate(transform)

    let rect = switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored:
      CGRect(x: 0, y: 0, width: height, height: width)
    default:
      CGRect(x: 0, y: 0, width: width, height: height)
    }

    context.draw(image, in: rect)

    return context.makeImage() ?? image
  }

  private func fitImage(_ image: CGImage, for orientation: InstaxOrientation) throws -> CGImage {
    // For landscape orientations, swap target dimensions
    let targetWidth: Int
    let targetHeight: Int
    if orientation.swapsDimensions {
      targetWidth = model.imageHeight
      targetHeight = model.imageWidth
    } else {
      targetWidth = model.imageWidth
      targetHeight = model.imageHeight
    }

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

  private func encodeForTransmission(_ image: CGImage, for orientation: InstaxOrientation) -> Data {
    // SP-1 uses JPEG encoding instead of channel-separated format
    if model == .sp1 {
      return encodeAsJPEG(image, for: orientation)
    }

    // Printer always expects data in native dimensions (width x height)
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
    let sourceWidth = image.width
    let sourceHeight = image.height

    // Create output buffer: width * height * 3 (RGB only)
    let totalBytes = outputWidth * outputHeight * 3
    var encodedBytes = [UInt8](repeating: 0, count: totalBytes)

    // Encode in channel-separated format, rotating as needed for orientation
    for h in 0 ..< outputHeight {
      for w in 0 ..< outputWidth {
        // Calculate source coordinates based on orientation
        let srcRow: Int
        let srcCol: Int

        switch orientation {
        case .portrait:
          // No rotation - direct mapping
          // Source 600×800 → Output 600×800
          srcRow = h
          srcCol = w
        case .landscape:
          // 90° clockwise rotation to convert landscape to portrait
          // Source 800×600 → Output 600×800
          srcRow = w
          srcCol = sourceWidth - 1 - h
        case .portraitFlipped:
          // 180° rotation
          // Source 600×800 → Output 600×800
          srcRow = sourceHeight - 1 - h
          srcCol = sourceWidth - 1 - w
        case .landscapeFlipped:
          // 90° counter-clockwise rotation (270° clockwise)
          // Source 800×600 → Output 600×800
          srcRow = sourceHeight - 1 - w
          srcCol = h
        }

        let srcOffset = srcRow * bytesPerRow + srcCol * bytesPerPixel

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
  private func encodeAsJPEG(_ image: CGImage, for orientation: InstaxOrientation) -> Data {
    // For SP-1, rotate the image first if needed for orientation
    var rotatedImage = image
    if orientation != .portrait {
      rotatedImage = rotateImageForJPEG(image, for: orientation)
    }

    #if canImport(AppKit)
      let nsImage = NSImage(cgImage: rotatedImage, size: NSSize(width: rotatedImage.width, height: rotatedImage.height))
      guard let tiffData = nsImage.tiffRepresentation,
        let bitmapImage = NSBitmapImageRep(data: tiffData),
        let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
      else {
        return Data()
      }
      return jpegData
    #elseif canImport(UIKit)
      let uiImage = UIImage(cgImage: rotatedImage)
      return uiImage.jpegData(compressionQuality: 0.9) ?? Data()
    #else
      return Data()
    #endif
  }

  /// Rotate image for JPEG encoding (SP-1)
  private func rotateImageForJPEG(_ image: CGImage, for orientation: InstaxOrientation) -> CGImage {
    let sourceWidth = CGFloat(image.width)
    let sourceHeight = CGFloat(image.height)

    // Output dimensions for printer's native format
    let outputWidth = model.imageWidth
    let outputHeight = model.imageHeight

    guard let context = CGContext(
      data: nil,
      width: outputWidth,
      height: outputHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return image
    }

    // Apply rotation transform centered on output
    context.translateBy(x: CGFloat(outputWidth) / 2, y: CGFloat(outputHeight) / 2)

    switch orientation {
    case .portrait:
      // No rotation needed
      context.translateBy(x: -sourceWidth / 2, y: -sourceHeight / 2)
    case .landscape:
      // 90° clockwise - after rotation, source height becomes width
      context.rotate(by: .pi / 2)
      context.translateBy(x: -sourceHeight / 2, y: -sourceWidth / 2)
    case .portraitFlipped:
      // 180° rotation
      context.rotate(by: .pi)
      context.translateBy(x: -sourceWidth / 2, y: -sourceHeight / 2)
    case .landscapeFlipped:
      // 90° counter-clockwise - after rotation, source height becomes width
      context.rotate(by: -.pi / 2)
      context.translateBy(x: -sourceHeight / 2, y: -sourceWidth / 2)
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))

    return context.makeImage() ?? image
  }

  /// Decode image data back to a CGImage (for testing/preview).
  public func decode(_ data: Data) throws -> CGImage {
    let width = model.imageWidth
    let height = model.imageHeight

    guard data.count == width * height * 3 else {
      throw ImageError.invalidData
    }

    // Reverse the encoding
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

    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
      let image = context.makeImage()
    else {
      throw ImageError.processingFailed
    }

    return image
  }
}

/// Image processing errors.
public enum ImageError: Error, Sendable {
  case loadFailed
  case contextCreationFailed
  case processingFailed
  case invalidData
}
