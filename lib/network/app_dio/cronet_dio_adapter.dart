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
  // 注：CronetClient 无公开构造（仅 defaultCronetEngine 工厂），不支持自定义 engine
  CronetDioAdapter() : _client = CronetClient.defaultCronetEngine();

  final CronetClient _client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.data is FormData) {
      return _sendMultipart(options, cancelFuture);
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

    final streamed = await _sendWithCancel(
      () => _client.send(request),
      options,
      cancelFuture,
    );
    return _toResponseBody(streamed, cancelFuture);
  }

  Future<ResponseBody> _sendMultipart(
    RequestOptions options,
    Future<void>? cancelFuture,
  ) async {
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
    final streamed = await _sendWithCancel(
      () => _client.send(mReq),
      options,
      cancelFuture,
    );
    return _toResponseBody(streamed, cancelFuture);
  }

  Future<http.StreamedResponse> _sendWithCancel(
    Future<http.StreamedResponse> Function() sendFn,
    RequestOptions options,
    Future<void>? cancelFuture,
  ) async {
    if (cancelFuture == null) {
      return sendFn();
    }

    final cancelCompleter = Completer<http.StreamedResponse>();
    cancelFuture.then((_) {
      if (!cancelCompleter.isCompleted) {
        cancelCompleter.completeError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: 'Request cancelled',
          ),
        );
      }
    });

    final sendFuture = sendFn();
    return await Future.any<http.StreamedResponse>([
      sendFuture,
      cancelCompleter.future,
    ]);
  }

  ResponseBody _toResponseBody(
    http.StreamedResponse streamed,
    Future<void>? cancelFuture,
  ) {
    final headers = <String, List<String>>{};
    streamed.headers.forEach((k, v) {
      headers[k] = [v];
    });

    // 包装原始流，使 cancelFuture 触发时能主动取消订阅，停止读取网络数据
    final controller = StreamController<Uint8List>();
    final subscription = streamed.stream.listen(
      (chunk) => controller.add(Uint8List.fromList(chunk)),
      onDone: () => controller.close(),
      onError: (Object e, StackTrace st) => controller.addError(e, st),
      cancelOnError: true,
    );

    cancelFuture?.then((_) {
      subscription.cancel();
      if (!controller.isClosed) {
        controller.close();
      }
    });

    return ResponseBody(
      controller.stream,
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
