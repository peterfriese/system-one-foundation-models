import Foundation

// See tech-notes/0006-http-resilience-and-confidence-routing.md

/// Controls how network requests react to retryable HTTP status codes.
public struct RetryPolicy: Sendable, Hashable {
    /// Total attempts *including* the initial request. 3 means at most two retries.
    public var maxAttempts: Int

    /// Initial delay before the first retry attempt.
    public var initialDelay: Duration

    /// Multiplier applied to the backoff delay for each subsequent attempt.
    public var multiplier: Double

    /// Random jitter factor in `1 - jitter ... 1 + jitter`.
    public var jitter: Double

    /// The single source of truth for which HTTP status codes get retried.
    ///
    /// By default, only 429 (Too Many Requests) and 529 (Site Overloaded) are retried.
    /// 401 (Unauthorized) and 422 (Unprocessable Content) cannot succeed on retry and are excluded.
    public var retryableStatuses: Set<Int>

    /// Upper bound applied to any server-supplied `Retry-After` delay.
    public var maxRetryAfter: Duration

    public init(
        maxAttempts: Int = 3,
        initialDelay: Duration = .milliseconds(500),
        multiplier: Double = 2.0,
        jitter: Double = 0.2,
        retryableStatuses: Set<Int> = [429, 529],
        maxRetryAfter: Duration = .seconds(60)
    ) {
        // Normalize rather than trap: assemble sane bounds from configuration.
        self.maxAttempts = max(maxAttempts, 1)
        self.initialDelay = initialDelay < .zero ? .zero : initialDelay
        self.multiplier = max(multiplier, 1.0)
        self.jitter = min(max(jitter, 0.0), 1.0)
        self.retryableStatuses = retryableStatuses
        self.maxRetryAfter = maxRetryAfter < .zero ? .zero : maxRetryAfter
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    /// Calculates exponential backoff with jitter for the attempt that just failed, where `attempt` is 1-based.
    public func backoff(afterAttempt attempt: Int, randomness: Double = Double.random(in: 0...1)) -> Duration {
        let exponent = max(attempt - 1, 0)
        let rawGrowth = pow(multiplier, Double(exponent))
        let growth = rawGrowth.isFinite ? rawGrowth : Double.greatestFiniteMagnitude
        let scaled = rawGrowth.isFinite ? (initialDelay * growth) : .saturated
        let factor = 1.0 + jitter * (randomness * 2.0 - 1.0)
        let effectiveFactor = factor.isFinite ? max(factor, 0.0) : 1.0
        let result = scaled * effectiveFactor
        return min(result, maxRetryAfter)
    }

    /// Parses an RFC 9110 `Retry-After` header value (either integer seconds or HTTP-date), bounded by `maxRetryAfter`.
    ///
    /// Jitter is intentionally not applied to server-supplied dates/delays because the server explicitly named the time.
    public func retryAfter(headerValue raw: String?, now: Date = Date()) -> Duration? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if let seconds = Int(raw) {
            guard seconds >= 0 else { return nil }
            return min(.seconds(seconds), maxRetryAfter)
        }

        guard let date = Self.httpDate(raw) else { return nil }
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return .zero }
        return min(.seconds(interval), maxRetryAfter)
    }

    /// Extracts and parses `Retry-After` from an `HTTPURLResponse`.
    public func retryAfter(from response: HTTPURLResponse, now: Date = Date()) -> Duration? {
        retryAfter(headerValue: response.value(forHTTPHeaderField: "Retry-After"), now: now)
    }

    /// RFC 9110 permits three date formats; modern servers predominantly send IMF-fixdate.
    private static func httpDate(_ raw: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Duration Saturation Arithmetic

extension Duration {
    /// Scales a duration, rounded to the nearest nanosecond with saturation protection against integer overflow.
    public static func * (lhs: Duration, rhs: Double) -> Duration {
        guard !rhs.isNaN, rhs > 0 else { return .zero }
        let seconds = Double(lhs.components.seconds) + Double(lhs.components.attoseconds) * 1e-18
        if rhs.isInfinite {
            return seconds >= 0 ? .saturated : .negativeSaturated
        }
        let nanoseconds = (seconds * rhs * 1_000_000_000).rounded()
        guard nanoseconds.isFinite else {
            return seconds >= 0 ? .saturated : .negativeSaturated
        }
        if nanoseconds >= Double(Int64.max) {
            return .saturated
        }
        if nanoseconds <= Double(Int64.min) {
            return .negativeSaturated
        }
        return .nanoseconds(Int64(nanoseconds))
    }

    /// The largest delay represented in whole nanoseconds without overflow.
    public static var saturated: Duration {
        .nanoseconds(Int64.max)
    }

    /// The smallest (most negative) duration represented in whole nanoseconds without underflow.
    public static var negativeSaturated: Duration {
        .nanoseconds(Int64.min)
    }
}
