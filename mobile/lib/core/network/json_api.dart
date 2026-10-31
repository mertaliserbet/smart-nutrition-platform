import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_config.dart';

typedef JsonApiResponse = ({
  int statusCode,
  Object? body,
  bool hasBody,
  Duration? retryAfter,
});

// No cookies, redirects, automatic retries or credential/response logging.
Future<JsonApiResponse> postJson({
  required String path,
  required Map<String, String> payload,
  Uri? baseUri,
  Duration timeout = const Duration(seconds: 20),
}) => _requestJson(
  method: 'POST',
  path: path,
  payload: payload,
  baseUri: baseUri,
  timeout: timeout,
);

Future<JsonApiResponse> getJson({
  required String path,
  required String accessToken,
  Uri? baseUri,
  Duration timeout = const Duration(seconds: 20),
  void Function()? onUnauthorized,
}) => _requestJson(
  method: 'GET',
  path: path,
  accessToken: accessToken,
  baseUri: baseUri,
  timeout: timeout,
  onUnauthorized: onUnauthorized,
);

Future<JsonApiResponse> _requestJson({
  required String method,
  required String path,
  Map<String, String>? payload,
  String? accessToken,
  Uri? baseUri,
  required Duration timeout,
  void Function()? onUnauthorized,
}) async {
  final origin = baseUri == null
      ? ApiConfig.baseUri
      : ApiConfig.validate(baseUri.toString());
  final client = HttpClient(context: ApiConfig.developmentSecurityContext)
    ..connectionTimeout = timeout;
  try {
    return await (() async {
      // Only relative API paths may receive a bearer credential.
      if (!path.startsWith('/api/v1/') ||
          path.startsWith('//') ||
          path.contains('\\') ||
          Uri.parse(path).hasScheme) {
        throw const FormatException('Invalid API path.');
      }
      final request = await client.openUrl(method, origin.resolve(path));
      request.followRedirects = false;
      if (payload != null) {
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (accessToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      if (payload != null) request.write(jsonEncode(payload));
      final response = await request.close();
      // Revoke access immediately, even if the 401 body is broken or stalls.
      if (response.statusCode == 401) onUnauthorized?.call();
      final retryAfter = _retryAfter(
        response.headers.value(HttpHeaders.retryAfterHeader),
      );
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 65536) {
          return (
            statusCode: response.statusCode,
            body: null,
            hasBody: true,
            retryAfter: retryAfter,
          );
        }
        bytes.addAll(chunk);
      }
      Object? body;
      try {
        if (bytes.isNotEmpty &&
            response.headers.contentType?.mimeType == 'application/json') {
          body = jsonDecode(utf8.decode(bytes));
        }
      } on FormatException {
        body = null;
      }
      return (
        statusCode: response.statusCode,
        body: body,
        hasBody: bytes.isNotEmpty,
        retryAfter: retryAfter,
      );
    })().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

String? apiErrorCode(Object? body) {
  if (body is Map<String, dynamic> && body['requestId'] is String) {
    final error = body['error'];
    if (error is Map<String, dynamic> &&
        error['message'] is String &&
        error['code'] is String) {
      return error['code'] as String;
    }
  }
  return null;
}

Duration? _retryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
  try {
    final delay = HttpDate.parse(value).difference(DateTime.now().toUtc());
    return delay.isNegative ? Duration.zero : delay;
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}
