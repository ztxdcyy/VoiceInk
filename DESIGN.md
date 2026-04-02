# Voiceink — macOS Menu Bar 语音输入法

> 按住 Fn 说话，松开即输入。基于阿里云百炼 Qwen-Omni-Realtime 的实时语音转文字 macOS 菜单栏应用。

---

## 1. 项目概述

### 1.1 核心功能

用户按住 Fn 键录音，应用通过 WebSocket 将实时音频流发送至 Qwen-Omni-Realtime API，模型返回转录文本，松开 Fn 后将最终文本注入当前聚焦的输入框。

### 1.2 技术栈

| 项 | 选型 |
|---|---|
| 语言 | Swift 5.9+ |
| 最低系统 | macOS 14.0 (Sonoma) |
| UI 框架 | AppKit (NSMenu, NSPanel, NSVisualEffectView) |
| 音频 | AVAudioEngine |
| 网络 | URLSessionWebSocketTask |
| 构建 | Swift Package Manager + Makefile |
| ASR 后端 | 阿里云百炼 Qwen-Omni-Realtime (WebSocket) |

### 1.3 运行模式

- `LSUIElement = true`：仅菜单栏图标，无 Dock 图标
- 构建产物为签名的 `.app` bundle

---

## 2. 项目结构

```
Voiceink/
├── Package.swift
├── Makefile
├── README.md
├── DESIGN.md
└── Sources/
    └── Voiceink/
        ├── App/
        │   ├── AppDelegate.swift          # 应用入口, NSApplication delegate
        │   ├── MenuBarManager.swift        # 菜单栏图标 & 菜单管理
        │   └── PermissionManager.swift     # 辅助功能 & 麦克风权限引导
        ├── Audio/
        │   ├── AudioEngine.swift           # AVAudioEngine 录音 + RMS 计算 + PCM 提取
        │   └── AudioFormat.swift           # 音频格式常量 & 重采样配置
        ├── HotKey/
        │   └── FnKeyMonitor.swift          # CGEvent tap 全局 Fn 键监听
        ├── WebSocket/
        │   ├── RealtimeAPIClient.swift     # WebSocket 连接管理 & 事件收发
        │   ├── RealtimeModels.swift        # API 请求/响应 JSON 模型
        │   └── RealtimeProtocol.swift      # 事件类型枚举 & 协议定义
        ├── UI/
        │   ├── CapsulePanel.swift          # 悬浮胶囊窗口 (NSPanel)
        │   ├── WaveformView.swift          # 实时音频波形动画视图
        │   └── TranscriptLabel.swift       # 弹性宽度转录文本标签
        ├── TextInjection/
        │   ├── TextInjector.swift          # 剪贴板 + Cmd+V 注入逻辑
        │   └── InputSourceManager.swift    # CJK 输入法检测 & 切换
        ├── Settings/
        │   ├── SettingsWindowController.swift  # 设置窗口
        │   └── SettingsStore.swift         # UserDefaults 持久化
        └── Resources/
            └── Info.plist                  # LSUIElement, 麦克风描述等
```

---

## 3. 详细模块设计

### 3.1 App 生命周期 (`App/`)

#### AppDelegate.swift

```
职责: NSApplicationDelegate，应用启动入口
```

- 启动时初始化所有 Manager 单例
- 启动顺序：
  1. `SettingsStore.shared` — 加载持久化配置
  2. `PermissionManager.shared` — 检查并请求权限
  3. `MenuBarManager.shared` — 创建菜单栏图标
  4. `FnKeyMonitor.shared` — 注册全局按键监听
- 不使用 SwiftUI App lifecycle，直接使用 `NSApplication` + `AppDelegate`
- main.swift 作为入口：

