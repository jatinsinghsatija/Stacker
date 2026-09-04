package com.stacker.stacker

import java.io.EOFException
import java.io.IOException
import java.nio.charset.Charset
import java.util.UUID
import okhttp3.Interceptor
import okhttp3.Response
import okio.Buffer
import okio.GzipSource

/**
 * OkHttp interceptor that reports every call to the Stacker dashboard.
 *
 * This is the entry point for a **native Android** app — including one whose
 * networking goes through Retrofit, since Retrofit delegates to OkHttp:
 *
 * ```kotlin
 * val client = OkHttpClient.Builder()
 *     .addInterceptor(StackerOkHttpInterceptor())
 *     .build()
 * ```
 *
 * Add it **last** so it observes the final request after any auth or retry
 * interceptor has run.
 *
 * ### Behaviour guarantees
 *
 * * When capture is off (any release build) [intercept] forwards the call and
 *   returns, doing no work beyond a volatile read.
 * * The response body is read through a peek, so the caller still receives a
 *   fully readable, unconsumed body.
 * * Capture failures are swallowed: a bug in the inspector must never turn a
 *   working request into a failed one.
 *
 * @param maxBodyBytes bodies longer than this are truncated before reporting.
 * @param redactedHeaders header names whose values are replaced. Case-insensitive.
 */
