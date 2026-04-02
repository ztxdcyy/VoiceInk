# TODO

Project-level backlog for Voiceink. Items are roughly prioritized top-to-bottom within each section.

---

## 🔴 High Priority

- [ ] **End-to-end runtime validation** — Execute `QA_CHECKLIST.md` fully: Fn hold → speak → release → text injected in real apps (Safari, Notes, Terminal, WeChat).
- [ ] **Fn key suppression reliability** — Validate that the Emoji picker is reliably suppressed across macOS versions; document any edge cases.

---

## 🟡 Medium Priority

- [ ] **Local inference support** — Run transcription entirely on-device using a local Whisper or similar model (no API key required, works offline). Candidate: `whisper.cpp` via Swift subprocess or embedded framework.
- [ ] **Error UX** — Show user-facing error messages in the capsule HUD for common failures (no internet, invalid API key, timeout).
- [ ] **Auto-launch at login** — Add a toggle in Settings to enable/disable launch at login via `ServiceManagement`.
- [ ] **Configurable hotkey** — Allow users to choose a hotkey other than Fn (e.g., Right Option, Caps Lock).

---

## 🟢 Nice to Have

- [ ] **Multiple API provider support** — Abstract the WebSocket client to support OpenAI Realtime API or other compatible endpoints in addition to DashScope.
- [ ] **Transcript history** — Keep a session log of recent transcriptions accessible from the menu bar.
- [ ] **Custom vocabulary / prompt** — Let users supply a custom transcription hint (e.g., domain-specific terms) via Settings.
- [ ] **Waveform polish** — Smoother bar animation, idle breathing effect when connected but not recording.
- [ ] **Notarization & distribution** — Apple notarization + GitHub Releases binary distribution.

---

## ✅ Done (reference)

- [x] Project scaffolding, menu bar shell, settings UI
- [x] Fn key monitoring (CGEvent tap)
- [x] Audio engine (16 kHz PCM, RMS, Base64)
- [x] WebSocket client (DashScope Qwen-Omni-Realtime)
- [x] Capsule HUD (waveform + live transcript)
- [x] Text injection (clipboard + Cmd+V + CJK handling)
- [x] Two-step onboarding wizard
- [x] Fix: switch to `input_audio_transcription` for pure STT (v0.1.1)
- [x] Fix: harden transcription prompt to prevent conversational replies (v0.1.1)
