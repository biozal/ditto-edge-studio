import SwiftUI

struct SubscriptionQRScannerView: View {
    let onScanned: (_ items: [SubscriptionQRItem], _ progress: @escaping @MainActor (Int, Int) -> Void) async -> Void
    @Environment(\.dismiss) private var dismiss

    private enum ScanState: Equatable {
        case scanning
        case importing(current: Int, total: Int)
    }

    @State private var scanState: ScanState = .scanning

    var body: some View {
        NavigationStack {
            ZStack {
                if case .scanning = scanState {
                    SubscriptionQRCameraPreview(onScanned: handleScanned)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }

                if case let .importing(current, total) = scanState {
                    VStack(spacing: 20) {
                        ProgressView(value: Double(current), total: Double(total))
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .padding(.horizontal, 40)
                        Text("Importing \(current) of \(total)…")
                            .foregroundStyle(.white)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Scan Subscriptions QR")
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

    private func handleScanned(_ items: [SubscriptionQRItem]) {
        guard case .scanning = scanState else { return }
        scanState = .importing(current: 0, total: items.count)
        Task { @MainActor in
            await onScanned(items) { current, total in
                scanState = .importing(current: current, total: total)
            }
            dismiss()
        }
    }
}

// MARK: - iOS Camera Preview

#if os(iOS)
import VisionKit

private struct SubscriptionQRCameraPreview: UIViewControllerRepresentable {
    let onScanned: ([SubscriptionQRItem]) -> Void

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
        private let onScanned: ([SubscriptionQRItem]) -> Void
        private var hasScanned = false

        init(onScanned: @escaping ([SubscriptionQRItem]) -> Void) {
            self.onScanned = onScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue,
                   let items = QRCodeGenerator.decodeSubscriptions(from: payload)
                {
                    hasScanned = true
                    dataScanner.stopScanning()
                    onScanned(items)
                    return
                }
            }
        }
    }
}

// MARK: - macOS Camera Preview

#elseif os(macOS)
import AVFoundation

private struct SubscriptionQRCameraPreview: NSViewRepresentable {
    let onScanned: ([SubscriptionQRItem]) -> Void

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
        private let onScanned: ([SubscriptionQRItem]) -> Void
        private var hasScanned = false

        init(onScanned: @escaping ([SubscriptionQRItem]) -> Void) {
            self.onScanned = onScanned
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned else { return }
            for object in metadataObjects {
                if let qrObject = object as? AVMetadataMachineReadableCodeObject,
                   let payload = qrObject.stringValue,
                   let items = QRCodeGenerator.decodeSubscriptions(from: payload)
                {
                    hasScanned = true
                    onScanned(items)
                    return
                }
            }
        }
    }
}
#endif
