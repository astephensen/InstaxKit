import InstaxKit
import SwiftUI

struct PolaroidView: View {
  let image: NSImage?
  let printerModel: PrinterModel

  // Polaroid frame dimensions (relative to image)
  private let topBorder: CGFloat = 0.08
  private let sideBorder: CGFloat = 0.06
  private let bottomBorder: CGFloat = 0.20 // Thick bottom edge

  private var imageWidth: CGFloat {
    CGFloat(printerModel.imageWidth)
  }

  private var imageHeight: CGFloat {
    CGFloat(printerModel.imageHeight)
  }

  private var aspectRatio: CGFloat {
    imageWidth / imageHeight
  }

  // Calculate polaroid dimensions
  private var polaroidWidth: CGFloat {
    imageWidth * (1 + sideBorder * 2)
  }

  private var polaroidHeight: CGFloat {
    imageHeight * (1 + topBorder + bottomBorder)
  }

  private var polaroidAspectRatio: CGFloat {
    polaroidWidth / polaroidHeight
  }

  var body: some View {
    GeometryReader { geometry in
      let availableSize = geometry.size
      let scale = min(
        availableSize.width / polaroidWidth,
        availableSize.height / polaroidHeight
      ) * 0.9 // Leave some margin

      let displayWidth = polaroidWidth * scale
      let displayHeight = polaroidHeight * scale
      let imageDisplayWidth = imageWidth * scale
      let imageDisplayHeight = imageHeight * scale
      let topPadding = imageHeight * topBorder * scale

      ZStack {
        // Polaroid frame (white background with shadow)
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.white)
          .frame(width: displayWidth, height: displayHeight)
          .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

        // Image area
        VStack(spacing: 0) {
          Spacer()
            .frame(height: topPadding)

          ZStack {
            // Image background (dark gray when no image)
            Rectangle()
              .fill(Color(white: 0.15))
              .frame(width: imageDisplayWidth, height: imageDisplayHeight)

            // The actual image
            if let image {
              Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: imageDisplayWidth, height: imageDisplayHeight)
                .clipped()
            } else {
              // Placeholder
              VStack(spacing: 8) {
                Image(systemName: "photo")
                  .font(.system(size: 40))
                  .foregroundColor(.gray)
                Text("Waiting for print...")
                  .font(.caption)
                  .foregroundColor(.gray)
              }
            }
          }

          Spacer()
        }
        .frame(width: displayWidth, height: displayHeight)

      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

#Preview("With Image") {
  let testImage = NSImage(size: NSSize(width: 600, height: 800), flipped: false) { rect in
    NSColor.systemBlue.setFill()
    rect.fill()
    return true
  }

  return PolaroidView(image: testImage, printerModel: .sp2)
    .frame(width: 400, height: 500)
    .background(Color.gray.opacity(0.2))
}

#Preview("Empty SP-1") {
  PolaroidView(image: nil, printerModel: .sp1)
    .frame(width: 400, height: 500)
    .background(Color.gray.opacity(0.2))
}

#Preview("Empty SP-2") {
  PolaroidView(image: nil, printerModel: .sp2)
    .frame(width: 400, height: 500)
    .background(Color.gray.opacity(0.2))
}

#Preview("Empty SP-3") {
  PolaroidView(image: nil, printerModel: .sp3)
    .frame(width: 400, height: 500)
    .background(Color.gray.opacity(0.2))
}
