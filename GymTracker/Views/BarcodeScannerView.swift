import SwiftUI
import VisionKit
import AVFoundation

/// Live barcode scanner. Falls back to typing the code where the camera is unavailable (Simulator).
struct BarcodeScannerView: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var cameraDenied = false

    private var scannerSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerSupported && !cameraDenied {
                    DataScannerRepresentable(onCode: onCode)
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            Text("Point the camera at the barcode.")
                                .padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 24)
                        }
                } else {
                    Form {
                        Section {
                            TextField("Barcode number", text: $manualCode).keyboardType(.numberPad)
                            Button("Look up") { onCode(manualCode.trimmingCharacters(in: .whitespaces)) }
                                .disabled(manualCode.trimmingCharacters(in: .whitespaces).count < 8)
                        } footer: {
                            Text(cameraDenied
                                 ? "Camera access is off. Enable it in Settings, or type the number under the barcode."
                                 : "The camera scanner is not available on this device. Type the number under the barcode.")
                        }
                    }
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                guard scannerSupported else { return }
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraDenied = !granted
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}