class StackerOkHttpInterceptor @JvmOverloads constructor(
    private val maxBodyBytes: Long = 256L * 1024L,
    private val redactedHeaders: Set<String> = DEFAULT_REDACTED_HEADERS,
) : Interceptor {

    companion object {
        /** Header names redacted unless the caller overrides them. */
        @JvmField
        val DEFAULT_REDACTED_HEADERS: Set<String> = setOf(
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
        )

        private const val REDACTED = "••• redacted •••"
        private val UTF8: Charset = Charset.forName("UTF-8")
    }

    @Throws(IOException::class)
    override fun intercept(chain: Interceptor.Chain): Response {
        if (!StackerBridge.isEnabled) {
            return chain.proceed(chain.request())
        }

        val request = chain.request()
        val id = "android-${UUID.randomUUID()}"
        val requestTime = System.currentTimeMillis()

        // Report the in-flight request so it shows as pending immediately.
        runCatching {
            StackerBridge.sendApi(
                buildMap {
                    put("id", id)
                    put("origin", "android")
                    put("method", request.method)
                    put("url", request.url.toString())
                    put("requestTime", requestTime)
                    put("requestHeaders", headersOf(request.headers))
                    put("queryParameters", queryOf(request.url))
                    put("requestBody", requestBodyOf(request))
                    put("requestContentType", request.body?.contentType()?.toString())
                    put("requestSizeBytes", request.body?.contentLength()?.toInt() ?: 0)
                },
            )
        }

        val response: Response
        try {
            response = chain.proceed(request)
        } catch (error: IOException) {
            runCatching {
                StackerBridge.sendApi(
                    buildMap {
                        put("id", id)
                        put("origin", "android")
                        put("method", request.method)
                        put("url", request.url.toString())
                        put("requestTime", requestTime)
                        put("responseTime", System.currentTimeMillis())
                        put("requestHeaders", headersOf(request.headers))
                        put("queryParameters", queryOf(request.url))
                        put("errorMessage", error.message ?: error.toString())
                        put("errorType", error.javaClass.simpleName)
                    },
                )
            }
            throw error
        }

        runCatching {
            StackerBridge.sendApi(
                buildMap {
                    put("id", id)
                    put("origin", "android")
                    put("method", request.method)
                    put("url", request.url.toString())
                    put("requestTime", requestTime)
                    put("responseTime", System.currentTimeMillis())
                    put("statusCode", response.code)
                    put("requestHeaders", headersOf(request.headers))
                    put("queryParameters", queryOf(request.url))
                    put("requestBody", requestBodyOf(request))
                    put("requestContentType", request.body?.contentType()?.toString())
                    put("requestSizeBytes", request.body?.contentLength()?.toInt() ?: 0)
                    put("responseHeaders", headersOf(response.headers))
                    put("responseBody", responseBodyOf(response))
                    put("responseContentType", response.body?.contentType()?.toString())
                    put("responseSizeBytes", response.body?.contentLength()?.toInt() ?: -1)
                },
            )
        }

        return response
    }

    /** Flattens headers into a map, redacting sensitive values. */
    private fun headersOf(headers: okhttp3.Headers): Map<String, String> {
        val result = LinkedHashMap<String, String>(headers.size)
        for (index in 0 until headers.size) {
            val name = headers.name(index)
            val value = if (name.lowercase() in redactedHeaders) {
                REDACTED
            } else {
                headers.value(index)
            }
            // Repeated headers are joined rather than overwriting each other.
            result[name] = result[name]?.let { "$it, $value" } ?: value
        }
        return result
    }

    private fun queryOf(url: okhttp3.HttpUrl): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        for (name in url.queryParameterNames) {
            val value = url.queryParameterValues(name).joinToString(", ")
            result[name] = if (name.lowercase() in redactedHeaders) REDACTED else value
        }
        return result
    }

    /**
     * Reads the request body without consuming it.
     *
     * `RequestBody.writeTo` may be called repeatedly for a non-one-shot body,
     * so writing into a scratch buffer is safe. One-shot and duplex bodies are
     * skipped, because reading them would break the request.
     */
    private fun requestBodyOf(request: okhttp3.Request): String? {
        val body = request.body ?: return null
        if (body.isDuplex() || body.isOneShot()) {
            return "<one-shot or duplex request body not captured>"
        }
        return runCatching {
            val buffer = Buffer()
            body.writeTo(buffer)
            val charset = body.contentType()?.charset(UTF8) ?: UTF8
            if (!buffer.isProbablyUtf8()) {
                return "<binary ${buffer.size} bytes>"
            }
            val size = minOf(buffer.size, maxBodyBytes)
            val text = buffer.readString(size, charset)
            if (buffer.size > 0) "$text\n\n… truncated" else text
        }.getOrNull()
    }

    /**
     * Reads the response body through [Response.peekBody], which copies rather
     * than consumes — the caller's body stays fully readable.
     */
    private fun responseBodyOf(response: Response): String? {
        val body = response.body ?: return null
        return runCatching {
            val peeked = response.peekBody(maxBodyBytes)
            var source = peeked.source()

            // Manually gunzip: peekBody bypasses BridgeInterceptor's
            // transparent decompression, so a gzipped body would otherwise be
            // reported as binary noise.
            if (response.header("Content-Encoding")
                    .equals("gzip", ignoreCase = true)
            ) {
                val gzipped = Buffer()
                GzipSource(source).use { gzip ->
                    gzipped.writeAll(gzip)
                }
                source = gzipped
            }

            val buffer = Buffer()
            source.readAll(buffer)
            if (!buffer.isProbablyUtf8()) {
                return "<binary ${buffer.size} bytes>"
            }
            val charset = body.contentType()?.charset(UTF8) ?: UTF8
            buffer.readString(charset)
        }.getOrNull()
    }
}

/**
 * Heuristic for whether a buffer holds text, borrowed from OkHttp's own
 * logging interceptor: a NUL or unassigned control character means binary.
 */
private fun Buffer.isProbablyUtf8(): Boolean {
    return try {
        val prefix = Buffer()
        val byteCount = if (size < 64) size else 64
        copyTo(prefix, 0, byteCount)
        for (i in 0 until 16) {
            if (prefix.exhausted()) break
            val codePoint = prefix.readUtf8CodePoint()
            if (Character.isISOControl(codePoint) && !Character.isWhitespace(codePoint)) {
                return false
            }
        }
        true
    } catch (_: EOFException) {
        false
    }
}
