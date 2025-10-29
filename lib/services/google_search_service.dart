// 檔案路徑: lib/services/google_search_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GoogleSearchService {
  static final String? _apiKey = dotenv.env['Sai_GOOGLE_SEARCH_API_KEY'];
  static final String? _cx = dotenv.env['GOOGLE_SEARCH_CX'];
  final http.Client _client;

  // 允許傳入 http.Client 以便於測試
  GoogleSearchService({http.Client? client})
    : _client = client ?? http.Client();

  /// 執行搜尋並回傳結果列表
  ///
  /// @param queries 要搜尋的關鍵字列表
  /// @return 一個 List，包含多個 Map，每個 Map 有 'title' 和 'snippet'
  Future<List<Map<String, String>>> search(List<String> queries) async {
    if (_apiKey == null || _cx == null) {
      debugPrint('Google Search API Key 或 CX 未設定在 .env 檔案中');
      return [];
    }

    // 將多個查詢合併成一個，用 "OR" 連接
    final String queryString = queries.map((q) => '"$q"').join(' OR ');

    // Google Custom Search API (CSE) 的端點
    final Uri uri = Uri.https('www.googleapis.com', '/customsearch/v1', {
      'key': _apiKey,
      'cx': _cx,
      'q': queryString,
      'num': '3', // 只取前 3 筆結果
    });

    debugPrint('Google Search 請求: $uri');

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] == null) {
          debugPrint('Google Search 未找到結果');
          return [];
        }

        final List<Map<String, String>> results = [];
        for (var item in data['items']) {
          results.add({
            'title': item['title'] as String? ?? '',
            'snippet': item['snippet'] as String? ?? '',
          });
        }
        return results;
      } else {
        debugPrint(
          'Google Search API 錯誤: ${response.statusCode} ${response.body}',
        );
        return [];
      }
    } catch (e) {
      debugPrint('Google Search 請求失敗: $e');
      return [];
    }
  }
}
