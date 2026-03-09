import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'pages/login_page.dart';
import 'pages/machine_list_page.dart';

/// Aquivio BIB 管理系統
/// 用於管理飲料機的原料包 (BIB)

void main() {
  runApp(const AquivioBibManagerApp());
}

class AquivioBibManagerApp extends StatelessWidget {
  const AquivioBibManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aquivio BIB 管理',
      debugShowCheckedModeBanner: false,

      // Material Design 3 主題
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3), // 藍色主題
          brightness: Brightness.light,
        ),
        // 卡片樣式
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // 輸入框樣式
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
        ),
        // 按鈕樣式
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),

      // 深色模式主題
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),

      // 跟隨系統設定
      themeMode: ThemeMode.system,

      // 中文本地化
      locale: const Locale('zh', 'TW'),

      // 啟動頁面（檢查登入狀態）
      home: const SplashScreen(),
    );
  }
}

/// 啟動畫面
/// 檢查登入狀態並導向對應頁面
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  /// 檢查登入狀態
  Future<void> _checkAuthStatus() async {
    final apiService = ApiService();

    // 稍微延遲讓畫面顯示
    await Future.delayed(const Duration(milliseconds: 500));

    final isLoggedIn = await apiService.isLoggedIn();

    if (!mounted) return;

    // 根據登入狀態導向不同頁面
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) =>
            isLoggedIn ? const MachineListPage() : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Icon(
              Icons.local_drink,
              size: 80,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Aquivio BIB 管理',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '飲料機原料包管理系統',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
