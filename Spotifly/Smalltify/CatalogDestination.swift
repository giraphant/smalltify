import Foundation

nonisolated enum CatalogDestination {
    case section(String)
    case artist(CatalogArtist, group: String)
    case collection(CatalogItem)
}
