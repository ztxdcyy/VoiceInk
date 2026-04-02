# Voiceink

macOS 语音输入工具 —— 按住 Fn 键说话，松开后文字自动输入到当前光标位置。

## 特性

- **按住即说**：按住 Fn 键开始录音，松开自动转写并输入
- **实时转写**：基于阿里云 DashScope Qwen-Omni-Realtime 模型
- **光标跟随**：浮动胶囊 UI 自动定位到当前输入位置
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
- AVAudioEngine（音频采集与格式转换）
- CGEvent（Fn 键监听与键盘模拟）
- Accessibility API（光标位置获取）

## License

MIT
