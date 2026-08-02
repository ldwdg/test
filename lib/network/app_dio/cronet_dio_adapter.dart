import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cronet_http/cronet_http.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// dio HttpClientAdapter 桥接：Android 端使用 Cronet 网络栈（HTTP/2 + QUIC）
///
/// 注意：Cronet 使用系统代理设置（无自定义代理 API）。
/// 若应用依赖自定义代理（非系统代理），需在 Android 上启用系统代理/VPN。
class CronetDioAdapter implements HttpClientAdapter {
  CronetDioAdapter({CronetEngine? engine})
      : _client = engine != null
            ? CronetClient.defaultCronetEngine()
            : CronetClient.defaultCronetEngine();

  final CronetClient _client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.data is FormData) {
      return _sendMultipart(options);
    }

    final request = http.Request(options.method, options.uri);
    options.headers.forEach((k, v) {
      if (v != null) request.headers[k] = '$v';
    });

    if (options.data != null) {
      if (options.data is String) {
        request.body = options.data as String;
      } else {
        request.body = jsonEncode(options.data);
        request.headers.putIfAbsent('content-type', () => 'application/json');
      }
    } else if (requestStream != null) {
      final bytes = await requestStream.expand((c) => c).toList();
      request.bodyBytes = bytes;
    }

    final streamed = await _client.send(request);
    return _toResponseBody(streamed);
  }

  Future<ResponseBody> _sendMultipart(RequestOptions options) async {
    final fd = options.data as FormData;
    final mReq = http.MultipartRequest(options.method, options.uri);
    options.headers.forEach((k, v) {
      if (v != null) mReq.headers[k] = '$v';
    });
    for (final f in fd.fields) {
      mReq.fields[f.key] = f.value;
    }
    for (final f in fd.files) {
      final bytes = await f.value.finalize().expand((c) => c).toList();
      mReq.files.add(http.MultipartFile.fromBytes(
        f.key,
        bytes,
        filename: f.value.filename,
      ));
    }
    final streamed = await _client.send(mReq);
    return _toResponseBody(streamed);
  }

  ResponseBody _toResponseBody(http.StreamedResponse streamed) {
    final headers = <String, List<String>>{};
    streamed.headers.forEach((k, v) {
      headers[k] = [v];
    });
    return ResponseBody(
      streamed.stream.map((chunk) => Uint8List.fromList(chunk)),
      streamed.statusCode,
      headers: headers,
      statusMessage: streamed.reasonPhrase,
      isRedirect: streamed.isRedirect,
    );
  }

  @override
  void close({bool force = false}) {
    _client.close();
  }
}
