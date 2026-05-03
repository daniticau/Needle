import AppKit
import SwiftUI

@MainActor
final class ArtworkLoader: ObservableObject {
    @Published var image: NSImage?

    private var currentURL: URL?
    private var task: URLSessionDataTask?

    func load(_ url: URL?) {
        guard currentURL != url else { return }
        currentURL = url
        image = nil
        task?.cancel()

        guard let url else { return }

        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.image = image
            }
        }
        task?.resume()
    }
}
