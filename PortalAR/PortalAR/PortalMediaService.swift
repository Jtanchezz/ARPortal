import Foundation

struct PortalMediaItem: Decodable {
    enum MediaType: String, Decodable {
        case image
        case video
    }

    let id: String
    let title: String
    let type: MediaType
    let url: URL?
    let assetName: String?

    init(id: String, title: String, type: MediaType, url: URL?, assetName: String? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.url = url
        self.assetName = assetName
    }
}

struct PortalMediaConfiguration {
    let endpoint: URL?

    static let `default` = PortalMediaConfiguration(endpoint: nil)
}

final class PortalMediaService {
    private let configuration: PortalMediaConfiguration

    init(configuration: PortalMediaConfiguration = .default) {
        self.configuration = configuration
    }

    func loadMedia() async -> [PortalMediaItem] {
        let remoteItems = await fetchRemoteItems()
        if !remoteItems.isEmpty {
            return remoteItems + bundledItems()
        }

        if !Self.remoteSamples.isEmpty {
            return Self.remoteSamples + bundledItems()
        }

        return bundledItems()
    }

    private func fetchRemoteItems() async -> [PortalMediaItem] {
        guard let endpoint = configuration.endpoint else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            let decoded = try JSONDecoder().decode([PortalMediaItem].self, from: data)
            return decoded
        } catch {
            print("PortalMediaService error: \(error.localizedDescription)")
            return []
        }
    }

    private func bundledItems() -> [PortalMediaItem] {
        [
            PortalMediaItem(
                id: "bundle-001",
                title: "Loft creativo",
                type: .image,
                url: nil,
                assetName: "InteriorLoft"
            ),
            PortalMediaItem(
                id: "bundle-002",
                title: "Estudio minimal",
                type: .image,
                url: nil,
                assetName: "InteriorStudio"
            ),
            PortalMediaItem(
                id: "bundle-003",
                title: "Galería digital",
                type: .image,
                url: nil,
                assetName: "InteriorGallery"
            )
        ]
    }

    private static let remoteSamples: [PortalMediaItem] = [
        PortalMediaItem(
            id: "sample-001",
            title: "Concept Render",
            type: .image,
            url: URL(string: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80")
        ),
        PortalMediaItem(
            id: "sample-002",
            title: "UI Moodboard",
            type: .image,
            url: URL(string: "https://images.unsplash.com/photo-1523475472560-d2df97ec485c?auto=format&fit=crop&w=1200&q=80")
        ),
        PortalMediaItem(
            id: "sample-003",
            title: "Prototype",
            type: .image,
            url: URL(string: "https://images.unsplash.com/photo-1522199755839-a2bacb67c546?auto=format&fit=crop&w=1200&q=80")
        ),
        PortalMediaItem(
            id: "sample-004",
            title: "Motion Study",
            type: .image,
            url: URL(string: "https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1200&q=80")
        ),
        PortalMediaItem(
            id: "sample-005",
            title: "Lighting Demo",
            type: .image,
            url: URL(string: "https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=1200&q=80")
        ),
        PortalMediaItem(
            id: "sample-006",
            title: "Brand Showcase",
            type: .image,
            url: URL(string: "https://images.unsplash.com/photo-1460925895917-afdab827c52f?auto=format&fit=crop&w=1200&q=80")
        )
    ]
}
