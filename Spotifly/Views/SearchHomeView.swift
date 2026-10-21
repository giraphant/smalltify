//
//  SearchHomeView.swift
//  Spotifly
//
//  The search page before a search: recent searches.
//

import SwiftUI

/// Searches for a query through the toolbar's field, as if it had been typed there. A struct, as
/// `DismissAction` is, so the environment can compare it: every instance does the same thing.
struct RunSearchAction: Equatable {
    let run: (String) -> Void

    func callAsFunction(_ query: String) {
        run(query)
    }

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

extension EnvironmentValues {
    @Entry var runSearch = RunSearchAction { _ in }
}

/// The search page with nothing typed: the searches made last, which run again on a click, kept
/// on this Mac only. The toolbar's field takes the focus as it opens.
struct SearchHomeView: View {
    @Environment(SearchService.self) private var searchService
    @Environment(\.runSearch) private var runSearch

    var body: some View {
        Group {
            if searchService.recentSearches.isEmpty {
                ContentUnavailableView(
                    "search.no_recent",
                    systemImage: "magnifyingglass",
                    description: Text("search.no_recent_description"),
                )
            } else {
                Form {
                    Section {
                        ForEach(searchService.recentSearches, id: \.self) { query in
                            HStack {
                                Button {
                                    runSearch(query)
                                } label: {
                                    Text(verbatim: query)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    searchService.removeRecentSearch(query)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .named("search.remove_recent")
                            }
                        }
                    } header: {
                        Text("search.recent")
                    } footer: {
                        // Beside the footer, not a row of its own: the form boxes every row.
                        HStack {
                            Text("search.recent_footer")
                            Spacer()
                            Button("search.clear_recent") {
                                searchService.clearRecentSearches()
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .onAppear {
            focusToolbarSearchField()
        }
    }
}
