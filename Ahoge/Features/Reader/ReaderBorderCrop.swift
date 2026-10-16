// Native adaptation of stable Mihon reader behavior.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import UIKit

extension ReaderImagePipelining {
    // A small uncropped thumbnail is enough to identify certain uniform borders.
    // This leaves the source and its anchors intact and avoids full resolution decoding.
    func borderCrop(for source: ReaderImageAssetSource) async throws -> CGRect {
        let preview = try await previewImage(for: source, variantKey: "border-probe",
            normalizedCropRect: CGRect(x: 0, y: 0, width: 1, height: 1), maxPixelSize: 256,
            colorTransform: ReaderColorTransform(filter: ReaderColorFilter(enabled: false, grayscale: 0, dimming: 0)), forceRefresh: false)
        try Task.checkCancellation()
        return await Task.detached(priority: .utility) { ReaderBorderBounds.detect(preview.image) }.value
    }
}

enum ReaderBorderBounds {
    static func detect(_ image: UIImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let cg = image.cgImage else { return full }
        let width = min(cg.width, 256), height = min(cg.height, 256)
        guard width >= 16, height >= 16 else { return full }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return full }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            let reference = [Int(pixels[0]), Int(pixels[1]), Int(pixels[2])]
            // Only reliably uniform nearly white/black borders qualify.
            guard reference.allSatisfy({ $0 > 240 }) || reference.allSatisfy({ $0 < 15 }) else { return full }
            func matches(_ x: Int, _ y: Int) -> Bool {
                let index = (y * width + x) * 4
                return pixels[index + 3] > 245 && (0..<3).allSatisfy { abs(Int(pixels[index + $0]) - reference[$0]) < 12 }
            }
            guard matches(width - 1, 0), matches(0, height - 1), matches(width - 1, height - 1) else { return full }
            func uniformRow(_ y: Int) -> Bool { (0..<width).allSatisfy { matches($0, y) } }
            func uniformColumn(_ x: Int) -> Bool { (0..<height).allSatisfy { matches(x, $0) } }
            var left = 0, right = width - 1, top = 0, bottom = height - 1
            while left < width / 6 && uniformColumn(left) { left += 1 }
            while right > width * 5 / 6 && uniformColumn(right) { right -= 1 }
            while top < height / 6 && uniformRow(top) { top += 1 }
            while bottom > height * 5 / 6 && uniformRow(bottom) { bottom -= 1 }
            // An edge still uniform at the safety limit is ambiguous; retain the original.
            guard !uniformColumn(left), !uniformColumn(right), !uniformRow(top), !uniformRow(bottom) else { return full }
            // Keep a one-thumbnail-pixel safety border to avoid shaving antialiased art.
            left = max(left - 1, 0); right = min(right + 1, width - 1)
            top = max(top - 1, 0); bottom = min(bottom + 1, height - 1)
            return CGRect(x: Double(left) / Double(width), y: Double(top) / Double(height),
                width: Double(right - left + 1) / Double(width), height: Double(bottom - top + 1) / Double(height))
        }
    }
}