```swift
// main.swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

#### MenuBarManager.swift

```
职责: 菜单栏图标和下拉菜单管理
```

- 使用 `NSStatusBar.system.statusItem(withLength: .squareLength)`
- 图标：使用 SF Symbol `mic.fill`（录音中变为 `mic.badge.plus`）
- 菜单项：
  - **语言**: 子菜单，单选项 (✓ 标记当前选择)
    - 简体中文 (zh-CN) ← 默认
    - English (en)
    - 繁體中文 (zh-TW)
    - 日本語 (ja)
    - 한국어 (ko)
  - **分隔线**
  - **Settings...**: 打开设置窗口
  - **Launch at Login**: 开关项，通过 SMAppService 控制
  - **分隔线**
  - **Quit Voiceink**: 退出 (`⌘Q`)

#### PermissionManager.swift

```
职责: 权限检测与引导
```

**需要的权限：**

| 权限 | 用途 | API |
|---|---|---|
| 辅助功能 (Accessibility) | CGEvent tap 全局按键监听 + 模拟 Cmd+V | `AXIsProcessTrusted()` |
| 麦克风 | 音频录制 | `AVCaptureDevice.requestAccess(for: .audio)` |

**流程：**
1. 启动时调用 `AXIsProcessTrustedWithOptions` 检查辅助功能权限
2. 如未授权，显示 Alert 引导用户到 System Settings → Privacy & Security → Accessibility
3. 麦克风权限在首次录音时由系统自动弹窗请求（Info.plist 中配置 `NSMicrophoneUsageDescription`）
4. 权限状态变化后通过 `NotificationCenter` 广播

---

### 3.2 Fn 键全局监听 (`HotKey/`)

#### FnKeyMonitor.swift

```
职责: 全局监听 Fn (Globe) 键的按下/松开，抑制系统默认行为
```

**实现方案：**

使用 `CGEvent.tapCreate` 创建系统级事件监听器：

```swift
let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,       // 可修改/拦截事件
    eventsOfInterest: eventMask,
    callback: fnEventCallback,
    userInfo: pointer
)
```

**Fn 键检测逻辑：**

Fn 键不产生 keyDown/keyUp，而是通过 `flagsChanged` 事件的 `CGEventFlags` 变化来检测：

```swift
func fnEventCallback(...) -> Unmanaged<CGEvent>? {
    let flags = CGEventFlags(rawValue: event.flags.rawValue)
    let fnPressed = flags.contains(.maskSecondaryFn)

    if fnPressed && !wasPressed {
        // Fn 按下 → 开始录音
        NotificationCenter.default.post(name: .fnKeyDown, object: nil)
    } else if !fnPressed && wasPressed {
        // Fn 松开 → 停止录音
        NotificationCenter.default.post(name: .fnKeyUp, object: nil)
    }

    // 返回 nil 抑制事件传递，防止触发 emoji 选择器
    if isFnEvent {
        return nil
    }
    return Unmanaged.passRetained(event)
}
```

**关键细节：**

- `CGEventFlags.maskSecondaryFn` (rawValue: `0x00000020`) 即 Fn 标志位
- 返回 `nil` 吞掉事件，阻止 emoji 选择器触发
- 必须通过 `CFRunLoopSourceRef` 加入 RunLoop 才能生效
- 需要辅助功能权限，否则 tap 会被自动禁用
- **已知风险**：macOS 14+ 部分场景下 Fn/Globe 键走更底层的路径可能无法 100% 拦截。应在 README 中建议用户在 System Settings → Keyboard 中将 Globe 键设为 "Do Nothing"

**状态机：**

```
Idle ──(Fn down)──→ Recording ──(Fn up)──→ WaitingForResult ──(text.done)──→ Injecting ──→ Idle
                        │                        │
                        └──(Fn up <0.3s)──→ Cancelled → Idle   (防误触)
```

- 按住时间 < 300ms 视为误触，不发送请求
- `WaitingForResult` 状态下胶囊窗口显示 spinner

---

### 3.3 音频引擎 (`Audio/`)

#### AudioFormat.swift

```
职责: 音频格式常量定义
```

```swift
enum AudioFormat {
    /// Qwen-Omni-Realtime 要求的输入格式
    static let sampleRate: Double = 16_000     // 16 kHz
    static let channels: AVAudioChannelCount = 1  // Mono
    static let bitDepth: Int = 16              // 16-bit signed integer
    static let bytesPerSample: Int = 2         // 16-bit = 2 bytes

