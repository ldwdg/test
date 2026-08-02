# eros_fe 开发约定

## 项目身份
- 应用名: Eros-EH+（Android 包名 com.ldwdg.erosehentai，版本 2.0.0+567）
- fork 自 erosTeam/eros_fe，开发用 Aider + DeepSeek

## 技术栈
Flutter (stable, 3.44.8, 经 FVM 管理) + GetX 状态管理 + dio 网络 + HTML parser 抓取

## 常用命令
- 依赖安装: flutter pub get
- 静态检查: flutter analyze（改动后必须 0 error）
- 运行 (Linux 桌面调试): flutter run -d linux
- 测试: flutter test
- Android 打包: flutter build apk --release（已配置签名，keystore 见 android/key.properties）

## 架构约定
- 状态管理一律用 GetX：controller 继承 GetxController，页面用 GetView/Obx
- 网络层走 lib/common/service/ 或 lib/network/app_dio/，禁止页面内直接发请求
- 抓取逻辑放 lib/common/parser/，禁止在 UI 层写 HTML 解析
- 新增页面遵循 lib/pages/<feature>/ 目录结构
- 数据模型放 lib/models/

## 本 fork 的改动（与上游不同，勿回退）
- 已移除 sentry_flutter（错误上报）
- 已移除 system_network_proxy（Linux 插件不可用），桌面端代理改读环境变量 http_proxy/HTTPS_PROXY（见 lib/network/app_dio/proxy.dart）
- lib/config/config.dart 为本地产明文配置，已被 .gitignore 排除，禁止提交

## 禁区
- 禁止修改 lib/config/config.dart（用户私密配置）
- 禁止整体重构、禁止大规模重命名
- 界面文案改动必须同步 lib/l10n/ 下全部 6 种语言 .arb
- 禁止触碰 lib/generated/（自动生成文件）
- 禁止提交 .env、libisar.so、build/ 产物

## 修改流程
1. 先读相关文件，复述理解的数据流再动手
2. 改完必须跑 flutter analyze，修复全部 error
3. 保持改动最小化，遵循既有代码风格
