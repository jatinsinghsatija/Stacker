/// Human-readable meanings for HTTP status codes.
///
/// The dashboard shows the *meaning* of a code next to the code itself so a
/// reviewer does not have to remember what, say, 422 or 428 stands for.
library;

/// Broad outcome class of an HTTP status code.
enum HttpStatusClass {
  informational,
  success,
  redirection,
  clientError,
  serverError,
  unknown,
}

/// A status code paired with its reason phrase and an explanation.
class HttpStatusInfo {
  const HttpStatusInfo({
    required this.code,
    required this.reasonPhrase,
    required this.meaning,
  });

  /// The numeric status code, or `-1` when the request never got a response.
  final int code;

  /// The canonical reason phrase, e.g. `Not Found`.
  final String reasonPhrase;

  /// A one-line plain-English explanation of what the code implies.
  final String meaning;

  HttpStatusClass get statusClass => HttpStatus.classOf(code);

  @override
  String toString() => '$code $reasonPhrase';
}

/// Lookup table and helpers for HTTP status codes.
///
/// Covers every code registered with IANA plus the widely deployed
/// unofficial codes (Cloudflare 5xx, nginx 4xx) that show up in real traffic.
abstract final class HttpStatus {
  /// Sentinel used for a request that failed before any response arrived
  /// (DNS failure, connection refused, TLS error, timeout, cancellation).
  static const int noResponse = -1;

