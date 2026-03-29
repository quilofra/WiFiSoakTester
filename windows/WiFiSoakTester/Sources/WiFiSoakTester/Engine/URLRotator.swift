import Foundation

actor URLRotator {
    private var urls: [URL]
    private var cursor: Int = 0
    private var lastSelected: URL?
    private var cooldownUntil: [URL: Date] = [:]
    private var failureStreak: [URL: Int] = [:]
    private var lowPerformanceStreak: [URL: Int] = [:]
    private let failureCooldown: TimeInterval
    private let lowPerformanceCooldown: TimeInterval

    init(
        urls: [URL],
        failureCooldown: TimeInterval = 20,
        lowPerformanceCooldown: TimeInterval = 10
    ) {
        self.urls = urls
        self.failureCooldown = failureCooldown
        self.lowPerformanceCooldown = lowPerformanceCooldown
    }

    func update(urls: [URL]) {
        self.urls = urls
        if cursor >= urls.count {
            cursor = 0
        }
        let validSet = Set(urls)
        cooldownUntil = cooldownUntil.filter { validSet.contains($0.key) }
        failureStreak = failureStreak.filter { validSet.contains($0.key) }
        lowPerformanceStreak = lowPerformanceStreak.filter { validSet.contains($0.key) }
        if let selected = lastSelected, !validSet.contains(selected) {
            lastSelected = nil
        }
    }

    func nextURL(avoiding failedURL: URL? = nil, now: Date = Date()) -> URL? {
        guard !urls.isEmpty else { return nil }

        let preferred = selectCandidate(avoiding: failedURL, now: now, avoidLastSelected: true)
            ?? selectCandidate(avoiding: failedURL, now: now, avoidLastSelected: false)
            ?? selectCandidateIgnoringCooldown(avoiding: failedURL)

        guard let choice = preferred else { return urls.first }
        lastSelected = choice
        return choice
    }

    func markFailure(_ url: URL, now: Date = Date()) {
        let streak = min((failureStreak[url] ?? 0) + 1, 16)
        failureStreak[url] = streak
        lowPerformanceStreak[url] = nil

        let multiplier = min(pow(2, Double(max(streak - 1, 0))), 8)
        cooldownUntil[url] = now.addingTimeInterval(failureCooldown * multiplier)
    }

    func markLowPerformance(_ url: URL, now: Date = Date()) {
        let streak = min((lowPerformanceStreak[url] ?? 0) + 1, 16)
        lowPerformanceStreak[url] = streak

        let multiplier = min(pow(1.5, Double(max(streak - 1, 0))), 4)
        cooldownUntil[url] = now.addingTimeInterval(lowPerformanceCooldown * multiplier)
    }

    func markSuccess(_ url: URL) {
        cooldownUntil[url] = nil
        failureStreak[url] = nil
        lowPerformanceStreak[url] = nil
    }

    private func selectCandidate(avoiding failedURL: URL?, now: Date, avoidLastSelected: Bool) -> URL? {
        guard !urls.isEmpty else { return nil }

        for offset in 0..<urls.count {
            let index = (cursor + offset) % urls.count
            let url = urls[index]

            if shouldSkip(url: url, failedURL: failedURL, now: now, avoidLastSelected: avoidLastSelected) {
                continue
            }

            cursor = (index + 1) % urls.count
            return url
        }

        return nil
    }

    private func selectCandidateIgnoringCooldown(avoiding failedURL: URL?) -> URL? {
        guard !urls.isEmpty else { return nil }

        for offset in 0..<urls.count {
            let index = (cursor + offset) % urls.count
            let url = urls[index]
            if urls.count > 1, let failedURL, url == failedURL {
                continue
            }
            cursor = (index + 1) % urls.count
            return url
        }

        return urls.first
    }

    private func shouldSkip(url: URL, failedURL: URL?, now: Date, avoidLastSelected: Bool) -> Bool {
        if urls.count > 1, let failedURL, url == failedURL {
            return true
        }

        if avoidLastSelected, urls.count > 1, let lastSelected, url == lastSelected {
            return true
        }

        if let until = cooldownUntil[url], until > now {
            return true
        }

        return false
    }
}
