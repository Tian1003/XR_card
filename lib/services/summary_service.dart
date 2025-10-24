// lib/services/summary_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class SummaryService {
  final GenerativeModel? _model;

  SummaryService()
      : _model = (dotenv.env['Sai_GEMINI_API_KEY'] != null)
            ? GenerativeModel(
                model: 'gemini-2.5-flash',
                apiKey: dotenv.env['Sai_GEMINI_API_KEY']!,
              )
            : null;

  /// 針對逐字稿產出「很短」的摘要（2~3 句 / 或 3~5 個重點，繁中）
  Future<String?> summarize(String transcript) async {
    if (_model == null) {
      debugPrint('SummaryService: API key 未設定，略過摘要');
      return null;
    }
    if (transcript.trim().isEmpty) return null;

    final prompt = [
      Content.text(
        '你是會議逐字稿的精簡助理。請用繁體中文，幫我把下面對話整理成非常精簡的摘要：\n'
        '- 2~3 句話重點敘述（避免流水帳，避免太長）\n'
        '- 只保留關鍵決策、下一步、時間/數字\n'
        '- 不要加入沒有出現的內容\n\n'
        '=== 逐字稿開始 ===\n$transcript\n=== 逐字稿結束 ===',
      )
    ];

    final res = await _model!.generateContent(prompt);
    return res.text?.trim();
  }
}
