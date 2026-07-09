import Foundation
import Combine

/// Single source of truth for the CompanionServer connection. Every backend
/// service (Profile, Calendar, Config, Tasks, Memory, Conversation history,
/// audio playback) reads `baseURL`/`deviceToken` from here — change the IP
/// or port once (persisted, editable from Settings) and it takes effect
/// everywhere immediately, since services read this live rather than caching
/// it at init.
enum BackendConfig {
    private static let baseURLKey = "backend_base_url"
    static let defaultBaseURL = "http://10.235.115.130:8080"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"
}

/// Publishes `BackendConfig.baseURL` changes so SwiftUI views (the Settings
/// field, the status pill) can observe and re-render without a restart.
@MainActor
final class BackendConfigStore: ObservableObject {
    @Published var baseURL: String = BackendConfig.baseURL {
        didSet { BackendConfig.baseURL = baseURL }
    }

    func resetToDefault() {
        baseURL = BackendConfig.defaultBaseURL
    }
}
