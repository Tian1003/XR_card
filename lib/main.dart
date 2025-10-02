import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/home_page.dart';
import 'data/supabase_services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    // 天
    url: 'https://afqtdcbyezgjnearxgxz.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmcXRkY2J5ZXpnam5lYXJ4Z3h6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUyMzg4NTYsImV4cCI6MjA3MDgxNDg1Nn0.1YwgDMEBrss177ADUD1VvMcKqWU0skMmzubmq0UhTec',
    // 蔡
    // url: 'https://sjfjxhagyodvibvajmdm.supabase.co',
    // anonKey:
    //     'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNqZmp4aGFneW9kdmlidmFqbWRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTU2MDc2NjAsImV4cCI6MjA3MTE4MzY2MH0.9GqgOZT79mPJ2obPQ_uIcCU7xHNeb_BYYAaFD7qzrq4',
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