    /// 目标 PCM 格式
    static var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!
    }

    /// 每次发送的音频帧时长（毫秒）
    static let frameDurationMs: Int = 100      // 100ms per frame
    /// 每帧采样数
    static let samplesPerFrame: Int = Int(sampleRate) * frameDurationMs / 1000  // 1600
}
```

#### AudioEngine.swift

```
职责: AVAudioEngine 录音管理，同时输出 RMS 电平 & PCM Base64 数据
```

**核心接口：**

```swift
protocol AudioEngineDelegate: AnyObject {
    /// RMS 电平更新 (0.0 ~ 1.0)，用于驱动波形动画
    func audioEngine(_ engine: AudioEngine, didUpdateRMSLevel level: Float)
    /// PCM 音频帧 (Base64 编码)，用于发送给 WebSocket
    func audioEngine(_ engine: AudioEngine, didCaptureAudioFrame base64PCM: String)
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?
    func startRecording() throws
    func stopRecording()
}
```

**实现要点：**

1. **重采样**：AVAudioEngine 的 inputNode 默认采样率为硬件采样率（通常 48kHz）。使用 `installTap` 时指定目标格式为 16kHz/16-bit/mono，AVAudioEngine 会自动通过内部格式转换器完成重采样：

```swift
let inputNode = engine.inputNode
let hardwareFormat = inputNode.outputFormat(forBus: 0)

// 创建 16kHz 目标格式
let targetFormat = AudioFormat.targetFormat

// 如果硬件格式与目标不同，需要通过 mixer 节点做转换
let mixerNode = AVAudioMixerNode()
engine.attach(mixerNode)
engine.connect(inputNode, to: mixerNode, format: hardwareFormat)

mixerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(AudioFormat.samplesPerFrame), format: targetFormat) { [weak self] buffer, time in
    self?.processAudioBuffer(buffer)
}
```

2. **processAudioBuffer 同时计算 RMS 和提取 PCM**：

```swift
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let int16Data = buffer.int16ChannelData else { return }
    let frameLength = Int(buffer.frameLength)
    let channelData = int16Data[0]

    // 1. 计算 RMS
    var sumOfSquares: Float = 0
    for i in 0..<frameLength {
        let sample = Float(channelData[i]) / Float(Int16.max)
        sumOfSquares += sample * sample
    }
    let rms = sqrt(sumOfSquares / Float(frameLength))
    delegate?.audioEngine(self, didUpdateRMSLevel: rms)

    // 2. 提取 PCM 并 Base64 编码
    let data = Data(bytes: channelData, count: frameLength * AudioFormat.bytesPerSample)
    let base64 = data.base64EncodedString()
    delegate?.audioEngine(self, didCaptureAudioFrame: base64)
}
```

3. **线程安全**：Tap 回调在音频线程上执行，RMS 更新需 dispatch 到主线程驱动 UI；Base64 数据可在后台队列发送给 WebSocket。

---

### 3.4 WebSocket 实时 API 客户端 (`WebSocket/`)

#### RealtimeModels.swift

```
职责: API 请求/响应的 Codable 模型
```

**客户端事件 (Client → Server):**

```swift
// 1. session.update
struct SessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: SessionConfig
}

struct SessionConfig: Encodable {
    let modalities: [String]           // ["text"]
    let instructions: String           // System prompt
    let input_audio_format: String     // "pcm"
    let turn_detection: TurnDetection? // nil = Manual 模式
}

// 2. input_audio_buffer.append
struct AudioAppendEvent: Encodable {
    let type = "input_audio_buffer.append"
    let audio: String                  // Base64 PCM
}

// 3. input_audio_buffer.commit
struct AudioCommitEvent: Encodable {
    let type = "input_audio_buffer.commit"
}

