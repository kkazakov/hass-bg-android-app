# AGENTS.md — hass-bulgarian-voice

Guidelines for agentic coding agents (and humans) working in this repository.

## Project overview

A small Flutter Android app (push-to-talk) for
[`hass-bg-gateway`](https://github.com/kkazakov/hass-bg-gateway). Hold the mic,
speak Bulgarian, release: the app records 16 kHz mono WAV, uploads it to
`POST /v1/voice`, shows the text reply, and plays the returned audio when the
gateway says `speak: true`.

No cloud service in the app, no wake word, no background recording. The gateway
does ASR/matching/HA; the app is a remote control with local gateway bookmarks.

- Flutter stable **3.47.x** / Dart 3.13
- `minSdk 26`, `targetSdk 35`, `compileSdk 36`
- Gateway default port is **8125**; one gateway = one Home Assistant
- The app does **not** send `X-API-Key`; the gateway's `BGV_API_KEY` must be empty

## Architecture

```
HomePage
  ├─ GatewayStore (SharedPreferences)     gateways_v1, active_gateway_v1
  ├─ VoiceRecorder (record)               16 kHz mono PCM16 WAV
  ├─ GatewayClient (http)                 multipart POST /v1/voice
  │     └─ CommandResult (models.dart)    kind/transcript/text/audio_url/timings
  └─ AudioPlayer (audioplayers)           plays audio_url when speak == true
```

State is plain `setState` in `_HomePageState`; there is no state-management
package. The active gateway is selected by id and persisted after every switch,
add, edit or delete.

### Gateway contract

Request: `multipart/form-data`, field `audio` (WAV).
Response fields used: `kind`, `speak`, `text`, `transcript`, `audio_url`,
`matched.intent`, `matched.score`, `timings.total_ms`, `reason`.

- `audio_url` is relative (`/v1/audio/<id>.mp3|wav`) and resolved against the
  gateway base URL.
- MP3 (gTTS) and WAV (Piper) are both supported by `audioplayers`.
- The gateway has no `instance` field/parameter anymore; a saved gateway maps to
  exactly one HA. Multiple homes = multiple saved gateways.
- Commands live in the gateway's catalogue (`commands.yaml` or
  `BGV_COMMANDS_FILE`), not in the app.
- The app does not send `X-API-Key`; a keyed gateway returns 401.

## Directory structure

```
lib/
  main.dart      HomePage, gateway chip strip, mic button, result card,
                 GatewayDialog, Bulgarian UI strings
  models.dart    Gateway (normalizeUrl/defaultName), CommandResult.fromJson
  store.dart     GatewayStore: SharedPreferences read/write
  api.dart       GatewayClient: multipart, timeouts, error mapping, audio URI
  recorder.dart  VoiceRecorder: `record` wrapper (16 kHz mono WAV)
test/
  models_test.dart       URL normalisation, result parsing, store round-trip
  home_widget_test.dart  add/long-press/delete widget flows
android/                  manifest, SDK levels, launcher
docs/                     screenshots used by README
```

## Setup and build

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH=$JAVA_HOME/bin:$PATH

flutter pub get
flutter analyze
flutter test                  # 8 tests, no device/gateway needed
flutter build apk --release   # ~50 MB
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Debug build is ~167 MB. Do not build with Java 27 — the current AGP rejects it.

## Conventions

- Keep the app single-screen and dependency-light; it is a remote control, not a
  platform.
- Bulgarian UI strings; technical terms (`URL`, `Gateway`) stay English.
- All HTTP goes through `GatewayClient`; all persistence through `GatewayStore`.
- Delete the temporary WAV after send or cancel (`_deleteFile`).
- Do not add background audio, wake word or always-on microphone without an
  explicit request.
- If you add `X-API-Key` support, update README, tests and the gateway docs; do
  not silently require a key.
- If the UI changes materially, regenerate `docs/screenshot.png` (the current
  screenshots are cropped above the gateway-URL footer so they do not go stale
  when the default port changes).

## Gotchas

- **Hold-to-talk race:** `onTapDown` starts an async permission + recorder start.
  `_pressActive`, `_cancelled` and `_pressedAt` handle release/cancel during that
  window. Do not remove them; a fast tap otherwise leaves the recorder running.
- **`onTapCancel` cancels the recording** (finger dragged off). Intentional;
  sending on cancel caused accidental commands.
- **450 ms minimum**: shorter recordings are discarded (`_tooShort`).
- **Saved URLs are not migrated.** Changing the default port (8080 → 8125) does
  not rewrite existing gateway entries; the user edits them with long-press.
- **Cleartext HTTP is enabled on purpose** (`usesCleartextTraffic="true"`); home
  gateways are plain HTTP. No custom CA/pinning support.
- **No API key support.** Never point this build at a keyed/public gateway.
- **Java 27 breaks the AGP**; build with Java 21.
- **Release signing** uses the template's debug keystore; it is sideload-only.
- **Widget tests** must call `SharedPreferences.setMockInitialValues({})` in
  `setUp`.
- **Playback errors are swallowed** in `_send` (`.catchError((_) {})`). If audio
  silently fails, check media volume and the gateway's `/v1/audio/...` URL
  before changing UI logic.
- The package id is `bg.krasi.hass_bulgarian_voice`; changing it breaks existing
  stored preferences.

## Testing

```bash
flutter analyze
flutter test
```

The tests use fake prefs and never touch the microphone, network or a gateway.
They cover URL normalisation, response parsing, store round-trips, the empty
state, and add/long-press/delete gateway flows.

## Security

- The HA token stays on the gateway; only gateway URLs are stored on the phone.
- Audio goes only to the configured gateway. The gateway may forward query text
  to Google when its TTS provider is `gtts`; `piper` keeps it local.
- Cleartext HTTP is allowed by design; use LAN/Tailscale/VPN, not open Wi-Fi.
- Never commit a keystore, API key or HA token.
