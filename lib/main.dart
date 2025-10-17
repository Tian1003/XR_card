import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 在 App 啟動前載入 .env 檔案
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    // 天
    // url: dotenv.env['Tian_Supabase_URL']!,
    // anonKey: dotenv.env['Tian_Supabase_Anon_Key']!,

    // 蔡
    url: dotenv.env['Sai_Supabase_URL']!,
    anonKey: dotenv.env['Sai_Supabase_Anon_Key']!,
  );

  // 建立並偵測裝置，iPad=1、iPhone=2
  await SupabaseService.init(Supabase.instance.client);

  runApp(const MyApp());
}

// 全域存取 Supabase 客戶端
//final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Business Card App',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const HomePage(), // 直接使用 HomePage 管理頁面
    );
  }
}
