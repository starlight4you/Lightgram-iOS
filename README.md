# Lightgram iOS

基于 [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) 的 fork，面向老款 iPad（iPad Air 2 / iPad mini 4 / iPad Pro 第一代等）做了 **Lite Mode** 性能优化，在保留核心聊天功能的前提下降低 GPU / CPU 负载。

> **免责声明**：本项目为第三方客户端，与 Telegram 官方无关。请遵守 [Telegram API 使用条款](https://core.telegram.org/api/terms)，不要使用「Telegram」作为应用名称，也不要使用官方 logo。

## 功能概览

Lite Mode 开启后会：

- 关闭 `UIVisualEffectView` 毛玻璃、壁纸渐变动画、Confetti / Dust 粒子特效
- 隐藏 Stories 入口并停止 Stories 网络同步
- 限制刷新率为 60 Hz，缩小列表预加载范围，减少 emoji / GIF 并发解码
- 在无法使用 App Groups 时自动回退到 Application Support 目录（适配免费 Personal Team 签名）

完整技术说明见 [`docs/lite-mode.md`](docs/lite-mode.md)。

在应用内：**设置 → 实验性功能 → Lite Mode** 可手动开关；老款 iPad 会自动建议开启。

## 环境要求

- macOS + Xcode（版本见 [`versions.json`](versions.json)）
- Python 3
- [Bazel](https://bazel.build/)（`Make.py` 会自动下载匹配版本）

## 获取代码

```sh
git clone --recursive -j8 https://github.com/starlight4you/lightgram-ios.git
cd lightgram-ios
```

## 配置（必读）

### 1. 申请 Telegram API 凭证

前往 <https://my.telegram.org/apps> 创建应用，记下 `api_id` 和 `api_hash`。

**切勿将真实的 `api_id` / `api_hash` 提交到 Git。**

### 2. 准备本地配置文件

```sh
cp build-system/lite-development-configuration.json.example \
   build-system/lite-development-configuration.json
```

编辑 `build-system/lite-development-configuration.json`，填入：

| 字段 | 说明 |
|------|------|
| `bundle_id` | 你的 Bundle ID，如 `org.example.lightgram` |
| `api_id` | 从 my.telegram.org 获取 |
| `api_hash` | 从 my.telegram.org 获取 |
| `team_id` | Apple Developer Team ID（Xcode → Signing 或 Keychain 证书详情中查看） |

该文件已在 `.gitignore` 中，不会被 git 跟踪。

### 3. 生成 Xcode 工程

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    generateProject \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --disableExtensions \
    --buildNumber=1
```

然后打开 `Telegram/Telegram.xcodeproj` 进行编译或调试。

## 构建

### 模拟器（无需签名）

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --buildNumber=1 \
    --configuration=debug_sim_arm64
```

### 真机（免费 Apple ID / Personal Team）

在 `generateProject` 命令中加上 `--disableExtensions`，构建配置使用 `debug_arm64`：

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --disableExtensions \
    --buildNumber=1 \
    --configuration=debug_arm64
```

首次真机构建可能需要 1–2 小时。更多排错说明见 [`docs/lite-mode.md`](docs/lite-mode.md#build)。

## 上游文档

通用编译问题（Bazel 缓存、Xcode 版本、签名等）可参考上游 README 的 [FAQ](https://github.com/TelegramMessenger/Telegram-iOS#faq) 章节，或本仓库 [`docs/lite-mode.md`](docs/lite-mode.md)。

## 许可证

本项目继承 Telegram-iOS 的 [GPL v2](LICENSE) 许可证。修改后的源代码须按相同许可证公开。