  static const Map<int, List<String>> _table = <int, List<String>>{
    // ---- 1xx informational -------------------------------------------------
    100: ['Continue', 'The server received the headers and the client should proceed to send the body.'],
    101: ['Switching Protocols', 'The server is switching protocols as requested by the Upgrade header.'],
    102: ['Processing', 'The server accepted the request but has not completed it yet (WebDAV).'],
    103: ['Early Hints', 'Preliminary response headers sent so the client can start preloading resources.'],

    // ---- 2xx success -------------------------------------------------------
    200: ['OK', 'The request succeeded and the response carries the requested payload.'],
    201: ['Created', 'The request succeeded and a new resource was created; check the Location header.'],
    202: ['Accepted', 'The request was accepted for processing but has not completed yet.'],
    203: ['Non-Authoritative Information', 'The response is a transformed copy from a proxy, not the origin.'],
    204: ['No Content', 'The request succeeded and intentionally returns no response body.'],
    205: ['Reset Content', 'The request succeeded; the client should reset the document view.'],
    206: ['Partial Content', 'Only the byte range requested via the Range header is being returned.'],
    207: ['Multi-Status', 'The body holds multiple independent status codes, one per sub-request (WebDAV).'],
    208: ['Already Reported', 'Members of a WebDAV binding were already enumerated in a previous reply.'],
    226: ['IM Used', 'The response is the result of applying instance-manipulations to the resource.'],

    // ---- 3xx redirection ---------------------------------------------------
    300: ['Multiple Choices', 'Several representations exist; the client must pick one.'],
    301: ['Moved Permanently', 'The resource has a new permanent URL; update the stored link.'],
    302: ['Found', 'The resource is temporarily at a different URL; keep using the original one.'],
    303: ['See Other', 'Fetch the result of this request with a GET to the URL in Location.'],
    304: ['Not Modified', 'The cached copy is still valid, so no body was sent.'],
    305: ['Use Proxy', 'The resource must be accessed through the proxy given in Location (deprecated).'],
    307: ['Temporary Redirect', 'Same as 302 but the HTTP method must not be changed on the retry.'],
    308: ['Permanent Redirect', 'Same as 301 but the HTTP method must not be changed on the retry.'],

    // ---- 4xx client error --------------------------------------------------
    400: ['Bad Request', 'The server could not parse the request; check the body, params, and encoding.'],
    401: ['Unauthorized', 'Authentication is missing or invalid; the token may be absent or expired.'],
    402: ['Payment Required', 'Payment or an active subscription is required to access this resource.'],
    403: ['Forbidden', 'The caller is authenticated but not allowed to perform this action.'],
    404: ['Not Found', 'No resource exists at this URL; check the path and any interpolated IDs.'],
    405: ['Method Not Allowed', 'This URL exists but does not accept the HTTP method that was used.'],
    406: ['Not Acceptable', 'The server cannot produce a response matching the Accept header.'],
    407: ['Proxy Authentication Required', 'The client must authenticate with the proxy first.'],
    408: ['Request Timeout', 'The server closed an idle connection while waiting for the request.'],
    409: ['Conflict', 'The request conflicts with the current state, e.g. a duplicate or stale write.'],
    410: ['Gone', 'The resource was deliberately and permanently removed.'],
    411: ['Length Required', 'The server requires a Content-Length header on this request.'],
    412: ['Precondition Failed', 'A conditional header such as If-Match did not hold.'],
    413: ['Payload Too Large', 'The request body exceeds the size the server will accept.'],
    414: ['URI Too Long', 'The request URL is longer than the server will process.'],
    415: ['Unsupported Media Type', 'The Content-Type of the body is not supported by this endpoint.'],
    416: ['Range Not Satisfiable', 'The requested byte range lies outside the size of the resource.'],
    417: ['Expectation Failed', 'The expectation in the Expect header cannot be met.'],
    418: ["I'm a Teapot", 'An April Fools joke code from RFC 2324; sometimes used to reject bots.'],
    421: ['Misdirected Request', 'This server cannot produce a response for the requested authority.'],
    422: ['Unprocessable Content', 'The syntax is valid but validation failed; inspect the field errors.'],
    423: ['Locked', 'The resource is locked and cannot be modified (WebDAV).'],
    424: ['Failed Dependency', 'The request failed because a dependent request failed (WebDAV).'],
    425: ['Too Early', 'The server refuses to risk replaying an early-data request.'],
    426: ['Upgrade Required', 'The client must switch to a different protocol, such as TLS.'],
    428: ['Precondition Required', 'The server requires a conditional request to avoid a lost update.'],
    429: ['Too Many Requests', 'The client is rate limited; back off and honour the Retry-After header.'],
    431: ['Request Header Fields Too Large', 'The headers are collectively or individually too large.'],
    451: ['Unavailable For Legal Reasons', 'Access is denied for legal or censorship reasons.'],
    // Widely deployed unofficial 4xx.
    444: ['No Response (nginx)', 'nginx closed the connection without any response, usually to drop an abusive client.'],
    494: ['Request Header Too Large (nginx)', 'nginx rejected the request because its headers were oversized.'],
    495: ['SSL Certificate Error (nginx)', 'The client TLS certificate could not be verified.'],
    496: ['SSL Certificate Required (nginx)', 'The client did not present the required TLS certificate.'],
    497: ['HTTP Request Sent to HTTPS Port (nginx)', 'A plaintext request reached a TLS-only port.'],
    499: ['Client Closed Request (nginx)', 'The client disconnected before the server could reply, often a cancelled call.'],

    // ---- 5xx server error --------------------------------------------------
    500: ['Internal Server Error', 'An unhandled error occurred on the server; check the server logs.'],
    501: ['Not Implemented', 'The server does not support the functionality needed for this request.'],
    502: ['Bad Gateway', 'An upstream server returned an invalid response to the gateway or proxy.'],
    503: ['Service Unavailable', 'The server is overloaded or down for maintenance; retry later.'],
    504: ['Gateway Timeout', 'An upstream server did not respond in time.'],
    505: ['HTTP Version Not Supported', 'The HTTP version used in the request is not supported.'],
    506: ['Variant Also Negotiates', 'The server has an internal content-negotiation misconfiguration.'],
    507: ['Insufficient Storage', 'The server cannot store the representation needed to complete the request.'],
    508: ['Loop Detected', 'An infinite loop was detected while processing the request (WebDAV).'],
    510: ['Not Extended', 'Further extensions to the request are required.'],
    511: ['Network Authentication Required', 'The client must authenticate with the network, e.g. a captive portal.'],
    // Widely deployed unofficial 5xx (Cloudflare).
    520: ['Web Server Returned Unknown Error', 'Cloudflare received an unexpected empty or invalid response from the origin.'],
    521: ['Web Server Is Down', 'Cloudflare could not reach the origin server; connections were refused.'],
    522: ['Connection Timed Out', 'Cloudflare could not complete a TCP handshake with the origin.'],
    523: ['Origin Is Unreachable', 'Cloudflare could not route to the origin, often a DNS or network issue.'],
    524: ['A Timeout Occurred', 'Cloudflare established a connection but the origin did not reply in time.'],
    525: ['SSL Handshake Failed', 'The TLS handshake between Cloudflare and the origin failed.'],
    526: ['Invalid SSL Certificate', 'The origin presented an invalid or expired TLS certificate.'],
    527: ['Railgun Error', 'A connection error occurred between Cloudflare and the Railgun listener.'],
    530: ['Site Frozen', 'The origin returned an additional 1xxx Cloudflare error; see the body.'],
  };

