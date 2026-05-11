# Draft: Voice Pipeline Rework

## Requirements (confirmed)
- Apple Speech Recognition (SFSpeechRecognizer via iPhone relay) as PRIMARY voice path
- Zhipu ASR as FALLBACK (when iPhone not available)
- Fix HTTP 400 / error code 1214 from Zhipu ASR
- User quote: "我能不能直接用苹果自己的speech recognition"

## Technical Decisions
- Apple Speech via iPhone relay (not on-watch SFSpeechRecognizer) — already implemented in IOSpeechRelayTranscriber
- Swap primary/fallback order in WatchDrawerAndChrome.swift
- Fix Zhipu ASR 1214 error as secondary priority
- Improve error display on watch (truncated HTTP errors are unhelpful)

## Research Findings
- Error code 1214 = `${field} 参数非法。请检查文档。` (Zhipu API docs)
- Zhipu ASR supports only `.wav` and `.mp3`, duration ≤ 30s, size ≤ 25 MB
- Watch records PCM WAV 16kHz/16-bit/mono — should be valid but might have subtle issues
- IOSpeechRelayTranscriber uses SFSpeechRecognizer with zh-CN locale — already works
- Server auth path (BolaAuthService) blocks ASR because hostIsZhipuOpenPlatform check returns false
- Server has ASR proxy endpoint at /ai/v1/audio/transcriptions but code doesn't use it
- Current flow: cloud ASR first → iPhone relay second (should be reversed)

## Open Questions
- None (all clarified by user)

## Scope Boundaries
- INCLUDE: Swap primary/fallback order, fix 1214, improve error display, enable server ASR proxy
- EXCLUDE: On-watch SFSpeechRecognizer (unreliable), new UI design, other features
