import AVFoundation
import SwiftUI

struct QRCodeScannerView: View {
    let onScanned: (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var cameraAuthorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                switch cameraAuthorizationStatus {
                case .authorized:
                    QRCameraPreview(
                        onScanned: { config, favorites in handleScanned(config, favorites: favorites) },
                        onError: { message in handleScanError(message) }
                    )
                    .ignoresSafeArea()

                    if isImporting {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        ProgressView("Importing...")
                            .foregroundStyle(.white)
                            .tint(.white)
                    }

                    if let scanError {
                        scanErrorOverlay(message: scanError)
                    }

                case .denied:
                    permissionUnavailableView(
                        title: "Camera Access Denied",
                        message: "Edge Studio needs camera access to scan QR codes. Open Settings to grant access."
                    )

                case .restricted:
                    permissionUnavailableView(
                        title: "Camera Access Restricted",
                        message: "Camera access is restricted on this device. Check your device's parental or MDM controls."
                    )

                case .notDetermined:
                    permissionRequestingView

                @unknown default:
                    permissionUnavailableView(
                        title: "Camera Access Unavailable",
                        message: "Edge Studio cannot access the camera at this time."
                    )
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
        .onAppear {
            refreshAuthorizationStatus()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Re-check after returning from Settings.
            refreshAuthorizationStatus()
        }
        #endif
    }

    // MARK: - Permission Helpers

    private func refreshAuthorizationStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthorizationStatus = status
        if status == .notDetermined {
            requestAuthorization()
        }
    }

    private func requestAuthorization() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraAuthorizationStatus = granted ? .authorized : .denied
            }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func permissionUnavailableView(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "video.slash.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Open Settings") {
                openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var permissionRequestingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Requesting camera access...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanErrorOverlay(message: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Dismiss") {
                    scanError = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundColor(.black)
            }
            .padding()
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding()
        }
    }

    // MARK: - Scan Handlers

    private func handleScanned(_ config: DittoConfigForDatabase, favorites: [FavoriteQueryItem]) {
        guard !isImporting else { return }
        scanError = nil
        isImporting = true
        onScanned(config, favorites)
    }

    private func handleScanError(_ message: String) {
        // Surface the error in-sheet instead of auto-dismissing so the user can react.
        isImporting = false
        scanError = message
    }
}

// MARK: - iOS Camera Preview

#if os(iOS)
import VisionKit

private struct QRCameraPreview: UIViewControllerRepresentable {
    let onScanned: (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void
    let onError: (String) -> Void

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
        Coordinator(onScanned: onScanned, onError: onError)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScanned: (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void
        private let onError: (String) -> Void
        private var hasScanned = false

        init(
            onScanned: @escaping (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onScanned = onScanned
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue
                {
                    if let decoded = QRCodeGenerator.decode(from: payload) {
                        hasScanned = true
                        dataScanner.stopScanning()
                        onScanned(decoded.config, decoded.favorites)
                        return
                    } else {
                        onError("Scanned QR code is not a valid Edge Studio configuration.")
                    }
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError("Scanner unavailable: \(error.localizedDescription)")
        }
    }
}

// MARK: - macOS Camera Preview

#elseif os(macOS)

private struct QRCameraPreview: NSViewRepresentable {
    let onScanned: (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void
    let onError: (String) -> Void

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.setup(coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    final class PreviewNSView: NSView {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?

        func setup(coordinator: Coordinator) {
            wantsLayer = true
            // The parent view already gates this behind .authorized, but we keep the
            // requestAccess fallback for safety in case the status changes mid-flight.
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
        private let onScanned: (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void
        private let onError: (String) -> Void
        private var hasScanned = false

        init(
            onScanned: @escaping (DittoConfigForDatabase, [FavoriteQueryItem]) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onScanned = onScanned
            self.onError = onError
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned else { return }
            for object in metadataObjects {
                if let qrObject = object as? AVMetadataMachineReadableCodeObject,
                   let payload = qrObject.stringValue
                {
                    if let decoded = QRCodeGenerator.decode(from: payload) {
                        hasScanned = true
                        onScanned(decoded.config, decoded.favorites)
                        return
                    } else {
                        onError("Scanned QR code is not a valid Edge Studio configuration.")
                    }
                }
            }
        }
    }
}
#endif
