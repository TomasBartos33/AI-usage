import CoreServices
import Foundation

/// Recursive directory watcher based on FSEvents. Events are coalesced by the
/// kernel using `latency`, so a burst of writes produces a single callback.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "AIUsage.DirectoryWatcher", qos: .utility)
    private let handler: @Sendable ([String]) -> Void

    /// - Parameter handler: called on a background queue with the changed paths.
    init?(paths: [URL], latency: TimeInterval = 2.0, handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
        let existing = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            watcher.handler(Array(paths.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagIgnoreSelf)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit { stop() }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Watches a single file with a kqueue vnode source. Handles atomic saves
/// (write to temp + rename) by re-opening the path after delete/rename events,
/// and waits for the file to appear if it does not exist yet.
final class SingleFileWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "AIUsage.SingleFileWatcher", qos: .utility)
    private let handler: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var retryWork: DispatchWorkItem?
    private var notifyWork: DispatchWorkItem?
    private var stopped = false

    init(url: URL, handler: @escaping @Sendable () -> Void) {
        self.url = url
        self.handler = handler
        queue.async { [weak self] in self?.open() }
    }

    deinit {
        source?.cancel()
        retryWork?.cancel()
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopped = true
            self?.source?.cancel()
            self?.source = nil
            self?.retryWork?.cancel()
        }
    }

    private func open() {
        guard !stopped else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry(after: 120)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let event = source.data
            self.scheduleNotification()
            if !event.isDisjoint(with: [.delete, .rename, .revoke]) {
                source.cancel()
                self.source = nil
                // The replacement file usually exists already after an atomic save.
                self.scheduleRetry(after: 0.5)
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    /// Coalesces bursts of writes (some tools rewrite their state file several times per second).
    private func scheduleNotification() {
        notifyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handler() }
        notifyWork = work
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.open() }
        retryWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
