import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCodeGenerator {
    static func generate(from config: DittoConfigForDatabase) -> Image? {
        guard let data = try? JSONEncoder().encode(config) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