// 4. response.create (Manual 模式必须！)
struct ResponseCreateEvent: Encodable {
    let type = "response.create"
}
```

**服务端事件 (Server → Client):**

```swift
enum ServerEventType: String, Decodable {
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"
    case inputAudioBufferCommitted = "input_audio_buffer.committed"
    case responseCreated = "response.created"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseDone = "response.done"
    case error = "error"
}

struct ServerEvent: Decodable {
    let type: String
    // 以下字段为可选，根据事件类型存在
    let delta: String?         // response.text.delta 的增量文本
    let text: String?          // response.text.done 的完整文本
    let error: APIError?       // error 事件
}
```

#### RealtimeProtocol.swift

```
职责: 事件类型常量 & 委托协议
```

```swift
protocol RealtimeAPIClientDelegate: AnyObject {
    func realtimeClient(_ client: RealtimeAPIClient, didReceiveTranscriptDelta delta: String)
    func realtimeClient(_ client: RealtimeAPIClient, didCompleteTranscript text: String)
    func realtimeClient(_ client: RealtimeAPIClient, didEncounterError error: Error)
    func realtimeClientDidConnect(_ client: RealtimeAPIClient)
    func realtimeClientDidDisconnect(_ client: RealtimeAPIClient)
}
```

#### RealtimeAPIClient.swift

```
职责: WebSocket 连接生命周期管理 & 事件收发
```

**连接建立：**

```swift
class RealtimeAPIClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    func connect() {
        let settings = SettingsStore.shared
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            delegate?.realtimeClient(self, didEncounterError: VoiceinkError.missingAPIKey)
            return
        }

        let model = settings.model  // 默认 "qwen-omni-turbo-latest"
        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(model)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        listenForMessages()
    }
}
```

**会话配置 (连接成功后立即发送)：**

```swift
func sendSessionUpdate() {
    let language = SettingsStore.shared.language  // e.g. "zh-CN"
    let languageName = SettingsStore.shared.languageDisplayName  // e.g. "简体中文"

    let instructions = """
    你是一个精确的语音转录助手。用户的主要语言是\(languageName)。
    请将用户的语音准确转录为文字。规则：
    1. 只输出转录后的文字，不要包含任何解释、对话、问候或额外内容。
    2. 只修复明显的语音识别错误：
       - 中文谐音错误（如"配森"→"Python"、"杰森"→"JSON"）
       - 英文技术术语被错误转为中文拼音
       - 明显的同音字错误
    3. 保持用户原始的表达方式、语序和用词，绝对不要改写、润色、缩减或扩充内容。
    4. 如果用户说了中英文混杂的内容，保持原始的混杂方式。
    5. 正确添加标点符号。
    """

    let config = SessionConfig(
        modalities: ["text"],
        instructions: instructions,
        input_audio_format: "pcm",
        turn_detection: nil  // Manual 模式
    )

    let event = SessionUpdateEvent(session: config)
    sendEvent(event)
}
```

**关键交互流程 (Manual 模式)：**

```
连接成功 → session.update → [等待 session.updated]

按住 Fn:
    → 循环发送 input_audio_buffer.append (每100ms一帧)

松开 Fn:
    → input_audio_buffer.commit
    → response.create              ← ⚡ 关键！不发此事件模型不会响应
    → [接收 response.text.delta...]  ← 增量文本，驱动实时显示
    → [接收 response.text.done]      ← 最终完整文本
    → [接收 response.done]           ← 响应结束，可以注入文字
