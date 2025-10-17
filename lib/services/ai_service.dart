import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AiService {
  // --- IMPORTANT ---
  // 為了安全起見，API 金鑰不應直接寫在程式碼中。
  // 請將 'Sai_GEMINI_API_KEY' 替換成您自己的 Gemini API 金鑰。
  static final String? _apiKey = dotenv.env['Sai_GEMINI_API_KEY'];

  GenerativeModel? _model;

  AiService() {
    _initialize();
  }

  void _initialize() {
    if (_apiKey == null) {
      debugPrint('請在 AiService 中設定您的 Gemini API 金鑰！');
      return;
    }
    // 選用模型：
    // 1. gemini-2.5-flash
    // 2. gemini-2.5-pro
    // flash: 10 次/分鐘, pro: 2 次/分鐘
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey!);
  }

  /// 針對指定公司名稱進行企業分析
  Future<String?> analyzeCompany(String companyName) async {
    if (_model == null) {
      debugPrint('Gemini 模型尚未初始化，請檢查 API 金鑰。');
      return '模型尚未初始化。';
    }

    // 檢查公司名稱是否為空
    if (companyName.trim().isEmpty) {
      return '公司名稱為空，無法分析。';
    }

    try {
      // 建立一個 Prompt，要求 Gemini 針對這家公司進行簡短分析
      final prompt =
          '請針對「$companyName」這間公司，提供一段約 100-150 字的簡要分析報告，包含其主要業務、市場定位和潛在的合作機會。';

      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      return response.text;
    } on GenerativeAIException catch (e) {
      debugPrint('Gemini API 呼叫失敗: $e');
      // 回傳錯誤訊息，讓 UI 層可以判斷是否要重試
      return e.message;
    } catch (e) {
      debugPrint('Gemini API 呼叫失敗: $e');
      return '分析失敗，請查看終端機錯誤訊息。';
    }
  }
}
