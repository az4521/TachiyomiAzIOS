import Foundation

public struct Home: Sendable, Codable, Hashable {
    public var components: [HomeComponent]
    public init(components: [HomeComponent]) {
        self.components = components
    }
    public mutating func setSourceKey(_ key: String) {
        components = components.map {
            var component = $0
            component.setSourceKey(key)
            return component
        }
    }
}

public struct HomeComponent: Sendable, Codable, Hashable {
    public var title: String?
    public var subtitle: String?
    public var value: Value

    public init(title: String?, subtitle: String? = nil, value: Value) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
    }

    public enum Value: Sendable, Codable, Hashable {
        case imageScroller(links: [Link], autoScrollInterval: TimeInterval? = nil, width: Int? = nil, height: Int? = nil)
        case bigScroller(entries: [Manga], autoScrollInterval: TimeInterval? = nil)
        case scroller(entries: [Link], listing: Listing? = nil)
        case mangaList(ranking: Bool = false, pageSize: Int? = nil, entries: [Link], listing: Listing? = nil)
        case mangaChapterList(pageSize: Int? = nil, entries: [MangaWithChapter], listing: Listing? = nil)
        case filters([FilterItem])
        case links([Link])

        public var intValue: Int {
            switch self {
                case .imageScroller: 0
                case .bigScroller: 1
                case .scroller: 2
                case .mangaList: 3
                case .mangaChapterList: 4
                case .filters: 5
                case .links: 6
            }
        }

        public struct FilterItem: Sendable, Codable, Hashable {
            public var title: String
            public var values: [FilterValue]?
            public init(title: String, values: [FilterValue]?) {
                self.title = title
                self.values = values
            }
        }

        public struct Link: Codable, Hashable, Sendable {
            public var title: String
            public var subtitle: String?
            public var imageUrl: String?
            public var value: LinkValue?
            public init(title: String, imageUrl: String? = nil, subtitle: String? = nil, value: LinkValue? = nil) {
                self.title = title
                self.subtitle = subtitle
                self.imageUrl = imageUrl
                self.value = value
            }
        }

        public enum LinkValue: Codable, Hashable, Sendable {
            case url(String)
            case listing(Listing)
            case manga(Manga)
        }
    }

    mutating func setSourceKey(_ key: String) {
        func link(_ original: Value.Link) -> Value.Link {
            var result = original
            if case .manga(var manga) = result.value {
                manga.sourceKey = key
                result.value = .manga(manga)
            }
            return result
        }
        switch value {
            case let .imageScroller(links, interval, width, height):
                value = .imageScroller(links: links.map(link), autoScrollInterval: interval, width: width, height: height)
            case let .bigScroller(entries, interval):
                value = .bigScroller(
                    entries: entries.map {
                        var manga = $0
                        manga.sourceKey = key
                        return manga
                    },
                    autoScrollInterval: interval
                )
            case let .scroller(entries, listing):
                value = .scroller(entries: entries.map(link), listing: listing)
            case let .mangaList(ranking, pageSize, entries, listing):
                value = .mangaList(ranking: ranking, pageSize: pageSize, entries: entries.map(link), listing: listing)
            case let .mangaChapterList(pageSize, entries, listing):
                value = .mangaChapterList(
                    pageSize: pageSize,
                    entries: entries.map {
                        var entry = $0
                        entry.manga.sourceKey = key
                        return entry
                    },
                    listing: listing
                )
            case let .links(links):
                value = .links(links.map(link))
            case .filters:
                break
        }
    }
}

public enum HomePartialResult: Sendable, Codable {
    case layout(Home)
    case component(HomeComponent)
}