```

**连接策略：**

- **懒连接**：不在启动时连接，在用户首次按下 Fn 时建立 WebSocket 连接
- **连接复用**：一次连接可以处理多次录音（多轮对话）
- **心跳**：WebSocket 层面依赖 URLSession 默认的 ping/pong
- **超时**：松开 Fn 后 15 秒未收到 `response.done`，视为超时，显示错误并关闭连接
- **断线重连**：连接异常断开时，下次按 Fn 自动重新建立连接
- **会话上限**：单次 WebSocket 连接最长 120 分钟（API 限制），超时后自动重连

**错误处理：**

| 错误类型 | 处理方式 |
|---|---|
| API Key 缺失/无效 | 弹出 Settings 窗口 |
| 网络不可用 | 胶囊窗口显示 "网络不可用" |
| 余额不足 / 限流 | 胶囊窗口显示错误信息 |
| WebSocket 意外断开 | 自动重连，重连失败显示错误 |
| 响应超时 (15s) | 胶囊窗口显示 "请求超时"，关闭当前请求 |

---

### 3.5 悬浮胶囊窗口 (`UI/`)

#### CapsulePanel.swift

```
职责: 录音时在屏幕底部居中显示的无边框悬浮窗
```

**窗口属性：**

```swift
class CapsulePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        // 关键属性
        self.level = .statusBar            // 浮于大多数窗口之上
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
```

**布局结构：**

```
┌──────────────────────────────────────────────────────┐
│  ┌────────┐  ┌────────────────────────────────────┐  │
│  │ Wave   │  │  转录文本...                        │  │
│  │ Form   │  │                                    │  │
│  │ 44x32  │  │  160px ~ 560px 弹性宽度             │  │
│  └────────┘  └────────────────────────────────────┘  │
│              56px 高, 圆角半径 28px                    │
└──────────────────────────────────────────────────────┘
```

- 外层：`NSVisualEffectView`，material = `.hudWindow`，blendingMode = `.behindWindow`
- 高度固定 56px，圆角半径 28px (胶囊形状)
- 左侧：`WaveformView` (44×32px)，左边距 16px
- 右侧：`TranscriptLabel` (弹性宽度 160~560px)，左右边距各 12px
- 总宽度 = 16 + 44 + 12 + textWidth + 16 = 88 + textWidth
- 最小宽度：88 + 160 = 248px（无文字/短文字时）
- 最大宽度：88 + 560 = 648px（长文字时）

**定位：**

- 屏幕底部居中，距底边 80px
- 使用 `NSScreen.main` 获取当前主屏幕尺寸
- 宽度变化时重新居中

**动画：**

| 动画 | 参数 |
|---|---|
| 入场 | 从 scale(0.8) + opacity(0) 弹簧动画到 scale(1) + opacity(1)，duration 0.35s，spring damping 0.7 |
| 文字宽度过渡 | NSAnimationContext，duration 0.25s，timingFunction easeInOut |
| 退场 | 从 scale(1) + opacity(1) 到 scale(0.85) + opacity(0)，duration 0.22s |
| 等待中 (WaitingForResult) | 波形区域替换为旋转 spinner (NSProgressIndicator) |

**状态管理：**

```swift
enum CapsuleState {
    case hidden
    case recording           // 显示波形 + 实时文字
    case waitingForResult    // 显示 spinner + 已有文字
    case error(String)       // 显示错误信息
}
```

#### WaveformView.swift

```
职责: 5 根竖条实时音频波形动画，由 RMS 电平驱动
```

**设计参数：**

```swift
let barCount = 5
let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]  // 中间高两侧低
let barWidth: CGFloat = 3.0
let barSpacing: CGFloat = 3.0       // 竖条间距
let barCornerRadius: CGFloat = 1.5  // 竖条圆角
let minBarHeight: CGFloat = 4.0     // 最小高度 (静音时)
let maxBarHeight: CGFloat = 28.0    // 最大高度

