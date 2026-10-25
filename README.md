# BG Voice — Android push-to-talk client

Minimal Flutter Android app for [`hass-bulgarian-commands`](../hass-bulgarian-commands):
hold the microphone, speak Bulgarian, release — the gateway transcribes, matches
the command and acts on Home Assistant. Text replies are shown; commands marked
`speak: true` also play the spoken answer.

* **Targets Android 15** (`targetSdk 35`, `compileSdk 36`), runs on Android 8.0+
  (`minSdk 26`). Set `minSdk = 35` in `android/app/build.gradle.kts` if you want
  Android 15+ only.
* No cloud, no analytics, no background listening.

## Requirements

1. A running gateway reachable from the phone, e.g.
   `http://100.101.102.21:8080` (tailnet) or `http://192.168.1.10:8080` (LAN).
   The gateway must listen on an interface the phone can reach:

   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8080   # in hass-bulgarian-commands
   ```

2. The phone and the gateway on the same network/VPN.
3. Android 8.0 or newer.

## Build and install

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk   # Java 17–21; 27 is too new for this AGP
export PATH=$JAVA_HOME/bin:$PATH

flutter pub get
flutter test                 # 8 tests, no device needed
flutter build apk --release  # 52 MB, build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
# debug build (167 MB, faster iteration): flutter build apk --debug
```

Flutter stable 3.47.x is expected (Dart 3.13).

## Using it

1. **＋** (top right) → enter the gateway URL (`host:port` is accepted; `http://`
   is added automatically). The name defaults to the host and can be changed.
2. The gateways appear as chips at the top. Tap one to switch; the selection is
   stored as default and restored on the next launch.
3. **Hold the microphone**, speak, **release**. The command is uploaded, the reply
   appears below (transcript, intent, score, latency).
4. **Long-press a chip** → *Редактирай* (URL/name) or *Изтрий* (with confirmation).

The app records 16 kHz mono PCM16 WAV, which the gateway accepts. Temporary files
are deleted after sending. If you release too quickly (< 450 ms) nothing is sent.

## How it talks to the gateway

```
POST {gateway}/v1/voice     multipart field "audio" (WAV)
→ { kind, speak, text, transcript, audio_url, matched, timings }
GET  {gateway}/v1/audio/... reply WAV (played when speak == true)
```

No API key is sent (the gateway has none configured by default). If you set
`BGV_API_KEY` on the gateway, this client will get 401 until header support is
added — keep the gateway on a trusted network until then.

Cleartext HTTP is enabled (`android:usesCleartextTraffic="true"`) because home
gateways usually run plain HTTP on the LAN/tailnet.

## Project layout

```
lib/
  main.dart       UI: gateway chips, hold-to-talk button, dialogs
  models.dart     Gateway + CommandResult, URL normalisation
  store.dart      SharedPreferences persistence (gateways + active id)
  api.dart        multipart upload, error mapping, audio URL
  recorder.dart   record wrapper (16 kHz mono WAV)
test/             model/store/widget tests (8)
android/          minSdk 26, targetSdk 35, RECORD_AUDIO + INTERNET
```

## Known limits

- Push-to-talk only; no wake word, no background listening.
- One gateway per request (no per-command instance routing yet).
- No API key / custom CA support yet; HTTP only.
- Debug APK is ~167 MB (Flutter debug engine); a release build is much smaller
  but needs signing.
