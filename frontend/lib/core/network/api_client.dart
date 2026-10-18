/// The ONE HTTP client every repository uses (assignment §7: centralized
/// HTTP, no scattered endpoints).
///
/// Responsibilities: base URL + timeout, JSON encode/decode, bearer auth
/// header, backend error-envelope parsing into [ApiException], transport
/// failure normalization, and a single 401 hook so the auth layer can clear
/// the session the moment the server rejects the token. Repositories only
/// ever call [get]/[post] with a path under `/api/v1`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/http.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// Async bearer-token lookup, injected by the auth layer (avoids a circular
/// dependency between networking and state).
typedef TokenProvider = Future<String?> Function();

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    Duration? timeout,
    this.tokenProvider,
    this.onUnauthorized,
  }) : _http = httpClient ?? http.Client(),
       baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _timeout = timeout ?? AppConfig.apiTimeout;

  final http.Client _http;
  final Duration _timeout;

  /// Base URL including `/api/v1`, no trailing slash.
  final String baseUrl;

  /// Async bearer-token lookup, injected by the auth layer (avoids a
  /// circular dependency between networking and state).
  TokenProvider? tokenProvider;

  /// Invoked whenever the server answers 401 so the auth controller can
  /// clear the session and stop protected polling.
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final uri = _uri(path, query);
    final merged = await _headers(headers);
    return _send(() => _http.get(uri, headers: merged));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = _uri(path, null);
    final merged = await _headers(headers, jsonBody: true);
    return _send(
      () => _http.post(uri, headers: merged, body: jsonEncode(body ?? {})),
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final uri = _uri(path, query);
    final merged = await _headers(headers, jsonBody: true);
    return _send(
      () => _http.patch(uri, headers: merged, body: jsonEncode(body ?? {})),
    );
  }

  Uri _uri(String path, Map<String, String>? query) {
    final base = Uri.parse('$baseUrl/$path');
    return query == null || query.isEmpty
        ? base
        : base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  Future<Map<String, String>> _headers(
    Map<String, String>? extra, {
    bool jsonBody = false,
  }) async {
    final headers = <String, String>{...?extra};
    if (jsonBody) headers['Content-Type'] = 'application/json';
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _send(Future<Response> Function() send) async {
    final Response response;
    try {
      response = await send().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        code: 'timeout',
        message:
            'The server did not respond in time. Your request may still be '
            'processing — retrying is safe.',
      );
    } on ClientException catch (exc) {
      throw ApiException(
        code: 'network_error',
        message:
            'Could not reach the server. Check your connection (${exc.message}).',
      );
    } on Exception catch (exc) {
      // VM platforms surface SocketException and friends directly; treat any
      // unexpected transport-level failure uniformly (web-safe: no dart:io).
      throw ApiException(
        code: 'network_error',
        message: 'Could not reach the server. Check your connection ($exc).',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      // Non-JSON body (e.g. a proxy error page) — normalize.
      throw ApiException(
        statusCode: response.statusCode,
        code: 'UNEXPECTED_RESPONSE',
        message: 'The server returned an unexpected response.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final error = decoded['error'];
    final envelope = error is Map<String, dynamic>
        ? error
        : const <String, dynamic>{};
    final apiException = ApiException(
      statusCode: response.statusCode,
      code: (envelope['code'] as String?) ?? 'HTTP_ERROR',
      message:
          (envelope['message'] as String?) ??
          'Request failed (${response.statusCode}).',
      details: envelope['details'] is Map<String, dynamic>
          ? envelope['details'] as Map<String, dynamic>
          : null,
      requestId:
          (envelope['request_id'] as String?) ??
          response.headers['x-request-id'],
    );
    if (apiException.isUnauthorized) onUnauthorized?.call();
    throw apiException;
  }

  /// Release the underlying HTTP connection pool.
  void close() => _http.close();
}
