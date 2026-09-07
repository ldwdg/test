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
  // 共享单例 CronetClient：Cronet 每个引擎初始化都会注册一个广播接收器，
  // 若每个 adapter 都新建引擎，会累积撞上 Android 每进程 1000 个 receiver 上限
  // → IllegalStateException: Too many receivers 导致闪退。这里全局共享一个客户端。
  static CronetClient? _sharedClient;

  CronetDioAdapter()
      : _client = _sharedClient ??= CronetClient.defaultCronetEngine();

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
      if (v == null) return;
      // dio 在 _transformData 阶段已用 dio 自己的 boundary 算好
      // content-type 与 content-length 写入 headers；但这里改用
      // http.MultipartRequest 重新组包，finalize() 会生成新的 boundary 并
      // 覆盖 content-type，却不会更新 content-length，导致发出的
      // content-length 与实际 body 长度不一致 → 服务器/Cloudflare 返回 400。
      // 因此这里不复制这两个头，交给 http 包按自己的 boundary 重新计算。
      final lowerKey = k.toLowerCase();
      if (lowerKey == 'content-type' || lowerKey == 'content-length') {
        return;
      }
      mReq.headers[k] = '$v';
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
