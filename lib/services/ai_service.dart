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

  /// [新增] 根據多方資訊生成「開場白」(供「話題建議」按鈕使用)
  ///
  /// 整合企業細節、時事新聞和上次對話摘要，產出開放性話題
  Future<List<String>> generateSuggestions(
    String? companyName,
    String? jobTitle, // [!] 新增職稱參數
    String? companyInfo,
    List<String> newsSnippets,
    String? lastSummary,
  ) async {
    if (_model == null) return ['AI 模型未初始化'];

    String prompt =
        '''
    您是一位專業的商務社交助理。請根據以下關於「${companyName ?? '這位專業人士'}」的背景資訊，
    為我生成 3 個簡短且自然的、適合用來開啟對話的「開放性問題」或「開場白」。
    我希望這些問題能引導對方分享更多資訊，而不是簡單的「是/否」回答。

    背景資訊：
    1.  **企業細節分析** (您對他們公司的了解)：
        ${companyInfo ?? "無"}
    2.  **對方職業/職稱**：
        ${jobTitle ?? "無"}
    3.  **相關時事/新聞摘要** (最近的產業動態)：
        ${newsSnippets.isNotEmpty ? newsSnippets.join("； ") : "無"}
    4.  **上次對話回顧** (上次聊到的重點)：
        ${lastSummary ?? "無"}

    請針對上述資訊，盡可能生成 3 個相關的開場白 (例如，一個關於公司、一個關於職業、一個關於時事)。
    如果某個面向的資訊不足，您可以生成一個較通用的問題，或專注於有資訊的面向。

    範例：
    - (基於企業細節) "我了解到貴公司在教育領域耕耘，可以多分享一些你們具體的服務模式嗎？"
    - (基於職業) "您作為「${jobTitle ?? '專業人士'}」，最近在[相關領域]上是否有觀察到什麼特別的趨勢？"
    - (基於時事) "最近看到關於[某某]的新聞，這對你們的產業是否有帶來什麼新的挑戰或機遇？"
    - (基於對話回顧) "上次我們聊到[某某]專案，不曉得後續的進展還順利嗎？"

    請直接回傳 3 個以換行符號分隔的建議問題 (不需要包含 '1.' 或 '- ' 這樣的前綴)。
    ''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);

      // 清理 AI 回應
      return response.text
              ?.split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map((s) => s.replaceAll(RegExp(r'^[0-9\.\-\*•]\s*'), ''))
              .where((s) => s.isNotEmpty)
              .toList() ??
          ['請問您最近關注哪些產業動態嗎？'];
    } on GenerativeAIException catch (e) {
      debugPrint('Gemini API 呼叫失敗 (generateSuggestions): $e');
      if (e.message.contains('UNAVAILABLE')) {
        return ['模型目前忙碌中，請稍後再試'];
      }
      return ['生成建議時發生錯誤'];
    } catch (e) {
      debugPrint('Gemini API 呼叫失敗 (generateSuggestions): $e');
      return ['生成建議時發生錯誤，請查看終端機'];
    }
  }
}
