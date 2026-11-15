// De webcam voor de foto van een onderdeel, en het verkleinen van een foto voordat hij naar Claude en de schijf gaat.
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@Observable @MainActor final class Camera: NSObject, AVCapturePhotoCaptureDelegate {
    var name = ""
    var problem: String?
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private var done: ((Data?) -> Void)?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            problem = "De Mac mag de camera niet gebruiken. Zet het aan in Systeeminstellingen > Privacy en beveiliging > Camera."; return
        }
        guard session.inputs.isEmpty else { run(); return }
        guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev) else { problem = "Geen camera gevonden. Kies dan een foto."; return }
        name = dev.localizedName
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        run()
    }

    private func run() {
        nonisolated(unsafe) let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }   // startRunning blokkeert even
    }

    func stop() {
        nonisolated(unsafe) let s = session
        DispatchQueue.global().async { s.stopRunning() }
    }

    func shoot() async -> Data? {
        guard session.isRunning else { return nil }
        return await withCheckedContinuation { c in
            done = { c.resume(returning: $0) }
            output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in self.done?(data); self.done = nil }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        v.layer = layer
        v.wantsLayer = true
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

enum Photo {
    // Een JPEG met de langste kant hooguit `side` pixels: klein genoeg voor Claude en de schijf, scherp genoeg voor de draadjes.
    static func jpeg(_ data: Data, side: CGFloat = 1600) -> Data? {
        guard let src = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let s = min(1, side / CGFloat(max(src.width, src.height)))
        let w = Int(CGFloat(src.width) * s), h = Int(CGFloat(src.height) * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }

    @MainActor static func choose() -> Data? {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Kies een foto van het onderdeel"
        guard p.runModal() == .OK, let u = p.url else { return nil }
        return try? Data(contentsOf: u)
    }
}
