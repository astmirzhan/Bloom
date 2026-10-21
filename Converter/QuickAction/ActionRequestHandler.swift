import AppKit

/// "Convert with Bloom" in Finder's Quick Actions (right-click and the
/// preview pane). App extensions must be sandboxed, so this one converts
/// nothing itself: it opens the chosen files with Bloom, which shows
/// its format menu at the pointer and saves the results beside them.
final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    /// The extension context and its items are only used from this request.
    /// A box rather than `nonisolated(unsafe)` locals, which Xcode 26's
    /// compiler still rejects when the closure is passed as `sending`.
    private struct Request: @unchecked Sendable {
        let context: NSExtensionContext
        let items: [NSExtensionItem]
    }

    func beginRequest(with context: NSExtensionContext) {
        let request = Request(context: context, items: context.inputItems.compactMap { $0 as? NSExtensionItem })
        Task {
            let context = request.context
            let urls = await QuickActionSupport.fileURLs(from: request.items)
            guard !urls.isEmpty, let app = QuickActionSupport.hostApp(of: Bundle.main.bundleURL) else {
                context.cancelRequest(withError: CocoaError(.fileNoSuchFile))
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
                context.completeRequest(returningItems: nil)
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }
}
