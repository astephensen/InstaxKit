import CoreGraphics
import Foundation
import ImageIO

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(UIKit)
  import UIKit
#endif

/// Image rotation options.
public enum ImageRotation: Int, Sendable {
  case none = 0
  case clockwise90 = 90
  case clockwise180 = 180
  case clockwise270 = 270

  var radians: CGFloat {
    CGFloat(rawValue) * .pi / 180
  }
}

/// Encodes images for Instax printers.
public struct InstaxImageEncoder: Sendable {
  public let model: PrinterModel

  public init(model: PrinterModel) {
    self.model = model
  }

  /// Load and encode an image from a file URL.
  public func encode(from url: URL, rotation: ImageRotation = .none) throws -> Data {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      throw ImageError.loadFailed
    }

    // Get EXIF orientation
    let orientation = getOrientation(from: imageSource)

    // Apply EXIF orientation
    var processedImage = applyOrientation(cgImage, orientation: orientation)

    // Apply user-requested rotation
    if rotation != .none {
      processedImage = rotateImage(processedImage, by: rotation)
    }

    // Resize and crop to fit
    let fittedImage = try fitImage(processedImage)

    // Encode for transmission
    return encodeForTransmission(fittedImage)
  }

  /// Encode a CGImage directly.
  public func encode(image: CGImage, rotation: ImageRotation = .none) throws -> Data {
    var processedImage = image
    if rotation != .none {
      processedImage = rotateImage(image, by: rotation)
    }
    let fittedImage = try fitImage(processedImage)
    return encodeForTransmission(fittedImage)
  }

  /// Rotate an image by the specified amount.
  private func rotateImage(_ image: CGImage, by rotation: ImageRotation) -> CGImage {
    let width = image.width
    let height = image.height

    // For 90 or 270 degree rotation, swap dimensions
    let newWidth: Int
    let newHeight: Int
    if rotation == .clockwise90 || rotation == .clockwise270 {
      newWidth = height
      newHeight = width
    } else {
      newWidth = width
      newHeight = height
    }

    guard let context = CGContext(
      data: nil,
      width: newWidth,
      height: newHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return image
    }

    // Move origin to center, rotate, then move back
    context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
    context.rotate(by: -rotation.radians) // Negative because CG rotates counter-clockwise
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    return context.makeImage() ?? image
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

    let width = model.imageWidth // printWidth in Python
    let height = model.imageHeight // printHeight in Python

    // Get raw pixel data
    guard let dataProvider = image.dataProvider,
          let pixelData = dataProvider.data as Data?
    else {
      return Data()
    }

    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow

    // Rotate image 90 degrees counter-clockwise for the printer
    // Then encode in the special channel-separated format

    // Create output buffer: width * height * 3 (RGB only)
    let totalBytes = width * height * 3
    var encodedBytes = [UInt8](repeating: 0, count: totalBytes)

    // The Python code rotates -90 degrees first if width != printWidth
    // For portrait orientation (thick edge at bottom)
    // We need to match the exact encoding: column-major, channel-separated

    for h in 0 ..< height {
      for w in 0 ..< width {
        // After rotation, we read from the source appropriately
        // Source is in row-major RGBA format

        let srcRow = h
        let srcCol = w
        let srcOffset = srcRow * bytesPerRow + srcCol * bytesPerPixel

        let r = pixelData[srcOffset]
        let g = pixelData[srcOffset + 1]
        let b = pixelData[srcOffset + 2]

        // Target encoding formula from Python:
        // redTarget = (((w * height) * 3) + (height * 0)) + h
        // greenTarget = (((w * height) * 3) + (height * 1)) + h
        // blueTarget = (((w * height) * 3) + (height * 2)) + h

        let redTarget = ((w * height) * 3) + (height * 0) + h
        let greenTarget = ((w * height) * 3) + (height * 1) + h
        let blueTarget = ((w * height) * 3) + (height * 2) + h

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