// 包络参数
let attackRate: CGFloat = 0.40      // 上升跟随速度 40%
let releaseRate: CGFloat = 0.15     // 下降衰减速度 15%
let jitterAmount: CGFloat = 0.04    // ±4% 随机抖动
```

**RMS 驱动逻辑：**

```swift
/// 平滑包络处理
func updateLevel(_ rawRMS: Float) {
    let normalized = min(CGFloat(rawRMS) * 3.0, 1.0)  // 归一化并放大

    if normalized > smoothedLevel {
        smoothedLevel += (normalized - smoothedLevel) * attackRate
    } else {
        smoothedLevel += (normalized - smoothedLevel) * releaseRate
    }

    // 更新每根竖条
    for i in 0..<barCount {
        let jitter = CGFloat.random(in: -jitterAmount...jitterAmount)
        let height = minBarHeight + (maxBarHeight - minBarHeight)
                     * smoothedLevel * barWeights[i]
                     * (1.0 + jitter)
        barHeights[i] = max(minBarHeight, min(maxBarHeight, height))
    }
    setNeedsDisplay(bounds)
}
```

- 使用 `CADisplayLink`（macOS 上用 `CVDisplayLink` 或 `NSTimer` 60fps）驱动重绘
- 竖条颜色：白色，opacity 0.9
- 竖条垂直居中对齐

#### TranscriptLabel.swift

```
职责: 弹性宽度的转录文本显示
```

- 使用 `NSTextField` (非可编辑), `.labelStyle`
- 字体：`.systemFont(ofSize: 14, weight: .medium)`
- 颜色：`.white`
- 单行显示，超长时 truncation tail (`...`)
- 宽度根据文本内容计算，clamp 在 160~560px 之间
- 宽度变化时通知 `CapsulePanel` 重新计算总宽度并 animate

---

### 3.6 文字注入 (`TextInjection/`)

#### InputSourceManager.swift

```
职责: 检测当前输入法，CJK 输入法临时切换
```

```swift
class InputSourceManager {
    /// 获取当前输入源
    static func currentInputSource() -> TISInputSource

    /// 检测当前输入源是否为 CJK 输入法
    static func isCJKInputSource() -> Bool {
        // 检查 inputSource 的 kTISPropertyInputSourceLanguages
        // 包含 zh, ja, ko 等即为 CJK
    }

    /// 切换到 ASCII 输入源 (ABC / US)
    static func switchToASCII() -> TISInputSource? {
        // 返回切换前的原输入源，用于后续恢复
        // 使用 TISSelectInputSource 切换
    }

