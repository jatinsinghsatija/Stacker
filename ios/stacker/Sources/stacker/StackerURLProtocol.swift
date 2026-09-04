import Foundation

/// Captures `URLSession` traffic on iOS by sitting in the URL loading system.
///
/// ## How to install it — two paths
///
/// **1. Your own session (recommended, fully reliable).** Add the protocol to
/// the session's configuration:
///
/// ```swift
/// let config = URLSessionConfiguration.default
/// StackerURLProtocol.install(in: config)
/// let session = URLSession(configuration: config)
/// ```
///
/// **2. `URLSession.shared` and third-party SDKs (broad, best-effort).**
/// Register globally:
///
/// ```swift
/// StackerURLProtocol.registerGlobally()
/// ```
///
/// `URLProtocol.registerClass` reaches `URLSession.shared` and any session
/// built from a default configuration, which covers Alamofire and most SDKs.
/// It does *not* reach a session whose `protocolClasses` were replaced
/// wholesale, nor a background session — the OS loads those outside the app's
/// URL loading system. For those, use path 1, or report the call explicitly
/// with `StackerBridge.shared.sendApi(...)`.
///
/// ## Why a URLProtocol rather than swizzling
///
/// Swizzling `URLSession`'s internals is version-fragile and breaks when Apple
/// reshapes the class internals. `URLProtocol` is the documented interception
/// point, so this survives OS updates.
@objc public final class StackerURLProtocol: URLProtocol {

    /// Marker preventing infinite recursion: the replayed request must not be
    /// intercepted by this protocol a second time.
    private static let handledKey = "com.stacker.handled"

    /// Bodies longer than this are truncated before reporting.
    private static let maxBodyBytes = 256 * 1024

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var responseData = Data()
    private var recordId = ""
    private var requestTime = Date()

