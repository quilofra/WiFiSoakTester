import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum DownloadWorkerError: Error {
    case noEndpointAvailable
    case invalidHTTPStatus(Int)
    case lowPerformance(currentRateBps: Double)
}

private actor ChunkProcessor {
    private let workerID: Int
    private let url: URL
    private let configuration: DownloadConfiguration
    private let metricsStore: MetricsStore
    private let sink: any ByteSink
    private let rateLimiter: RateLimiter?

    private var bytesSinceRateCheck: Int64 = 0
    private var lowRateElapsed: TimeInterval = 0
    private var lastRateCheck = Date()

    init(
        workerID: Int,
        url: URL,
        configuration: DownloadConfiguration,
        metricsStore: MetricsStore,
        sink: any ByteSink,
        rateLimiter: RateLimiter?
    ) {
        self.workerID = workerID
        self.url = url
        self.configuration = configuration
        self.metricsStore = metricsStore
        self.sink = sink
        self.rateLimiter = rateLimiter
    }

    func process(_ data: Data) async throws {
        guard !data.isEmpty else { return }

        try await sink.consume(data)

        let count = Int64(data.count)
        await metricsStore.recordBytes(workerID: workerID, bytes: count, url: url)
        if let rateLimiter {
            await rateLimiter.acquire(bytes: count)
        }

        bytesSinceRateCheck += count
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRateCheck)
        guard elapsed >= 1 else { return }

        let currentRate = Double(bytesSinceRateCheck) / elapsed
        if configuration.minRateBps > 0 {
            if currentRate < configuration.minRateBps {
                lowRateElapsed += elapsed
            } else {
                lowRateElapsed = 0
            }

            if lowRateElapsed >= max(configuration.switchAfterSeconds, 1) {
                throw DownloadWorkerError.lowPerformance(currentRateBps: currentRate)
            }
        }

        bytesSinceRateCheck = 0
        lastRateCheck = now
    }
}

#if os(Windows)
private final class ChunkResultBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var error: Error?
}

