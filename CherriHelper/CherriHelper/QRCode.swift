// ===================================
// QR Code
// v0.0.1 BUILD 2026-11-21@15:45
// Turns the pairing link into a QR image. Moved out of PairingStore so the welcome screen and its previews can use it alone.
// dev by @dastefster 🍒🔨
// ===================================

import AppKit
import CoreImage


// ===================================
// QR CODE
// ===================================

enum QRCode {
    static func image(for string: String) -> NSImage? {
        guard !string.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.samplingNearest().transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }

        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
