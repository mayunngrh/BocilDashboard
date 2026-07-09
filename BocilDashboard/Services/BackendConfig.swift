import Foundation

/// Single source of truth for the CompanionServer connection. Every backend
/// service (Profile, Calendar, Config, Tasks, Memory, Conversation history,
/// audio playback) reads `baseURL`/`deviceToken` from here — change the IP,
/// port, or token once and it takes effect everywhere.
enum BackendConfig {
    static let baseURL = "http://10.235.115.130:8080"
    static let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"
}
