# SessionCoordinator 子模块执行计划（串行）

日期：2026-04-01
范围：仅 `SessionCoordinator` 子模块及其最小依赖改动

## 1. 目标

实现一个核心编排器 `SessionCoordinator`，完成单次会话主链路：

`Fn 按下 -> 录音+流式发送 -> Fn 松开 -> commit + response.create -> 等待最终结果 -> 文本注入 -> 回到 idle`

## 2. 边界（本轮仅做）

- 新增：`Sources/Voiceink/App/SessionCoordinator.swift`
- 小幅改动（仅必要）：
  - `RealtimeProtocol.swift`：补一个 `response.done` 回调
  - `RealtimeAPIClient.swift`：在收到 `response.done` 时触发回调
  - `AppDelegate.swift`：确保 Coordinator 被正确实例化并连接到 `FnKeyMonitor`

不在本轮做：
- UI 视觉微调
- 额外快捷键
- 历史记录

## 3. 状态机

- `idle`
- `connecting`
- `recording`
- `waitingForResult`
- `injecting`

约束：
- 最小按住时长 300ms，低于此值视为误触，直接取消。
- 等待结果超时 15s，超时报错并回到 idle。

## 4. 事件编排

### 4.1 Fn 按下

1. 若无 API Key：显示设置窗口，结束。
2. 显示胶囊窗口进入 `recording`（先给用户即时反馈）。
3. 若 WebSocket 未连接：
   - 状态置 `connecting`
   - connect
   - 等待 `session.updated` 后再真正启动录音
4. 若已连接且 session ready：直接启动录音

### 4.2 录音进行中

- `AudioEngine` 回调：
  - RMS -> `CapsulePanel.updateWaveformLevel`
  - Base64 PCM -> `RealtimeAPIClient.sendAudioFrame`
- 文本增量：`response.text.delta` -> `CapsulePanel.updateTranscript`

### 4.3 Fn 松开

1. 若按住 < 300ms：
   - 停录
   - 隐藏胶囊
   - 回到 `idle`
2. 否则：
   - 停录
   - 状态置 `waitingForResult`
   - 胶囊切到 waiting
   - 发送 `input_audio_buffer.commit`
   - 发送 `response.create`
   - 开始 15s 超时计时

### 4.4 收到服务端完成事件

- `response.text.done`：缓存最终文本
- `response.done`：
  - 取消超时计时
  - 若最终文本非空：执行 `TextInjector.inject`
  - 隐藏胶囊
  - 回到 `idle`

## 5. 错误处理

- 缺少 API Key：打开 Settings
- WebSocket 错误：胶囊显示错误 2s 后隐藏，回 idle
- 超时：胶囊显示“请求超时”，回 idle

## 6. 验收标准（本子模块）

- 能从 `Fn` 按下进入录音，并看到波形
- 松开后能触发 commit/create
- 收到 done 后能自动注入文本
- 误触 (<300ms) 不发起注入
- 超时可自动恢复 idle
