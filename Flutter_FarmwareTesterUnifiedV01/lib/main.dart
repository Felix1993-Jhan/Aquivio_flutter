// ============================================================================
// Firmware Tester Unified - 統一測試治具上位機
// ============================================================================
// 功能說明：
// 統一管理 Main Board 與 Body&Door Board 兩種測試模式
//
// 應用程式流程：
// SplashScreen → ModeSelectionPage → MainNavigationPage / BodyDoorNavigationPage
// ============================================================================

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_firmware_tester_unified/shared/widgets/splash_screen.dart';
import 'package:flutter_firmware_tester_unified/mode_selection_page.dart';

// ==================== 應用程式入口 ====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化視窗管理器並設定最小尺寸
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(800, 600),
    size: Size(1200, 800),
    center: true,
    title: 'Firmware Tester Unified',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

/// 應用程式根 Widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firmware Tester Unified',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(
        duration: Duration(milliseconds: 3000),
        child: ModeSelectionPage(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
