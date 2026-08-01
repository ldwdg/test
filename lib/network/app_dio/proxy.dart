import 'dart:io';

import 'package:dio/io.dart';
import 'package:eros_fe/index.dart';
import 'package:flutter_socks_proxy/socks_proxy.dart';
import 'package:get/get.dart';
import 'package:system_proxy/system_proxy.dart';

class HttpProxyAdapter extends IOHttpClientAdapter {
  HttpProxyAdapter({required this.proxy, bool? skipCertificate}) {
    createHttpClient = () {
      final client = createProxyHttpClient();
      if (proxy.isNotEmpty) {
        // logger.d('set proxy $proxy');
        client.findProxy = (url) => proxy;
      }
      if (proxy != 'DIRECT' || (skipCertificate ?? false)) {
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      }
      return client;
    };
  }

  final String proxy;
}

Future<String> getProxy({
  ProxyType proxyType = ProxyType.system,
  String? proxyHost,
  int? proxyPort,
  String? proxyUsername,
  String? proxyPassword,
}) async {
  String proxy = '$proxyHost:$proxyPort';
  if (proxyUsername != null &&
      proxyUsername.isNotEmpty &&
      proxyPassword != null &&
      proxyPassword.isNotEmpty) {
    proxy = '$proxyUsername:$proxyPassword@$proxy';
  }
  switch (proxyType) {
    case ProxyType.system:
      if (GetPlatform.isMobile) {
        Map<String, String>? systemProxy = await SystemProxy.getProxySettings();
        if (systemProxy != null) {
          proxy = 'PROXY ${systemProxy['host']}:${systemProxy['port']}';
        } else {
          proxy = 'DIRECT';
        }
      }

      if (GetPlatform.isDesktop) {
        // Linux/桌面端改用环境变量代理（原 system_network_proxy 插件已移除）
        final proxyEnv = Platform.environment['http_proxy'] ??
            Platform.environment['HTTP_PROXY'] ??
            Platform.environment['https_proxy'] ??
            Platform.environment['HTTPS_PROXY'];
        logger.d('proxyEnv: $proxyEnv');
        final proxyUri = proxyEnv != null ? Uri.tryParse(proxyEnv) : null;
        if (proxyUri != null && proxyUri.host.isNotEmpty) {
          proxy = 'PROXY ${proxyUri.host}:${proxyUri.port}';
        } else {
          proxy = 'DIRECT';
        }
      }
      break;
    case ProxyType.http:
      proxy = 'PROXY $proxy';
      break;
    case ProxyType.socks5:
      proxy = 'SOCKS5 $proxy';
      break;
    case ProxyType.socks4:
      proxy = 'SOCKS4 $proxy';
      break;
    case ProxyType.direct:
      proxy = 'DIRECT';
      break;
  }

  return proxy;
}
