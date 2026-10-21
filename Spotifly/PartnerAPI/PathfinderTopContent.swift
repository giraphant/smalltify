//
//  PathfinderTopContent.swift
//  Spotifly
//
//  The listener's top tracks and artists, as the web player's profile page reads them.
//

import Foundation

/// The span a top list covers. The raw values are the only three `AffinityTimeRange` takes:
/// `MEDIUM_TERM`, the Web API's word, is refused with 400 (measured 2026-10-21).
nonisolated enum TopContentRange: String, CaseIterable, Encodable, Sendable {
    /// About four weeks.
    case short = "SHORT_TERM"
    /// About six months.
    case mid = "MID_TERM"
    /// About a year.
    case long = "LONG_TERM"
}

/// `{ "data": { "me": { "profile": { "topArtists": …, "topTracks": … } } } }`
nonisolated struct PathfinderTopContentResponse: Decodable, Sendable {
    struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            let data: Item?
        }

        let items: [Entry]?
    }

    struct Profile: Decodable, Sendable {
        let topArtists: Page<PathfinderArtist>?
        let topTracks: Page<PathfinderTrack>?
    }

    struct Me: Decodable, Sendable {
        let profile: Profile?
    }

    struct Payload: Decodable, Sendable {
        let me: Me?
    }

    let data: Payload?
}

/// On the main actor, where the entities' initializers are.
extension PathfinderTopContentResponse {
    var tracks: [Track] {
        (data?.me?.profile?.topTracks?.items ?? []).compactMap { $0.data.flatMap(Track.init(pathfinder:)) }
    }

    var artists: [Artist] {
        (data?.me?.profile?.topArtists?.items ?? []).compactMap { $0.data.flatMap(Artist.init(pathfinder:)) }
    }
}

/// The variables `userTopContent` takes, as the web player sends them: both lists, sorted by
/// affinity, over one range.
nonisolated struct PathfinderTopContentVariables: Encodable, Sendable {
    struct Input: Encodable, Sendable {
        var offset = 0
        let limit: Int
        var sortBy = "AFFINITY"
        let timeRange: TopContentRange
    }

    var includeTopArtists = true
    let topArtistsInput: Input
    var includeTopTracks = true
    let topTracksInput: Input

    init(range: TopContentRange, limit: Int) {
        topArtistsInput = Input(limit: limit, timeRange: range)
        topTracksInput = Input(limit: limit, timeRange: range)
    }
}
