import SwiftUI

struct QRCodeScannerView: View {
    let onScanned: (DittoConfigForDatabase) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRCameraPreview(onScanned: handleScanned)
                    .ignoresSafeArea()

                if isImporting {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView("Importing...")
                        .foregroundStyle(.white)
                        .tint(.white)
                }
            }
            .navigationTitle("Scan QR Code")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }

    private func handleScanned(_ config: DittoConfigForDatabase) {
        guard !isImporting else { return }
        isImporting = true
        onScanned(config)
    }
}

// MARK: - iOS Camera Preview

#if os(iOS)
import VisionKit

private struct QRCameraPreview: UIViewControllerRepresentable {
    let onScanned: (DittoConfigForDatabase) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScanned: (DittoConfigForDatabase) -> Void
        private var hasScanned = false

        init(onScanned: @escaping (DittoConfigForDatabase) -> Void) {
            self.onScanned = onScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue,
                   let data = payload.data(using: .utf8),
                   let config = try? JSONDecoder().decode(DittoConfigForDatabase.self, from: data)
                {
                    hasScanned = true
                    dataScanner.stopScanning()
                    onScanned(config)
                    return
                }
            }
        }
    }
}

// MARK: - macOS Camera Preview

#elseif os(macOS)
import AVFoundation

private struct QRCameraPreview: NSViewRepresentable {
    let onScanned: (DittoConfigForDatabase) -> Void

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.setup(coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    final class PreviewNSView: NSView {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?

        func setup(coordinator: Coordinator) {
            wantsLayer = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.startCapture(coordinator: coordinator)
                }
            }
        }

        private func startCapture(coordinator: Coordinator) {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let metadataOutput = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadataOutput) else { return }
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
            let supported = metadataOutput.availableMetadataObjectTypes
            guard supported.contains(.qr) else { return }
            metadataOutput.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
            previewLayer = preview
            preview.frame = bounds

            captureSession = session
            DispatchQueue.global(qos: .utility).async { [weak session] in
                session?.startRunning()
            }
        }

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onScanned: (DittoConfigForDatabase) -> Void
        private var hasScanned = false

        init(onScanned: @escaping (DittoConfigForDatabase) -> Void) {
            self.onScanned = onScanned
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned else { return }
            for object in metadataObjects {
                if let qrObject = object as? AVMetadataMachineReadableCodeObject,
                   let payload = qrObject.stringValue,
                   let data = payload.data(using: .utf8),
                   let config = try? JSONDecoder().decode(DittoConfigForDatabase.self, from: data)
                {
                    hasScanned = true
                    onScanned(config)
                    return
                }
            }
        }
    }
}
#endif
