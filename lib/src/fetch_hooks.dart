import 'dart:async';

/// Produces an authentication body for [url], or null to skip authentication.
///
/// Called when a fetch is challenged (HTTP 401 with a `WWW-Authenticate`
/// header), or up front when the caller asked for `preAuth`. Invoked per
/// actual network attempt — never cached by the package — so time-bound or
/// single-use credentials stay valid on retries.
typedef ZeroRequestAuth = FutureOr<String?> Function(String url);

/// Transforms a downloaded response body before it is cached and decoded.
///
/// Receives the raw bytes and the response headers (lowercase names); returns
/// the bytes to store. Return the input unchanged for responses that need no
/// work. Throwing fails the load — the image reports an error instead of
/// rendering the untransformed bytes.
typedef ZeroResponseTransform = FutureOr<List<int>> Function(
    List<int> bytes, Map<String, String> headers);

/// App-installed hooks that teach the cache how to fetch protected content —
/// without the package knowing anything about the app's protocol.
///
/// The package's own behavior is plain HTTP: GET the URL, cache the body.
/// Some servers gate their content: they answer an unauthenticated request
/// with `401` + a `WWW-Authenticate` challenge (RFC 7235), expecting the
/// client to retry with credentials; some mark their response bodies as
/// needing client-side post-processing (e.g. decryption) via a response
/// header. Both concerns are the APP's — what to sign, what header to look
/// for, how to decrypt — so both arrive here as injected callbacks:
///
/// - [requestAuth] is called when a fetch gets challenged (and up front for
///   fetches made with `preAuth: true`); the returned string is sent as the
///   request body on the retry. Return null to leave the 401 as the result.
/// - [responseTransform] is called on every downloaded body when set; the
///   returned bytes are what gets cached and decoded.
///
/// Set once at app startup:
/// ```dart
/// ZeroFetchHooks.requestAuth = (url) => myAuth.envelopeFor(url);
/// ZeroFetchHooks.responseTransform = (bytes, headers) =>
///     headers['x-my-sealed'] != null ? myCrypto.open(bytes) : bytes;
/// ```
class ZeroFetchHooks {
  ZeroFetchHooks._();

  static ZeroRequestAuth? requestAuth;
  static ZeroResponseTransform? responseTransform;
}
