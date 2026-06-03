import AppKit

class FileExportService {
    /// Saved screenshots are encoded as JPEG and kept at or below this size.
    private static let maxJPEGBytes = 2 * 1024 * 1024  // 2 MB

    static func saveImage(_ image: NSImage, defaultName: String? = nil) {
        let panel = NSSavePanel()
        // JPEG first — it's the default. PNG stays available for a lossless save.
        panel.allowedFileTypes = ["jpg", "jpeg", "png"]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.nameFieldStringValue = defaultName ?? "Screenshot_\(timestamp()).jpg"
        panel.directoryURL = UserSettings.shared.saveDirectory

        panel.level = .floating

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            saveImageToFile(image, url: url)
        }
    }

    static func quickSave(_ image: NSImage) {
        let saveDir = UserSettings.shared.saveDirectory
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let fileURL = saveDir.appendingPathComponent("Screenshot_\(timestamp()).jpg")

        saveImageToFile(image, url: fileURL)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func saveImageToFile(_ image: NSImage, url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let data: Data?
        if url.pathExtension.lowercased() == "png" {
            // Explicit PNG request — keep it lossless, no size cap.
            data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        } else {
            // Default: JPEG compressed to stay within maxJPEGBytes.
            data = jpegData(from: cgImage, underByteLimit: maxJPEGBytes)
        }

        do {
            try data?.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = L("alert.save.failed")
            alert.informativeText = L("alert.save.failed.msg", error.localizedDescription)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("alert.ok"))
            alert.runModal()
        }
    }

    /// Encode to JPEG, lowering quality first and downscaling only as a last
    /// resort, until the data fits under `limit`. Returns the smallest result we
    /// produced if even aggressive compression can't reach the limit.
    private static func jpegData(from cgImage: CGImage, underByteLimit limit: Int) -> Data? {
        func encode(_ cg: CGImage, _ quality: CGFloat) -> Data? {
            NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        // Quality sweep at full resolution — handles the overwhelming majority.
        var smallest: Data?
        for q in stride(from: 0.9, through: 0.4, by: -0.1) {
            guard let data = encode(cgImage, CGFloat(q)) else { continue }
            if data.count <= limit { return data }
            smallest = data  // strictly decreasing, so this is the smallest so far
        }

        // Still over the limit at lowest quality (e.g. a busy 6K fullscreen) —
        // downscale progressively at a mid quality until it fits.
        var factor: CGFloat = 0.85
        for _ in 0..<6 {
            guard let scaled = downscaled(cgImage, by: factor) else { break }
            if let data = encode(scaled, 0.6) {
                if data.count <= limit { return data }
                smallest = data
            }
            factor *= 0.85
        }
        return smallest
    }

    private static func downscaled(_ cgImage: CGImage, by factor: CGFloat) -> CGImage? {
        let width = Int((CGFloat(cgImage.width) * factor).rounded())
        let height = Int((CGFloat(cgImage.height) * factor).rounded())
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
