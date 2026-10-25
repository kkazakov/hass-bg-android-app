import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecorderException implements Exception {
  RecorderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper around `record` that always produces 16 kHz mono PCM16 WAV,
/// which is what the gateway accepts.
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> ensurePermission() => _recorder.hasPermission();

  Future<String> start() async {
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/ptt_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    return path;
  }

  Future<String?> stop() => _recorder.stop();

  void dispose() {
    _recorder.dispose();
  }
}
