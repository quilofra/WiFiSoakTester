import Foundation

protocol ByteSink: Sendable {
    func consume(_ data: Data) async throws
    func close() async
}

actor DiscardSink: ByteSink {
    func consume(_ data: Data) async throws {
        _ = data.count
    }

    func close() async {
    }
}
