import Capture
import SwiftUI
import UIKit
import Vision
import VisionKit

/// Add Cookbook's barcode scanner (Flow C step 1, 01 §2.3): VisionKit's `DataScannerViewController`
/// reading EAN-13, the barcode an ISBN is printed as. The app has no camera usage description yet,
/// and the camera refuses without one, so the scanner stays hidden until the Info dictionary
/// carries `NSCameraUsageDescription` (phase2-plan "What Caleb supplies"); the simulator never
/// shows it either, having no camera.
enum ISBNScanner {
    /// Whether to offer the scanner: a camera usage description, then a device that can scan.
    @MainActor
    static var isAvailable: Bool {
        // The description first, so the scanner is never touched without one.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else { return false }
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}

/// The scanner full screen with Cancel; the first barcode that reads as an ISBN ends it.
struct ISBNScannerSheet: View {
    var onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ISBNScannerView(onScan: onScan)
                .ignoresSafeArea()
                .navigationTitle("Scan Barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text("Point the camera at the barcode on the back cover.")
                        .font(.subheadline)
                        .padding()
                        .glassEffect()
                        .padding()
                }
        }
    }
}

/// `DataScannerViewController` for EAN-13 barcodes, reporting the first one that is an ISBN
/// (978 or 979; other EAN-13s are product codes).
private struct ISBNScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item, let payload = barcode.payloadStringValue,
                      let isbn = ISBN.normalized(payload) else { continue }
                hasScanned = true
                dataScanner.stopScanning()
                onScan(isbn)
                return
            }
        }
    }
}
