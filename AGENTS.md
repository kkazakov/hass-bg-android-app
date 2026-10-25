# AGENTS.md — hass-bulgarian-voice

Guidelines for agentic coding agents (and humans) working in this repo.

## Project Overview

A small Flutter Android app (push-to-talk) for `hass-bulgarian-commands`.
Hold the mic → 16 kHz mono WAV → `POST /v1/voice` → show text reply, play the
reply WAV when `speak` is true. No cloud, no wake word, no background service.

* `minSdk 26`, `targetSdk 35`, `compileSdk 36`
* Flutter stable 3.47.x / Dart 3.13

## Directory Structure

```
lib/
  main.dart      HomePage (gateway chips, mic button), GatewayDialog, result card
  models.dart    Gateway (normalizeUrl/defaultName), CommandResult.fromJson
  store.dart     SharedPreferences: gateways_v1 + active_gateway_v1
  api.dart       GatewayClient (multipart), ApiException, audio URL resolution
  recorder.dart  VoiceRecorder wrapper around `record` (16 kHz mono WAV)
test/            model, store and widget tests
android/         manifest permissions, cleartext HTTP, SDK levels
```

## Setup

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH=$JAVA_HOME/bin:$PATH
flutter pub get
flutter test
flutter build apk --debug
```

## Conventions

- Keep it single-screen and dependency-light; this is a remote control, not a platform.
- UI strings are Bulgarian; technical terms (URL, Gateway) stay English.
- All network calls go through `GatewayClient`; all persistence through `GatewayStore`.
- Always delete the temporary WAV after send/cancel (`_deleteFile`).
- Do not add background audio, wake word or always-on microphone without an explicit request.

## Gotchas

- **Hold-to-talk race:** `onTapDown` starts an async permission + recorder start.
  `_pressActive`, `_cancelled` and `_pressedAt` handle release/cancel during that
  window. Do not remove them; a fast tap otherwise leaves the recorder running.
- **`onTapCancel` cancels the recording** (finger dragged off the button). That is
  intentional; sending on cancel caused accidental commands.
- **400 ms minimum**: shorter recordings are discarded (`_tooShort`).
- **Cleartext HTTP is enabled on purpose.** Home gateways are plain HTTP; HTTPS
  with a self-signed cert would need a network security config.
- **No API key support.** Do not point this at an internet-exposed gateway.
- **Java 27 breaks the current AGP**; build with Java 21.
- Widget tests must set `SharedPreferences.setMockInitialValues({})` in `setUp`.
