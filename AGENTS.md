# AGENTS.md — hass-bulgarian-voice

Guidelines for agentic coding agents (and humans) working in this repository.
Refer to this project as **HASS Voice**.

## Project overview

**HASS Voice** is a small Flutter Android app (push-to-talk) for
[`hass-bg-gateway`](https://github.com/kkazakov/hass-bg-gateway). Hold the mic,
speak Bulgarian, release: the app records 16 kHz mono WAV, uploads it to
`POST /v1/voice`, shows the text reply, and plays the returned audio when the
gateway says `speak: true`.

No cloud service in the app, no wake word, no background recording. The gateway
does ASR/matching/HA; the app is a remote control with local gateway bookmarks.
You implement, test and verify changes here. `README.md` is the user-facing
description of the app; this file governs how it is changed.

- Flutter stable **3.47.x** / Dart 3.13
- `minSdk 26`, `targetSdk 35`, `compileSdk 36`
- Gateway default port is **8125**; one gateway = one Home Assistant
- Optional per-gateway `X-API-Key` (`Gateway.secret`); empty means no auth header

## Commands

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH=$JAVA_HOME/bin:$PATH

git switch -c <type>/<short-name> main    # every change starts on a branch
flutter pub get
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test                              # 19 tests, no device/gateway needed
flutter test test/api_test.dart           # single file
flutter test --plain-name 'secret'        # single test by name
flutter build apk --release               # ~50 MB
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Debug build is ~167 MB. Do not build with Java 27 — the current AGP rejects it.

## Git workflow

- `main` is integration only. **Never commit directly to `main`.**
- Start every change from `main` on a branch: `feat/…`, `fix/…`, `docs/…` or
  `chore/…`. Commit and push branches to `origin` freely.
- Before starting, check whether another agent is already working in this
  checkout: `git status --short --branch`, `git worktree list`, and running
  `flutter`, `adb` or Gradle processes. Uncommitted changes you did not make, a
  second worktree or a busy build mean another agent is active.
- If one is, **do not share its working tree**. Fetch first (`git fetch
  origin`), then create a separate folder with `git worktree add
  ../hass-voice-<task> -b <type>/<short-name> main` and do all work there.
  Remove the worktree once its branch is pushed.
- Never `git stash`, `reset`, `clean` or switch branches in a tree you do not
  own; ask the user when it is unclear whether a tree is in use.
- **Never open or merge a pull request into `main` unless the user explicitly
  asks for it.** No automatic merges. This applies to documentation and to this
  file too.

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
android/                  manifest, SDK levels, adaptive launcher icons
docs/                     screenshots and launcher-icon sources (docs/branding)
```

## Conventions

- Keep the app single-screen and dependency-light; it is a remote control, not a
  platform.
- Bulgarian UI strings; technical terms (`URL`, `Gateway`) stay English.
- The launcher label is `HASS Voice`. Keep the applicationId
  `bg.krasi.hass_bulgarian_voice` and the Dart package `hass_bulgarian_voice`:
  changing them breaks saved gateways/imports.
- Launcher art is source-controlled in `docs/branding/` as self-contained SVGs;
  `docs/branding/render-icons.sh` regenerates the `mipmap-*` PNGs with
  `rsvg-convert`. Keep the `ic_launcher_monochrome` layer for themed icons.
- All HTTP goes through `GatewayClient`; all persistence through `GatewayStore`.
- Delete the temporary WAV after send or cancel (`_deleteFile`).
- The gateway secret is optional and per entry; keyless gateways must keep
  working. If auth handling changes, update README, tests and the gateway docs.
- If the UI changes materially, regenerate `docs/screenshot.png` (the current
  screenshots are cropped above the gateway-URL footer so they do not go stale
  when the default port changes).
- Gateway responses are untrusted input: parse them defensively in
  `CommandResult.fromJson` (every field needs a fallback) and surface failures
  as `ApiException` with a Bulgarian message. A raw `TypeError` must never reach
  the UI.

## Definition of done

1. The requested behaviour works, and a test covers it — or the change is
   explicitly test-free (docs, config) and that is stated.
2. `flutter analyze`, the `dart format` check and `flutter test` pass. Run the
   touched test file while iterating, the whole suite before finishing.
3. Visual changes regenerate `docs/screenshot.png` in the same branch.
4. `README.md` and this file are updated when behaviour, commands or the gateway
   contract change.
5. The branch is pushed to `origin`. Do not report a task complete while a test
   fails or verification is stale.

For a visible change, install and exercise the build on a device
(`adb install -r …`), leave the app running, and end the response with the exact
artifact path. Never report "done" against an APK you did not install and check;
non-visual changes need no device install.

## Boundaries

- NEVER commit a keystore, `key.properties`, `local.properties`, `.env`, an API
  key, an HA token or a real gateway secret. Do not weaken `.gitignore`.
- NEVER commit directly to `main`; every change starts on a branch and is
  pushed there.
- NEVER open, merge or fast-forward a pull request without an explicit user
  request.
- NEVER change the applicationId `bg.krasi.hass_bulgarian_voice`, the Dart
  package `hass_bulgarian_voice` or the launcher label `HASS Voice`: saved
  gateways, imports and preferences are keyed to them.
- NEVER send an empty `X-API-Key`, and never hand a keyed audio URL to
  `audioplayers`; keyless gateways must keep working and the secret must not
  leak.
- NEVER add background audio, a wake word or an always-on microphone without an
  explicit request.
- NEVER bump Flutter/Dart, `minSdk`, `targetSdk` or `compileSdk` silently; they
  change which devices can install and run the app.
- DO NOT change the gateway request/response contract without updating the
  README, tests and the gateway docs.
- DO NOT edit the generated `mipmap-*` PNGs by hand; regenerate them with
  `docs/branding/render-icons.sh`.
- NEVER force-push or rewrite published history.
- REQUIRE HUMAN CONFIRMATION for: replacing the signing key, uploading to a
  store, deleting saved gateway data, major dependency upgrades, and changing
  release or signing configuration.

## Gotchas

- **Hold-to-talk race:** `onTapDown` starts an async permission + recorder start.
  `_pressActive`, `_cancelled` and `_pressedAt` handle release/cancel during that
  window. Do not remove them; a fast tap otherwise leaves the recorder running.
- **`onTapCancel` cancels the recording** (finger dragged off). Intentional;
  sending on cancel caused accidental commands.
- **The mic must not move when feedback appears.** It sits in a fixed 168 dp
  slot at 42% of the free height; status, errors and the result card live in a
  separate scrollable region below. Do not put them back in one centred column
  with the button: clearing the result on the next press would move the button
  under the finger and turn the hold into an `onTapCancel`. The active gateway
  title is drawn inside the existing gap above the mic for the same reason; it
  must not add height to the column.
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
- **Launcher icon scales differ on purpose.** The adaptive foreground and
  monochrome SVGs draw the bubble at 0.84× so it sits at ~73% of the 72dp
  viewport; the legacy/round bitmaps use 1.21× because the whole 48–192px image
  is visible. Do not copy one scale to the other.

## Testing

Use the exact invocations from Commands. Decide what to test while planning the
change, not after it: new behaviour ships with a test in the same branch, and a
bug fix gets a regression test that fails without the fix.

The tests use fake prefs and `MockClient`; they never touch the microphone, a
real network or a gateway. They cover URL normalisation, secret parsing and
round-trips, `X-API-Key` presence/absence on voice and audio calls, cross-origin
audio not leaking the secret, 401 error mapping, the empty state, the active
gateway title, and add/edit/delete/secret widget flows.

## Security

- The HA token stays on the gateway. The phone stores gateway URLs and optional
  gateway secrets in app-private `SharedPreferences` (plaintext, not
  hardware-backed encryption). Android Auto Backup may include them.
- Audio goes only to the configured gateway. The gateway may forward query text
  to Google when its TTS provider is `gtts`; `piper` keeps it local.
- Cleartext HTTP is allowed by design; use LAN/Tailscale/VPN, not open Wi-Fi.
- What must never be committed is listed under Boundaries.
