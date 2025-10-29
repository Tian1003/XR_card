import 'dart:io' show File;            
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

class SpeechResult {
  final String text;
  final int durationSec;
  const SpeechResult({required this.text, required this.durationSec});
}

class SpeechToTextService {
  final Whisper _whisper = Whisper(
    model: WhisperModel.base, // 先 base，跑穩再升級
    downloadHost: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
  );


  Future<SpeechResult> transcribeFile(String audioPath, {int durationSec = 0}) async {
    final f = File(audioPath);
    if (!await f.exists() || await f.length() < 44) {
      throw Exception('Audio file not ready or invalid: $audioPath');
    }

    final resp = await _whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: audioPath,
        isTranslate: false,
        isNoTimestamps: true,
        splitOnWord: false,
        language: 'zh',
      ),
    );

    // 兼容不同回傳格式，盡量取出純文字
    String text = '';
    try {
      final t = (resp as dynamic).text as String?;
      if (t != null && t.trim().isNotEmpty) text = t;
    } catch (_) {}
    if (text.isEmpty) {
      try {
        final segs = (resp as dynamic).segments as List?;
        if (segs != null) {
          text = segs
              .map((s) => (s as dynamic).text as String? ?? '')
              .where((s) => s.trim().isNotEmpty)
              .join(' ');
        }
      } catch (_) {}
    }
    if (text.isEmpty) text = resp.toString();

    return SpeechResult(text: text.trim(), durationSec: durationSec);
  }

  Future<String?> version() => _whisper.getVersion();
}
