# Changelog

All notable changes to Voiceink will be documented in this file.

## [v0.1.1] - 2026-04-02

### Fixed

- **Transcription accuracy: model no longer "answers" questions instead of transcribing**
  - Previously, the Qwen-Omni-Realtime model would sometimes interpret spoken input as a question or command and reply conversationally rather than transcribing verbatim.
  - Switched from `response.create`-based transcription to DashScope's dedicated `input_audio_transcription` feature (`gummy-realtime-v1` model), which is purpose-built for pure STT.
  - `turn_detection` is now set to `null` (manual mode) — no auto-VAD triggering unwanted responses.
  - Fn key release now only commits the audio buffer; no `response.create` is sent.
  - Listens for `conversation.item.input_audio_transcription.completed` event for the final transcript.
  - Removed all `response.text.delta` / `response.done` handling (no longer needed).

- **Transcription prompt hardened to prevent conversational replies** *(included in this release)*
  - Changed session modalities from `[text, audio]` to `[text]` only — disables voice reply mode entirely.
  - Rewrote system instructions to explicitly forbid answering questions or following commands; model is instructed to output verbatim transcription only.

### Changed

- `RealtimeAPIClient`: removed `response.create` call on commit; simplified event handling loop.
- `RealtimeModels`: added `InputAudioTranscriptionConfig` and `TranscriptionCompletedEvent` Codable models.
- `SessionCoordinator`: updated to handle `transcriptionCompleted` delegate callback instead of `responseTextDone`.

---

## [v0.1.0] - 2026-04-01

### Added

- Initial release of Voiceink — macOS menu bar app for voice-to-text via Fn key.
- Fn key hold-to-record with 300 ms anti-bounce and 15 s response timeout.
- Audio streaming via WebSocket to Alibaba DashScope Qwen-Omni-Realtime API (16 kHz PCM, Base64).
- Floating capsule HUD with 5-bar waveform animation and live transcript display.
- Text injection via clipboard + simulated Cmd+V, with CJK input source switching.
- Two-step onboarding wizard (Accessibility permission + API key configuration).
- Persistent bilingual permission guide window with polling auto-close.
- Settings window: API key, model selection, connection test.
- Menu bar icon with language selector and quick access to settings.
- `make build / run / install / clean / qa / reset-permissions` build targets.
