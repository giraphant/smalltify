#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        /// SMALLTIFY_PLAYER: local (default), remote, idle, unpaired, starting, no-key,
        /// no-connect, pending, paused, repeat-all, repeat-one, queue-empty or queue-error.
        /// Combine with SMALLTIFY_OPEN=devices or mini, and SMALLTIFY_INSPECTOR=1.
        static var playerState: String { ProcessInfo.processInfo.environment["SMALLTIFY_PLAYER"] ?? "local" }

        static var remotePlayback: OfficialConnectPlayback {
            var snapshot = nowPlaying
            snapshot.speed = 0
            snapshot.shuffle = true
            snapshot.album = CatalogItem.parse(allTracks[0])?.album
            snapshot.releaseYear = "2024"
            return OfficialConnectPlayback(device: OfficialConnectDevice.parse(playerDevices[0]), snapshot: snapshot)
        }

        static var playerDevices: [[String: Any]] {
            [
                ["id": "speaker", "name": "客厅音箱", "type": "Speaker", "is_active": ["remote", "pending"].contains(playerState), "supports_volume": false],
                ["id": "phone", "name": "iPhone", "type": "Smartphone", "is_active": false, "supports_volume": true, "volume_percent": 60],
                ["id": "computer", "name": "书房电脑", "type": "Computer", "is_active": false, "supports_volume": true, "volume_percent": 40],
                ["name": "卧室电视", "type": "TV", "is_active": false, "supports_volume": false],
                ["id": "car", "name": "车载音响", "type": "Speaker", "is_active": false, "is_restricted": true, "supports_volume": false],
            ]
        }

        static func respondPlayer(_ request: FixtureRequest) -> (Int, Data, String)? {
            guard request.method == "GET" else { return nil }
            switch request.path {
            case "/me/player/devices": return ok(["devices": playerDevices])
            case "/me/player":
                guard ["remote", "pending"].contains(playerState) else { return (204, Data(), "application/json") }
                return ok(["device": playerDevices[0], "item": allTracks[0], "is_playing": true,
                           "progress_ms": 102_000, "shuffle_state": true, "repeat_state": "off"])
            case "/me/player/queue":
                if playerState == "queue-error" { return (500, Data(), "application/json") }
                if playerState == "queue-empty" { return ok(["currently_playing": allTracks[0], "queue": []]) }
                return ok(["currently_playing": allTracks[0], "queue": [10, 3, 15, 24, 11].map { allTracks[$0] }])
            default: return nil
            }
        }
    }
#endif
