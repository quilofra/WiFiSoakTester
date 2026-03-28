import Foundation

actor DiskRingBuffer: ByteSink {
    enum DiskRingBufferError: Error {
        case invalidConfiguration
    }

    private let directoryURL: URL
    private let cacheSizeBytes: Int64
    private let segmentSizeBytes: Int64
    private let segmentCount: Int
    private let segmentURLs: [URL]
    private var handles: [FileHandle]
    private var currentSegment: Int = 0
    private var currentOffset: Int64 = 0

    init(directoryURL: URL, cacheSizeBytes: Int64, segmentSizeBytes: Int64) throws {
        guard cacheSizeBytes > 0, segmentSizeBytes > 0 else {
            throw DiskRingBufferError.invalidConfiguration
        }

        self.directoryURL = directoryURL
        self.cacheSizeBytes = cacheSizeBytes
        self.segmentSizeBytes = segmentSizeBytes
        self.segmentCount = max(1, Int(ceil(Double(cacheSizeBytes) / Double(segmentSizeBytes))))

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var createdURLs: [URL] = []
        createdURLs.reserveCapacity(segmentCount)

        var openedHandles: [FileHandle] = []
        openedHandles.reserveCapacity(segmentCount)

        for index in 0..<segmentCount {
            let url = directoryURL.appendingPathComponent(String(format: "segment_%05d.bin", index))
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forUpdating: url)
            try handle.truncate(atOffset: 0)
            createdURLs.append(url)
            openedHandles.append(handle)
        }

        self.segmentURLs = createdURLs
        self.handles = openedHandles
    }

    func consume(_ data: Data) async throws {
        guard !data.isEmpty else { return }

        var position = data.startIndex
        while position < data.endIndex {
            if currentOffset >= segmentSizeBytes {
                try advanceSegment()
            }

            let remainingInSegment = Int(segmentSizeBytes - currentOffset)
            let writeCount = min(remainingInSegment, data.distance(from: position, to: data.endIndex))

            let end = data.index(position, offsetBy: writeCount)
            let slice = data[position..<end]
            let handle = handles[currentSegment]

            try handle.seek(toOffset: UInt64(currentOffset))
            try handle.write(contentsOf: slice)

            currentOffset += Int64(writeCount)
            position = end
        }
    }

    func close() async {
        for handle in handles {
            try? handle.close()
        }
        handles.removeAll(keepingCapacity: false)
    }

    func segmentFiles() -> [URL] {
        segmentURLs
    }

    func currentUsageApproxBytes() -> Int64 {
        Int64(segmentCount) * segmentSizeBytes
    }

    private func advanceSegment() throws {
        currentSegment = (currentSegment + 1) % segmentCount
        currentOffset = 0

        let handle = handles[currentSegment]
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
    }
}
