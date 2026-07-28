import AppKit
import QuickLookUI

@MainActor
final class QuickLookPreviewCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewCoordinator()
    private var url: URL?

    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(
        _ panel: QLPreviewPanel!,
        previewItemAt index: Int
    ) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}