    /// Adds the protocol to [configuration]'s loading chain.
    ///
    /// Inserted first so it sees the request before any other custom protocol.
    @objc public static func install(in configuration: URLSessionConfiguration) {
        var classes = configuration.protocolClasses ?? []
        if !classes.contains(where: { $0 == StackerURLProtocol.self }) {
            classes.insert(StackerURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = classes
    }

    /// Registers the protocol globally, covering `URLSession.shared`.
    @objc public static func registerGlobally() {
        URLProtocol.registerClass(StackerURLProtocol.self)
    }

    /// Unregisters the global hook.
    @objc public static func unregisterGlobally() {
        URLProtocol.unregisterClass(StackerURLProtocol.self)
    }

    // MARK: - URLProtocol

    public override class func canInit(with request: URLRequest) -> Bool {
        // Off in release, and never re-handle a request we already replayed.
        guard StackerBridge.shared.isEnabled else { return false }
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }
        // Only HTTP(S); file and data URLs are not interesting here and
        // interfering with them risks breaking image loading.
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        recordId = "ios-\(UUID().uuidString)"
        requestTime = Date()

        guard let mutableRequest = (request as NSURLRequest).mutableCopy()
                as? NSMutableURLRequest
        else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "com.stacker",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not copy the request"]
                )
            )
            return
        }

        // Mark the replay so canInit refuses it and we do not loop.
        URLProtocol.setProperty(
            true,
            forKey: Self.handledKey,
            in: mutableRequest
        )

        reportPending()

        // A separate ephemeral session performs the real load. Its
        // configuration deliberately does NOT include this protocol.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        self.session = session

        let task = session.dataTask(with: mutableRequest as URLRequest)
        dataTask = task
        task.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
        session?.invalidateAndCancel()
        session = nil
        dataTask = nil
    }

    // MARK: - Reporting

    private func reportPending() {
        var payload: [String: Any] = [
            "id": recordId,
            "origin": "ios",
            "method": request.httpMethod ?? "GET",
            "url": request.url?.absoluteString ?? "",
            "requestTime": Int(requestTime.timeIntervalSince1970 * 1000),
            "requestHeaders": StackerRedaction.headers(request.allHTTPHeaderFields),
            "queryParameters": StackerRedaction.query(from: request.url),
        ]
        if let body = requestBodyString() {
            payload["requestBody"] = body
            payload["requestSizeBytes"] = request.httpBody?.count ?? 0
        }
        if let contentType = request.value(forHTTPHeaderField: "Content-Type") {
            payload["requestContentType"] = contentType
        }
        StackerBridge.shared.sendApi(payload)
    }

    private func reportCompletion(response: HTTPURLResponse?, error: Error?) {
        var payload: [String: Any] = [
            "id": recordId,
            "origin": "ios",
            "method": request.httpMethod ?? "GET",
            "url": request.url?.absoluteString ?? "",
            "requestTime": Int(requestTime.timeIntervalSince1970 * 1000),
            "responseTime": Int(Date().timeIntervalSince1970 * 1000),
            "requestHeaders": StackerRedaction.headers(request.allHTTPHeaderFields),
            "queryParameters": StackerRedaction.query(from: request.url),
        ]
        if let body = requestBodyString() {
            payload["requestBody"] = body
        }

        if let response {
            payload["statusCode"] = response.statusCode
            payload["responseHeaders"] = StackerRedaction.headers(
                response.allHeaderFields as? [String: String]
            )
            payload["responseSizeBytes"] = responseData.count
            if let contentType = response.value(forHTTPHeaderField: "Content-Type") {
                payload["responseContentType"] = contentType
            }
            payload["responseBody"] = Self.bodyString(
                from: responseData,
                contentType: response.value(forHTTPHeaderField: "Content-Type")
            )
        }

        if let error {
            let nsError = error as NSError
            payload["errorMessage"] = nsError.localizedDescription
            payload["errorType"] = "\(nsError.domain)(\(nsError.code))"
        }

        StackerBridge.shared.sendApi(payload)
    }

    private func requestBodyString() -> String? {
        // `httpBodyStream` is deliberately not read: it is single-pass and
        // consuming it here would corrupt the outgoing request.
        if request.httpBody == nil, request.httpBodyStream != nil {
            return "<streamed request body not captured>"
        }
        guard let body = request.httpBody else { return nil }
        return Self.bodyString(
            from: body,
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        )
    }

    /// Renders [data] as text, or a placeholder when it is binary.
    private static func bodyString(from data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "" }

        let lowered = contentType?.lowercased() ?? ""
        let looksBinary = lowered.hasPrefix("image/")
            || lowered.hasPrefix("audio/")
            || lowered.hasPrefix("video/")
            || lowered.contains("octet-stream")
            || lowered.contains("pdf")
            || lowered.contains("zip")

        if looksBinary {
            return "<binary \(data.count) bytes>"
        }

        let slice = data.count > maxBodyBytes
            ? data.prefix(maxBodyBytes)
            : data
        guard let text = String(data: slice, encoding: .utf8) else {
            return "<binary \(data.count) bytes>"
        }
        return data.count > maxBodyBytes ? "\(text)\n\n… truncated" : text
    }
}

// MARK: - URLSessionDataDelegate

extension StackerURLProtocol: URLSessionDataDelegate {

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        completionHandler(.allow)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        // Buffer for reporting, and forward so the caller is unaffected.
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        reportCompletion(
            response: task.response as? HTTPURLResponse,
            error: error
        )

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }

        session.finishTasksAndInvalidate()
        self.session = nil
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Surface the redirect to the client so its policy applies, then let
        // the redirect proceed.
        client?.urlProtocol(
            self,
            wasRedirectedTo: request,
            redirectResponse: response
        )
        completionHandler(request)
    }
}

/// Header and query redaction shared by the iOS capture points.
enum StackerRedaction {

    /// Header names whose values are hidden.
    static let redactedHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "x-csrf-token",
        "x-session-token",
        "api-key",
        "apikey",
    ]

    static let placeholder = "••• redacted •••"

    /// Redacts sensitive values in [headers].
    static func headers(_ headers: [String: String]?) -> [String: String] {
        guard let headers else { return [:] }
        var result: [String: String] = [:]
        for (name, value) in headers {
            result[name] = redactedHeaders.contains(name.lowercased())
                ? placeholder
                : value
        }
        return result
    }

    /// Extracts and redacts the query parameters of [url].
    static func query(from url: URL?) -> [String: String] {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else {
            return [:]
        }
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = redactedHeaders.contains(item.name.lowercased())
                ? placeholder
                : (item.value ?? "")
        }
        return result
    }
}