private final class WindowsStreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let processor: ChunkProcessor
    private let lock = NSLock()
    private var completion: CheckedContinuation<Void, Error>?
    private var pendingError: Error?
    private var activeTask: URLSessionDataTask?

    init(processor: ChunkProcessor) {
        self.processor = processor
    }

    func stream(request: URLRequest, session: URLSession) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                completion = continuation
                let task = session.dataTask(with: request)
                activeTask = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: {
            self.cancel()
        })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            setPendingError(DownloadWorkerError.invalidHTTPStatus(http.statusCode))
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let box = ChunkResultBox()

        Task {
            do {
                try await self.processor.process(data)
            } catch {
                box.error = error
            }
            box.semaphore.signal()
        }

        box.semaphore.wait()

        if let error = box.error {
            setPendingError(error)
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error>

        if let pendingError = takePendingError() {
            result = .failure(pendingError)
        } else if let error {
            result = .failure(error)
        } else {
            result = .success(())
        }

        finish(with: result)
    }

    private func cancel() {
        lock.lock()
        let task = activeTask
        let continuation = completion
        activeTask = nil
        completion = nil
        lock.unlock()

        task?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    private func setPendingError(_ error: Error) {
        lock.lock()
        if pendingError == nil {
            pendingError = error
        }
        lock.unlock()
    }

    private func takePendingError() -> Error? {
        lock.lock()
        let error = pendingError
        pendingError = nil
        lock.unlock()
        return error
    }

    private func finish(with result: Result<Void, Error>) {
        lock.lock()
        let continuation = completion
        completion = nil
        activeTask = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
#endif

final class DownloadCoordinator: @unchecked Sendable {
    private let configuration: DownloadConfiguration
    private let metricsStore: MetricsStore
    private let rotator: URLRotator
    private let sink: any ByteSink
    private let rateLimiter: RateLimiter?
    private let onSnapshot: @Sendable (MetricsSnapshot) -> Void
    private let onFinished: @Sendable ([SessionSample]) -> Void
    private let onEvent: @Sendable (String) -> Void
    private let onError: @Sendable (String) -> Void

    private var workerTasks: [Task<Void, Never>] = []
    private var tickerTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?

    private let stateLock = NSLock()
    private var hasStopped = false

    init(
        configuration: DownloadConfiguration,
        sink: any ByteSink,
        onSnapshot: @escaping @Sendable (MetricsSnapshot) -> Void,
        onFinished: @escaping @Sendable ([SessionSample]) -> Void,
        onEvent: @escaping @Sendable (String) -> Void = { _ in },
        onError: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.metricsStore = MetricsStore(sampleCapacity: configuration.sampleCapacity)
        self.rotator = URLRotator(urls: configuration.urls)
        self.sink = sink
        let limiterEnabled = configuration.stableMode || !configuration.saturateMaximum
        self.rateLimiter = RateLimiter(enabled: limiterEnabled, maxBytesPerSecond: configuration.maxRateBps)
        self.onSnapshot = onSnapshot
        self.onFinished = onFinished
        self.onEvent = onEvent
        self.onError = onError
    }

    func start() {
        let configuration = self.configuration
        let rotator = self.rotator
        let metricsStore = self.metricsStore
        let sink = self.sink
        let rateLimiter = self.rateLimiter
        let onSnapshot = self.onSnapshot
        let onEvent = self.onEvent
        let onError = self.onError

        for workerID in 0..<max(1, configuration.concurrency) {
            let workerTask = Task.detached(priority: .utility) {
                await Self.workerLoop(
                    workerID: workerID,
                    configuration: configuration,
                    rotator: rotator,
                    metricsStore: metricsStore,
                    sink: sink,
                    rateLimiter: rateLimiter,
                    onEvent: onEvent,
                    onError: onError
                )
            }
            workerTasks.append(workerTask)
        }

        tickerTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }

                let snapshot = await metricsStore.tick(
                    now: Date(),
                    minRateBps: configuration.minRateBps,
                    movingAverageWindowSeconds: configuration.movingAverageWindowSeconds
                )
                onSnapshot(snapshot)
            }
        }

        if let duration = configuration.durationSeconds, duration > 0 {
            durationTask = Task.detached(priority: .utility) { [weak self] in
                let nanos = UInt64(duration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                await self?.stop()
            }
        }
    }

    func stop() async {
        guard markStopped() else { return }

        workerTasks.forEach { $0.cancel() }
        tickerTask?.cancel()
        durationTask?.cancel()

        for task in workerTasks {
            _ = await task.result
        }

        let finalSnapshot = await metricsStore.tick(
            now: Date(),
            minRateBps: configuration.minRateBps,
            movingAverageWindowSeconds: configuration.movingAverageWindowSeconds
        )
        onSnapshot(finalSnapshot)

        await sink.close()
        let allSamples = await metricsStore.allSamples()
        onFinished(allSamples)
    }

    private func markStopped() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        if hasStopped {
            return false
        }
        hasStopped = true
        return true
    }

    private static func workerLoop(
        workerID: Int,
        configuration: DownloadConfiguration,
        rotator: URLRotator,
        metricsStore: MetricsStore,
        sink: any ByteSink,
        rateLimiter: RateLimiter?,
        onEvent: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async {
        let sessionConfig = URLSessionConfiguration.ephemeral
        #if !os(Windows)
        sessionConfig.waitsForConnectivity = false
        #endif
        sessionConfig.timeoutIntervalForRequest = max(configuration.timeoutSeconds, 1)
        sessionConfig.timeoutIntervalForResource = max(configuration.timeoutSeconds * 4, 30)

        let session = URLSession(configuration: sessionConfig)
        defer {
            session.invalidateAndCancel()
        }

        var lastFailedURL: URL?

        while !Task.isCancelled {
            guard let url = await rotator.nextURL(avoiding: lastFailedURL) else {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            await metricsStore.setActiveURL(workerID: workerID, url: url)

            var retryIndex = 0
            var switched = false

            retryLoop: while !Task.isCancelled, retryIndex <= configuration.maxRetries {
                do {
                    try await stream(
                        workerID: workerID,
                        url: url,
                        configuration: configuration,
                        session: session,
                        metricsStore: metricsStore,
                        sink: sink,
                        rateLimiter: rateLimiter
                    )

                    await rotator.markSuccess(url)
                    lastFailedURL = nil
                    switched = true
                    break
                } catch is CancellationError {
                    return
                } catch DownloadWorkerError.lowPerformance {
                    await rotator.markLowPerformance(url)
                    lastFailedURL = url
                    let message = "Worker \(workerID + 1): switch by low performance on \(url.absoluteString)"
                    onEvent(message)
                    onError(message)
                    switched = true
                    break
                } catch {
                    let decision = ErrorPolicy.decision(
                        for: error,
                        retryAttempt: retryIndex,
                        maxRetries: configuration.maxRetries,
                        baseBackoffSeconds: configuration.backoffSeconds
                    )

                    if case .stopSession = decision {
                        onEvent("Worker \(workerID + 1): stopping session (\(url.absoluteString))")
                        return
                    }

                    await metricsStore.recordError()
                    let message = "Worker \(workerID + 1): \(ErrorPolicy.describe(error: error)) (\(url.absoluteString))"
                    onEvent(message)
                    onError(message)

                    switch decision {
                    case .retry(let wait):
                        retryIndex += 1
                        await metricsStore.recordRetry()
                        onEvent(
                            String(
                                format: "Worker %d: retry %d/%d in %.2fs (%@)",
                                workerID + 1,
                                retryIndex,
                                configuration.maxRetries,
                                wait,
                                url.absoluteString
                            )
                        )
                        let nanos = UInt64(max(wait, 0.05) * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: nanos)
                        continue retryLoop

                    case .rotateImmediately:
                        await rotator.markFailure(url)
                        lastFailedURL = url
                        onEvent("Worker \(workerID + 1): rotate endpoint after failure (\(url.absoluteString))")
                        switched = true
                        break retryLoop

                    case .stopSession:
                        // handled before recording errors to avoid false positives on graceful stops
                        return
                    }
                }
            }

            if !switched {
                lastFailedURL = url
            }
        }
    }

    private static func stream(
        workerID: Int,
        url: URL,
        configuration: DownloadConfiguration,
        session: URLSession,
        metricsStore: MetricsStore,
        sink: any ByteSink,
        rateLimiter: RateLimiter?
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = max(configuration.timeoutSeconds, 1)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        #if os(Windows)
        let processor = ChunkProcessor(
            workerID: workerID,
            url: url,
            configuration: configuration,
            metricsStore: metricsStore,
            sink: sink,
            rateLimiter: rateLimiter
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = max(configuration.timeoutSeconds, 1)
        sessionConfig.timeoutIntervalForResource = max(configuration.timeoutSeconds * 4, 30)
        let delegate = WindowsStreamingDelegate(processor: processor)
        let delegateSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        defer {
            delegateSession.invalidateAndCancel()
        }
        try await delegate.stream(request: request, session: delegateSession)
        return
        #else
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadWorkerError.invalidHTTPStatus(http.statusCode)
        }

        var iterator = bytes.makeAsyncIterator()
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)

        var bytesSinceRateCheck: Int64 = 0
        var lowRateElapsed: TimeInterval = 0
        var lastRateCheck = Date()
        var lastFlushAt = Date()

        func flushBuffer(now: Date = Date()) async throws {
            guard !buffer.isEmpty else { return }
            let data = Data(buffer)
            buffer.removeAll(keepingCapacity: true)

            try await sink.consume(data)

            let count = Int64(data.count)
            await metricsStore.recordBytes(workerID: workerID, bytes: count, url: url)
            if let rateLimiter {
                await rateLimiter.acquire(bytes: count)
            }

            lastFlushAt = now
        }

        while let byte = try await iterator.next() {
            if Task.isCancelled {
                throw CancellationError()
            }

            buffer.append(byte)
            bytesSinceRateCheck += 1

            if buffer.count >= 64 * 1024 {
                try await flushBuffer(now: Date())
            }

            let now = Date()
            if !buffer.isEmpty, now.timeIntervalSince(lastFlushAt) >= 0.25 {
                try await flushBuffer(now: now)
            }

            let elapsed = now.timeIntervalSince(lastRateCheck)
            if elapsed >= 1 {
                let currentRate = Double(bytesSinceRateCheck) / elapsed
                if configuration.minRateBps > 0 {
                    if currentRate < configuration.minRateBps {
                        lowRateElapsed += elapsed
                    } else {
                        lowRateElapsed = 0
                    }

                    if lowRateElapsed >= max(configuration.switchAfterSeconds, 1) {
                        throw DownloadWorkerError.lowPerformance(currentRateBps: currentRate)
                    }
                }

                bytesSinceRateCheck = 0
                lastRateCheck = now
            }
        }

        try await flushBuffer(now: Date())
        #endif
    }
}
