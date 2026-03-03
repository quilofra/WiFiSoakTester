import Foundation

enum NetworkErrorClass: Sendable {
    case retryTransient
    case rotateImmediately
    case stopSession
}

enum RetryDecision: Sendable, Equatable {
    case retry(afterSeconds: TimeInterval)
    case rotateImmediately
    case stopSession
}

enum ErrorPolicy {
    private static let sslCodes: Set<URLError.Code> = [
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid,
        .clientCertificateRejected,
        .clientCertificateRequired
    ]

    private static let transientURLCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .resourceUnavailable,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed
    ]

    static func classify(error: Error) -> NetworkErrorClass {
        if let worker = error as? DownloadWorkerError {
            switch worker {
            case .noEndpointAvailable:
                return .stopSession
            case .lowPerformance:
                return .rotateImmediately
            case .invalidHTTPStatus(let status):
                if status == 408 || status == 429 || (500...599).contains(status) {
                    return .retryTransient
                }
                if (400...499).contains(status) {
                    return .rotateImmediately
                }
                return .retryTransient
            }
        }

        guard let urlError = error as? URLError else {
            return .retryTransient
        }

        if urlError.code == .badURL || urlError.code == .unsupportedURL {
            return .rotateImmediately
        }

        if urlError.code == .cancelled {
            return .stopSession
        }

        if urlError.code == .appTransportSecurityRequiresSecureConnection {
            return .rotateImmediately
        }

        if sslCodes.contains(urlError.code) {
            return .rotateImmediately
        }

        if transientURLCodes.contains(urlError.code) {
            return .retryTransient
        }

        return .retryTransient
    }

    static func decision(for error: Error, retryAttempt: Int, maxRetries: Int, baseBackoffSeconds: Double) -> RetryDecision {
        switch classify(error: error) {
        case .rotateImmediately:
            return .rotateImmediately

        case .stopSession:
            return .stopSession

        case .retryTransient:
            guard retryAttempt < maxRetries else {
                return .rotateImmediately
            }
            let exponent = max(retryAttempt, 0)
            let base = max(baseBackoffSeconds, 0.1)
            let expBackoff = base * pow(2, Double(exponent))
            let jitter = Double.random(in: 0.85...1.15)
            return .retry(afterSeconds: expBackoff * jitter)
        }
    }

    static func describe(error: Error) -> String {
        if let workerError = error as? DownloadWorkerError {
            switch workerError {
            case .invalidHTTPStatus(let code):
                return "HTTP status \(code)"
            case .lowPerformance(let rate):
                let mbps = (rate * 8) / 1_000_000
                return String(format: "Low performance %.2f Mbps", mbps)
            case .noEndpointAvailable:
                return "No endpoint available"
            }
        }

        if let urlError = error as? URLError {
            if urlError.code == .appTransportSecurityRequiresSecureConnection {
                return "ATS blocked insecure HTTP (\(urlError.code.rawValue))."
            }

            if sslCodes.contains(urlError.code) {
                return "SSL/TLS handshake failed (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
            }

            return "URL error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
        }

        return error.localizedDescription
    }
}