  /// Returns the meaning of [code], or `null` when the code is unknown.
  ///
  /// Passing [noResponse] yields the "no response" explanation used for
  /// transport-level failures.
  static HttpStatusInfo? lookup(int code) {
    if (code == noResponse) {
      return const HttpStatusInfo(
        code: noResponse,
        reasonPhrase: 'No Response',
        meaning:
            'The request never received an HTTP response. Typical causes are DNS '
            'failure, a refused connection, a TLS error, a timeout, or the call '
            'being cancelled.',
      );
    }
    final entry = _table[code];
    if (entry == null) return null;
    return HttpStatusInfo(
      code: code,
      reasonPhrase: entry[0],
      meaning: entry[1],
    );
  }

  /// Like [lookup] but always returns a value, synthesising a description
  /// from the status class for codes outside the table.
  static HttpStatusInfo describe(int code) {
    final known = lookup(code);
    if (known != null) return known;
    return HttpStatusInfo(
      code: code,
      reasonPhrase: _fallbackPhrase(code),
      meaning: _fallbackMeaning(code),
    );
  }

  /// The reason phrase for [code], or a class-derived fallback.
  static String reasonPhrase(int code) => describe(code).reasonPhrase;

  /// The plain-English meaning of [code].
  static String meaningOf(int code) => describe(code).meaning;

  /// The class [code] belongs to.
  static HttpStatusClass classOf(int code) {
    if (code >= 100 && code < 200) return HttpStatusClass.informational;
    if (code >= 200 && code < 300) return HttpStatusClass.success;
    if (code >= 300 && code < 400) return HttpStatusClass.redirection;
    if (code >= 400 && code < 500) return HttpStatusClass.clientError;
    if (code >= 500 && code < 600) return HttpStatusClass.serverError;
    return HttpStatusClass.unknown;
  }

  /// Whether [code] represents a 2xx response.
  static bool isSuccess(int code) => classOf(code) == HttpStatusClass.success;

  static String _fallbackPhrase(int code) => switch (classOf(code)) {
        HttpStatusClass.informational => 'Informational',
        HttpStatusClass.success => 'Success',
        HttpStatusClass.redirection => 'Redirection',
        HttpStatusClass.clientError => 'Client Error',
        HttpStatusClass.serverError => 'Server Error',
        HttpStatusClass.unknown => 'Unknown Status',
      };

  static String _fallbackMeaning(int code) => switch (classOf(code)) {
        HttpStatusClass.informational =>
          'A non-standard informational code. The server is still processing the request.',
        HttpStatusClass.success =>
          'A non-standard success code. The request was handled successfully.',
        HttpStatusClass.redirection =>
          'A non-standard redirection code. The resource lives at a different URL.',
        HttpStatusClass.clientError =>
          'A non-standard client error code. Something about the request was rejected.',
        HttpStatusClass.serverError =>
          'A non-standard server error code. The failure happened on the server side.',
        HttpStatusClass.unknown =>
          'This value is outside the 100-599 range defined for HTTP status codes.',
      };
}
