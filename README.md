# Voiceink

macOS 语音输入工具 —— 按住 Fn 键说话，松开后文字自动输入到当前光标位置。

## 快速上手

1. 前往 [Releases](https://github.com/ztxdcyy/Voiceink/releases) 下载最新的 `Voiceink.zip`
2. 解压后将 `Voiceink.app` 拖入「应用程序」文件夹
3. 终端执行 `xattr -cr /Applications/Voiceink.app`（解除 macOS 门禁限制）
4. 启动应用，按提示授予**辅助功能**和**麦克风**权限
5. 在菜单栏图标 → Settings 中配置 [DashScope API Key](https://bailian.console.aliyun.com/)
6. 在任意输入框按住 Fn 说话，松开即输入

## 特性

- **按住即说**：按住 Fn 键开始录音，松开自动转写并输入
- **Paraformer-v2**：基于阿里云 DashScope Paraformer 实时语音识别，专为中文短语音优化
- **自动标点 & 语气词过滤**：输出自带标点，自动去除"嗯、啊"等口语
- **光标跟随**：胶囊 UI 自动定位到当前输入位置
- **多语言**：支持简体中文、繁體中文、English、日本語、한국어
- **CJK 智能切换**：自动处理中日韩输入法与粘贴的兼容问题
- **剪贴板无损**：注入文字后自动恢复原有剪贴板内容

## 系统要求

- macOS 13.0+
- 辅助功能权限（用于监听 Fn 键和模拟粘贴）
- 麦克风权限
- DashScope API Key

## 构建与运行

```bash
# 构建
make build

# 运行
make run

# 清理
make clean
```

## 配置

首次运行会弹出引导窗口：

1. 授予辅助功能权限
2. 配置 DashScope API Key（在菜单栏图标 → Settings 中设置）

## 技术栈

- Swift 5.9 / Swift Package Manager
- AppKit（纯原生，无 SwiftUI 依赖）
- WebSocket（URLSessionWebSocketTask）
- AVAudioEngine + 手动降采样（音频采集，48kHz→16kHz）
- CGEvent（Fn 键监听与键盘模拟）
- Accessibility API（光标位置获取）

## TODO

- [ ] **常用词录入** — 用户可在设置中添加自定义词汇表（如 "nixlbench" 等专业术语），注入 system prompt 提升识别准确率
- [ ] **本地推理** — 支持纯本地离线转写（基于 whisper.cpp 等），无需 API Key
- [ ] **润色文字** — 转写后可选对文字进行智能润色（修正语法、去口语化、调整格式等）
- [ ] **胶囊实时转写** — 在胶囊 HUD 中流式显示转写文字（当前仅在转写完成后直接注入光标）

## License

MIT
