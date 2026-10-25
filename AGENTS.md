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
- Optional per-gateway `X-API-Key` (`Gateway.secret`); empty means no auth header

## Architecture

```
HomePage
  ├─ GatewayStore (SharedPreferences)     gateways_v1, active_gateway_v1
  ├─ VoiceRecorder (record)               16 kHz mono PCM16 WAV
  ├─ GatewayClient (http)                 POST /v1/voice + GET reply audio,
  │     │                                 optional X-API-Key per gateway
  │     └─ CommandResult (models.dart)    kind/transcript/text/audio_url/timings
  └─ AudioPlayer (audioplayers)           BytesSource when speak == true
```

State is plain `setState` in `_HomePageState`; there is no state-management
package. The active gateway is selected by id and persisted after every switch,
add, edit or delete.

### Gateway contract

Request: `multipart/form-data`, field `audio` (WAV), plus `X-API-Key` when the
saved gateway has a secret.
Response fields used: `kind`, `speak`, `text`, `transcript`, `audio_url`,
`matched.intent`, `matched.score`, `timings.total_ms`, `reason`.

- `audio_url` is relative (`/v1/audio/<id>.mp3|wav`) and resolved against the
  gateway base URL.
- MP3 (gTTS) and WAV (Piper) are both supported by `audioplayers`.
- The gateway has no `instance` field/parameter anymore; a saved gateway maps to
  exactly one HA. Multiple homes = multiple saved gateways.
- Commands live in the gateway's catalogue (`commands.yaml` or
  `BGV_COMMANDS_FILE`), not in the app.
- The app sends `X-API-Key` only when the saved gateway has a non-empty
  `secret`; empty means no header and keyless gateways keep working.
- The gateway applies `X-API-Key` to **every** `/v1` route, including
  `/v1/audio/...`, so reply audio must be downloaded through `GatewayClient`,
  not handed to `audioplayers` as a bare URL.

## Directory structure

```
lib/
  main.dart      HomePage, gateway chip strip, mic button, result card,
                 GatewayDialog, Bulgarian UI strings
  models.dart    Gateway (normalizeUrl/defaultName/secret), CommandResult
  store.dart     GatewayStore: SharedPreferences read/write
  api.dart       GatewayClient: multipart, X-API-Key, audio download, errors
  recorder.dart  VoiceRecorder: `record` wrapper (16 kHz mono WAV)
test/
  models_test.dart       URL normalisation, secret parsing, store round-trip
  api_test.dart          X-API-Key presence/absence, audio download, 401
  home_widget_test.dart  add/edit/delete and secret widget flows
android/                  manifest, SDK levels, launcher
docs/                     screenshots used by README
```

## Setup and build

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH=$JAVA_HOME/bin:$PATH

flutter pub get
flutter analyze
flutter test                  # 18 tests, no device/gateway needed
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
- The gateway secret is optional and per entry. Never send an empty
  `X-API-Key`; keyless gateways must keep working. If auth handling changes,
  update README, tests and the gateway docs.
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
- **Saved URLs and secrets are not migrated.** Changing the default port
  (8080 → 8125) does not rewrite existing gateway entries; the user edits them
  with long-press. Entries stored before secret support load with an empty one.
- **Cleartext HTTP is enabled on purpose** (`usesCleartextTraffic="true"`); home
  gateways are plain HTTP. No custom CA/pinning support.
- **`audioplayers` cannot send headers.** `UrlSource` would hit a keyed gateway
  with a 401, so `_playReply` downloads through `GatewayClient.fetchAudio` and
  plays `BytesSource`. Keep it that way for keyed audio.
- **Java 27 breaks the AGP**; build with Java 21.
- **Release signing** uses the template's debug keystore; it is sideload-only.
- **Widget tests** must call `SharedPreferences.setMockInitialValues({})` in
  `setUp`.
- **Playback errors are swallowed** in `_playReply`. If audio silently fails,
  check media volume, the saved secret and the gateway's `/v1/audio/...` URL
  before changing UI logic.
- The package id is `bg.krasi.hass_bulgarian_voice`; changing it breaks existing
  stored preferences.

## Testing

```bash
flutter analyze
flutter test
```

The tests use fake prefs and `MockClient`; they never touch the microphone, a
real network or a gateway. They cover URL normalisation, secret parsing and
round-trips, `X-API-Key` presence/absence on voice and audio calls, cross-origin
audio not leaking the secret, 401 error mapping, the empty state, and
add/edit/delete/secret widget flows.

## Security

- The HA token stays on the gateway. The phone stores gateway URLs and optional
  gateway secrets in app-private `SharedPreferences` (plaintext, not
  hardware-backed encryption). Android Auto Backup may include them.
- Audio goes only to the configured gateway. The gateway may forward query text
  to Google when its TTS provider is `gtts`; `piper` keeps it local.
- Cleartext HTTP is allowed by design; use LAN/Tailscale/VPN, not open Wi-Fi.
- Never commit a keystore, API key or HA token.