    /// 恢复到指定输入源
    static func restore(_ inputSource: TISInputSource) {
        TISSelectInputSource(inputSource)
    }
}
```

**注意**：`TISSelectInputSource` 等 API 来自 Carbon 框架，需要 `import Carbon`。

#### TextInjector.swift

```
职责: 将转录文本注入当前聚焦的输入框
```

**完整注入流程：**

```swift
class TextInjector {
    static func inject(text: String) {
        // 1. 备份当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalContents = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }

        // 2. 写入新文本到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. 检测并处理 CJK 输入法
        var previousInputSource: TISInputSource?
        if InputSourceManager.isCJKInputSource() {
            previousInputSource = InputSourceManager.switchToASCII()
        }

        // 4. 模拟 Cmd+V
        simulatePaste()

        // 5. 延迟恢复 (150ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 恢复输入法
            if let source = previousInputSource {
                InputSourceManager.restore(source)
            }

            // 恢复剪贴板 (再延迟 50ms 确保粘贴完成)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                pasteboard.clearContents()
                if let items = originalContents {
                    pasteboard.writeObjects(items)
                }
            }
        }
    }

    private static func simulatePaste() {
        // 模拟 Cmd+V 按下
        let vKeyCode: CGKeyCode = 9
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

---

### 3.7 设置 (`Settings/`)

#### SettingsStore.swift

```
职责: UserDefaults 持久化存储
```

```swift
class SettingsStore {
    static let shared = SettingsStore()

    @UserDefault(key: "apiKey", defaultValue: nil)
    var apiKey: String?

    @UserDefault(key: "model", defaultValue: "qwen-omni-turbo-latest")
    var model: String

    @UserDefault(key: "language", defaultValue: "zh-CN")
    var language: String

    @UserDefault(key: "launchAtLogin", defaultValue: false)
    var launchAtLogin: Bool

    /// 语言显示名映射
    var languageDisplayName: String {
        switch language {
        case "zh-CN": return "简体中文"
        case "zh-TW": return "繁體中文"
        case "en":    return "English"
        case "ja":    return "日本語"
        case "ko":    return "한국어"
        default:      return "简体中文"
        }
    }
}
```

#### SettingsWindowController.swift

```
职责: 设置窗口 UI
```

**窗口布局：**

```
┌─────────────── Voiceink Settings ───────────────┐
│                                                  │
│  DashScope API Key                               │
│  ┌──────────────────────────────────────────┐    │
│  │ sk-xxxxxxxxxxxxxxxxxxxx                   │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  Model                                           │
│  ┌──────────────────────────────────────────┐    │
│  │ qwen-omni-turbo-latest                    │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│                         [ Test ]    [ Save ]     │
│                                                  │
└──────────────────────────────────────────────────┘
```

- 窗口大小：420 × 200，不可缩放
- API Key 输入框：`NSSecureTextField`，可完全清空
- Model 输入框：`NSTextField`，默认值 `qwen-omni-turbo-latest`
- **Test 按钮**：尝试建立 WebSocket 连接并发送 session.update，收到 session.updated 即为成功，5 秒超时
- **Save 按钮**：保存到 UserDefaults，关闭窗口。如果 WebSocket 已连接则断开重连以应用新配置

---

### 3.8 核心编排 — 录音会话流程

整个应用的核心在于 Fn 按下→松开的一次完整会话。设计一个 `SessionCoordinator` 来编排所有模块：

```swift
class SessionCoordinator: FnKeyMonitorDelegate,
                          AudioEngineDelegate,
                          RealtimeAPIClientDelegate {

    private let audioEngine = AudioEngine()
    private let apiClient = RealtimeAPIClient()
    private let capsulePanel = CapsulePanel()
    private var currentTranscript = ""
    private var state: SessionState = .idle

    enum SessionState {
        case idle
        case connecting         // 首次使用，正在建立 WebSocket
        case recording          // 正在录音 + 发送音频
        case waitingForResult   // 已停止录音，等待最终结果
        case injecting          // 正在注入文字
    }
}
```

**完整流程时序图：**

```
User          FnKeyMonitor    SessionCoordinator    AudioEngine     RealtimeAPI       CapsulePanel     TextInjector
 │                │                  │                   │               │                │                │
 │──press Fn─────→│                  │                   │               │                │                │
 │                │──fnKeyDown──────→│                   │               │                │                │
 │                │                  │──connect()───────→│               │                │                │
 │                │                  │               (if not connected)──→│               │                │
 │                │                  │               ←──sessionCreated───│               │                │
 │                │                  │──sessionUpdate───→│──────────────→│               │                │
 │                │                  │               ←──sessionUpdated───│               │                │
 │                │                  │──startRecording()→│               │                │                │
 │                │                  │──show(recording)─→│               │               │──show()────────→│
 │                │                  │                   │               │                │                │
 │                │                  │←──rmsLevel────────│               │                │                │
 │                │                  │──updateLevel─────→│               │               │──update()──────→│
 │                │                  │←──base64PCM───────│               │                │                │
 │                │                  │──audioAppend─────→│──────────────→│               │                │
 │                │                  │     (repeat every 100ms...)       │                │                │
 │                │                  │                   │               │                │                │
 │──release Fn───→│                  │                   │               │                │                │
 │                │──fnKeyUp────────→│                   │               │                │                │
 │                │                  │──stopRecording()─→│               │                │                │
 │                │                  │──audioCommit─────→│──────────────→│               │                │
 │                │                  │──responseCreate──→│──────────────→│               │                │
 │                │                  │──show(waiting)───→│               │               │──spinner()─────→│
 │                │                  │                   │               │                │                │
 │                │                  │←──textDelta───────│───────────────│               │                │
 │                │                  │──updateText──────→│               │               │──setText()─────→│
 │                │                  │     (repeat for each delta...)    │                │                │
 │                │                  │                   │               │                │                │
 │                │                  │←──textDone────────│───────────────│               │                │
 │                │                  │←──responseDone────│───────────────│               │                │
 │                │                  │──hide()──────────→│               │               │──hide()────────→│
 │                │                  │──inject(text)────→│               │               │                │──inject()
 │                │                  │                   │               │                │                │
```

---

## 4. Info.plist 配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Voiceink</string>
    <key>CFBundleIdentifier</key>
    <string>com.voiceink.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <string>Voiceink</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voiceink 需要使用麦克风来录制您的语音并转换为文字。</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

---

## 5. Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voiceink",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Voiceink",
            path: "Sources/Voiceink",
            resources: [
                .copy("Resources/Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
```

---

## 6. Makefile

```makefile
APP_NAME = Voiceink
BUNDLE_ID = com.voiceink.app
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run install clean

build:
	swift build -c release
	# 创建 .app bundle
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Sources/Voiceink/Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	# Ad-hoc 签名
	codesign --force --sign - "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

install: build
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf .build
```

---

## 7. 关键技术风险与缓解措施

| # | 风险 | 严重性 | 缓解措施 |
|---|---|---|---|
| 1 | Fn 键无法 100% 抑制 emoji 选择器 | 高 | README 引导用户将 System Settings → Keyboard → Globe key 设为 "Do Nothing"；后续版本考虑支持自定义触发键 |
| 2 | 辅助功能权限未授权导致 CGEvent tap 静默失效 | 高 | 启动时主动检测 `AXIsProcessTrusted()`，未授权时弹窗引导，并在 CGEvent tap 上设置 disabled 回调重新启用 |
| 3 | WebSocket 网络延迟导致注入等待过长 | 中 | 15 秒超时机制；delta 增量实时显示让用户感知到进度 |
| 4 | 剪贴板恢复时机不当导致粘贴内容丢失 | 中 | 模拟 Cmd+V 后延迟 200ms 再恢复剪贴板 |
| 5 | AVAudioEngine 重采样质量 | 低 | 通过 MixerNode 中间节点让引擎自动处理格式转换，质量足够 |
| 6 | API 费用 (按音频时长计费) | 低 | 误触保护 (< 300ms 不发送)；UI 上提示正在使用云端 API |

---

## 8. 实现优先级 & 开发路线

### Phase 1: 最小可用版本 (MVP)

按以下顺序实现，每一步都可以独立验证：

| 步骤 | 模块 | 验证方式 |
|---|---|---|
| 1 | `Package.swift` + `main.swift` + `Info.plist` + `Makefile` | `make build` 编译通过 |
| 2 | `AppDelegate` + `MenuBarManager` | 菜单栏图标出现，菜单可交互 |
| 3 | `SettingsStore` + `SettingsWindowController` | Settings 窗口打开/保存/读取正常 |
| 4 | `PermissionManager` | 权限检测和引导流程 |
| 5 | `FnKeyMonitor` | 按住/松开 Fn 键能打印日志 |
| 6 | `AudioEngine` | 录音正常，RMS 电平输出，PCM Base64 输出 |
| 7 | `RealtimeModels` + `RealtimeAPIClient` | 连接 API，发送音频，接收转录文本 |
| 8 | `CapsulePanel` + `WaveformView` + `TranscriptLabel` | 悬浮窗显示，波形动画，文字更新 |
| 9 | `InputSourceManager` + `TextInjector` | 文字注入各种输入框正常 |
| 10 | `SessionCoordinator` | 全流程串联：Fn → 录音 → 转录 → 注入 |

### Phase 2: 体验优化 (后续)

- 自定义触发键（不仅限于 Fn）
- 开机自启 (`SMAppService`)
- 录音历史记录
- 更多语言支持
- 统计面板（使用时长、API 费用估算）

---

## 9. 外部依赖

**零第三方依赖**。全部使用 Apple 系统框架：

- `AppKit` — UI
- `AVFoundation` / `AVFAudio` — 音频录制
- `CoreGraphics` — CGEvent tap
- `Carbon` — TISInputSource 输入法切换
- `Foundation` — URLSessionWebSocketTask, JSONEncoder/Decoder, UserDefaults
- `ServiceManagement` — SMAppService (开机自启)

---

*文档版本: 1.0 | 日期: 2026-04-01 | 作者: Voiceink Team*
