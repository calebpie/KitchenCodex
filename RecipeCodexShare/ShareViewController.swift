import SwiftUI
import UIKit

/// Entry point for "Share → Recipe Codex" (Flow A). Phase 0 shows the shared URL and a Save
/// button that dismisses; Phase 1 parses JSON-LD through Capture and writes to the shared store.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharePreviewView(
            sharedURL: nil,
            onSave: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { [weak self, weak host] in
            let url = await Self.sharedURL(from: self?.extensionContext)
            host?.rootView.sharedURL = url
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private static func sharedURL(from context: NSExtensionContext?) async -> URL? {
        guard let items = context?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            for provider in item.attachments ?? [] where provider.canLoadObject(ofClass: URL.self) {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let url { return url }
            }
        }
        return nil
    }
}

struct SharePreviewView: View {
    var sharedURL: URL?
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(sharedURL?.host() ?? "Recipe Codex")
                    .font(.headline)
                Text(sharedURL?.absoluteString ?? "Reading the shared page…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Save Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}
