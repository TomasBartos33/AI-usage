import Foundation
import Observation

/// Owns the providers, decides when to refresh them and publishes normalized
/// snapshots to the UI.
///
/// Refresh strategy (conservative by design):
/// - file system events from the providers' local data (debounced by FSEvents),
/// - opening the menu (throttled inside providers),
/// - a single timer at the earliest known window reset,
/// - an optional low-frequency background timer,
/// - a once-a-minute clock tick so countdowns and staleness stay correct.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    private(set) var refreshing: Set<ProviderID> = []
    /// Coarse clock used by views for countdowns / staleness. Ticks once a minute.
    private(set) var now = Date()

    let preferences: Preferences

    @ObservationIgnored private var providers: [ProviderID: any UsageProvider] = [:]
    @ObservationIgnored private var pendingTriggers: [ProviderID: RefreshTrigger] = [:]
    @ObservationIgnored private var directoryWatchers: [DirectoryWatcher] = []
    @ObservationIgnored private var fileWatchers: [SingleFileWatcher] = []
    @ObservationIgnored private var clockTimer: Timer?
    @ObservationIgnored private var backgroundTimer: Timer?
    @ObservationIgnored private var resetTimer: Timer?
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private var started = false

    init(preferences: Preferences, cache: SnapshotCache = .default) {
        self.preferences = preferences
        self.cache = cache
    }

    var orderedProviderIDs: [ProviderID] { preferences.providerOrder }

    func provider(_ id: ProviderID) -> (any UsageProvider)? { providers[id] }

    func capabilities(of id: ProviderID) -> ProviderCapabilities {
        providers[id]?.capabilities ?? ProviderCapabilities(metrics: [])
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        configureProviders()
        startClock()
        rescheduleBackgroundTimer()
    }

    /// Rebuilds providers, e.g. after toggling demo mode or changing the Codex path.
    func configureProviders() {
        directoryWatchers.forEach { $0.stop() }
        fileWatchers.forEach { $0.stop() }
        directoryWatchers = []
        fileWatchers = []

        providers = ProviderFactory.makeProviders(preferences: preferences)
        snapshots = preferences.demoMode ? [:] : cache.load().filter { providers[$0.key] != nil }

        for (id, provider) in providers {
            let dirs = provider.watchedDirectories
            if !dirs.isEmpty, let watcher = DirectoryWatcher(paths: dirs, handler: { [weak self] paths in
                Task { @MainActor in
                    await provider.noteChangedPaths(paths)
                    self?.refresh(id, trigger: .fileChange)
                }
            }) {
                directoryWatchers.append(watcher)
            }
            for file in provider.watchedFiles {
                fileWatchers.append(SingleFileWatcher(url: file) { [weak self] in
                    Task { @MainActor in self?.refresh(id, trigger: .fileChange) }
                })
            }
        }
        refreshAll(trigger: .launch)
    }

    func rescheduleBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        let seconds = preferences.refreshInterval.rawValue
        guard seconds > 0 else { return }
        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll(trigger: .timer) }
        }
        timer.tolerance = TimeInterval(seconds) * 0.2
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    // MARK: Refreshing

    func menuOpened() {
        tick()
        guard preferences.refreshOnMenuOpen else { return }
        refreshAll(trigger: .menuOpened)
    }

    func refreshAll(trigger: RefreshTrigger) {
        for id in preferences.providerOrder where providers[id] != nil {
            refresh(id, trigger: trigger)
        }
    }

    /// Starts a refresh, or queues one if a refresh for this provider is already running.
    func refresh(_ id: ProviderID, trigger: RefreshTrigger) {
        guard let provider = providers[id] else { return }
        if refreshing.contains(id) {
            // Keep the strongest pending trigger (one that allows metadata queries wins).
            if pendingTriggers[id] == nil || trigger.allowsMetadataQuery {
                pendingTriggers[id] = trigger
            }
            return
        }
        refreshing.insert(id)
        let previous = snapshots[id]
        Task { [weak self] in
            let snapshot = await provider.refresh(trigger: trigger, previous: previous)
            await MainActor.run {
                guard let self else { return }
                // Ignore results from providers replaced while refreshing.
                guard let current = self.providers[id], current === provider else {
                    self.refreshing.remove(id)
                    return
                }
                self.apply(snapshot)
                self.refreshing.remove(id)
                if let next = self.pendingTriggers.removeValue(forKey: id) {
                    self.refresh(id, trigger: next)
                }
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot) {
        guard let current = snapshots[snapshot.provider] else {
            snapshots[snapshot.provider] = snapshot
            persistAndReschedule()
            return
        }
        // Ignore the refresh timestamp when deciding whether anything changed, so
        // frequent file-change refreshes don't rewrite the cache or re-render the menu bar.
        var comparable = current
        comparable.refreshedAt = snapshot.refreshedAt
        guard comparable != snapshot else { return }
        snapshots[snapshot.provider] = snapshot
        persistAndReschedule()
    }

    private func persistAndReschedule() {
        if !preferences.demoMode {
            cache.save(snapshots)
        }
        scheduleResetTimer()
    }

    // MARK: Timers

    private func startClock() {
        clockTimer?.invalidate()
        // Fire on minute boundaries so "resets in" values roll over in sync with the clock.
        let next = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func tick() {
        now = Date()
    }

    /// One timer at the earliest future window reset, so the UI and providers
    /// update exactly when a limit resets instead of polling for it.
    private func scheduleResetTimer() {
        resetTimer?.invalidate()
        resetTimer = nil
        let current = Date()
        let upcoming = snapshots.values.flatMap { snapshot in
            snapshot.windows.compactMap { window -> (ProviderID, Date)? in
                guard let resetsAt = window.resetsAt, resetsAt > current else { return nil }
                return (snapshot.provider, resetsAt)
            }
        }
        guard let earliest = upcoming.min(by: { $0.1 < $1.1 }) else { return }
        let timer = Timer(fire: earliest.1.addingTimeInterval(5), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                self?.refresh(earliest.0, trigger: .windowReset)
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        resetTimer = timer
    }
}
