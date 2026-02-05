// ============================================================================
// ModeSelectionPage - 模式選擇頁面（含自動偵測 Arduino）
// ============================================================================
// 功能：
// - 自動掃描 COM 埠，發送 "connect" 偵測 Arduino 韌體類型
//   - 回傳 "connectedMain" → 自動進入 Main Board 模式
//   - 回傳 "connectedBodyDoor" → 自動進入 Body&Door Board 模式
// - 偵測失敗時持續重試，同時保留手動按鈕可跳過等待
// - 語言切換開關，與設定頁面連動
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_firmware_tester_unified/config/app_mode.dart';
import 'package:flutter_firmware_tester_unified/main_mode/main_navigation_page.dart';
import 'package:flutter_firmware_tester_unified/bodydoor_mode/bodydoor_navigation_page.dart';
import 'package:flutter_firmware_tester_unified/shared/language_state.dart';

class ModeSelectionPage extends StatefulWidget {
  const ModeSelectionPage({super.key});

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage> {
  /// 判斷目前是否為中文
  bool get _isChinese => globalLanguageNotifier.value == AppLanguage.zhTW;

  // ==================== 自動偵測狀態 ====================

  /// 是否正在掃描
  bool _isScanning = false;

  /// 掃描狀態文字
  String _scanStatus = '';

  /// 重試計時器
  Timer? _retryTimer;

  /// 是否已跳轉（防止重複跳轉）
  bool _navigated = false;

  /// 當前正在探測的串口（用於清理）
  SerialPort? _probePort;

  // ==================== 生命週期 ====================

  @override
  void initState() {
    super.initState();
    // 延遲一幀再開始偵測，確保 UI 已建構完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoDetect();
    });
  }

  @override
  void dispose() {
    _stopAutoDetect();
    super.dispose();
  }

  // ==================== 自動偵測邏輯 ====================

  /// 停止自動偵測（清理所有資源）
  void _stopAutoDetect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _closeProbePort();
  }

  /// 關閉探測用的串口
  void _closeProbePort() {
    try {
      _probePort?.close();
    } catch (_) {}
    try {
      _probePort?.dispose();
    } catch (_) {}
    _probePort = null;
  }

  /// 開始自動偵測 Arduino
  Future<void> _startAutoDetect() async {
    if (_navigated || !mounted) return;

    setState(() {
      _isScanning = true;
      _scanStatus = _isChinese ? '正在偵測 Arduino...' : 'Detecting Arduino...';
    });

    // 取得所有可用 COM 埠
    List<String> ports;
    try {
      ports = SerialPort.availablePorts;
    } catch (e) {
      ports = [];
    }

    if (ports.isEmpty) {
      if (mounted && !_navigated) {
        setState(() {
          _scanStatus = _isChinese
              ? '未偵測到 COM 埠，持續掃描中...'
              : 'No COM port detected, scanning...';
        });
        _scheduleRetry();
      }
      return;
    }

    // 逐一探測每個 COM 埠
    for (int i = 0; i < ports.length; i++) {
      if (_navigated || !mounted) return;

      final portName = ports[i];
      setState(() {
        _scanStatus = _isChinese
            ? '正在探測 $portName (${i + 1}/${ports.length})...'
            : 'Probing $portName (${i + 1}/${ports.length})...';
      });

      final result = await _probeSerialPort(portName);

      if (result != null && mounted && !_navigated) {
        setState(() {
          _isScanning = false;
          _scanStatus = _isChinese
              ? '偵測到 ${result == AppMode.main ? "Main Board" : "Body & Door Board"}，正在進入...'
              : 'Detected ${result == AppMode.main ? "Main Board" : "Body & Door Board"}, entering...';
        });

        // 短暫延遲讓使用者看到結果
        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted && !_navigated) {
          _selectMode(context, result, arduinoPort: portName);
        }
        return;
      }
    }

    // 所有埠都未偵測到 Arduino
    if (mounted && !_navigated) {
      setState(() {
        _scanStatus = _isChinese
            ? '未偵測到 Arduino，持續掃描中...'
            : 'No Arduino detected, scanning...';
      });
      _scheduleRetry();
    }
  }

  /// 排程 3 秒後重試
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_navigated) {
        _startAutoDetect();
      }
    });
  }

  /// 探測單一串口，回傳偵測到的模式（null 表示未偵測到）
  Future<AppMode?> _probeSerialPort(String portName) async {
    _closeProbePort();

    try {
      _probePort = SerialPort(portName);

      if (!_probePort!.openReadWrite()) {
        _closeProbePort();
        return null;
      }

      // 設定串口參數: 115200, 8N1
      final config = SerialPortConfig();
      config.baudRate = 115200;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      config.rts = SerialPortRts.off;
      config.dtr = SerialPortDtr.off;
      _probePort!.config = config;

      // 等待 Arduino 重置初始化
      await Future.delayed(const Duration(milliseconds: 1000));

      if (_navigated || !mounted) {
        _closeProbePort();
        return null;
      }

      // 發送 "connect\n" 指令
      final connectCmd = Uint8List.fromList('connect\n'.codeUnits);
      try {
        _probePort!.write(connectCmd);
      } catch (e) {
        _closeProbePort();
        return null;
      }

      // 等待回應（最多 2 秒，每 100ms 檢查一次）
      final buffer = <int>[];
      for (int wait = 0; wait < 20; wait++) {
        await Future.delayed(const Duration(milliseconds: 100));

        if (_navigated || !mounted) {
          _closeProbePort();
          return null;
        }

        // 讀取可用資料
        try {
          final available = _probePort!.bytesAvailable;
          if (available > 0) {
            final data = _probePort!.read(available);
            buffer.addAll(data);

            // 檢查是否收到完整回應（含換行符）
            final response = utf8
                .decode(buffer, allowMalformed: true)
                .toLowerCase();
            if (response.contains('connectedmain')) {
              _closeProbePort();
              return AppMode.main;
            }
            if (response.contains('connectedbodydoor')) {
              _closeProbePort();
              return AppMode.bodyDoor;
            }
          }
        } catch (_) {
          // 讀取錯誤，跳過
        }
      }

      _closeProbePort();
      return null;
    } catch (e) {
      _closeProbePort();
      return null;
    }
  }

  // ==================== 頁面導航 ====================

  /// 切換語言（全域唯一，所有模式自動同步）
  void _toggleLanguage() {
    globalLanguageNotifier.value = _isChinese
        ? AppLanguage.en
        : AppLanguage.zhTW;
  }

  void _selectMode(BuildContext context, AppMode mode, {String? arduinoPort}) {
    if (_navigated) return;
    _navigated = true;

    // 停止自動偵測
    _stopAutoDetect();

    Widget targetPage;
    switch (mode) {
      case AppMode.main:
        targetPage = MainNavigationPage(initialArduinoPort: arduinoPort);
        break;
      case AppMode.bodyDoor:
        targetPage = BodyDoorNavigationPage(initialArduinoPort: arduinoPort);
        break;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => targetPage),
    );
  }

  // ==================== UI 建構 ====================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: globalLanguageNotifier,
      builder: (context, language, _) {
        final bool isCN = language == AppLanguage.zhTW;
        return Scaffold(
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A9A9A),
                  Color(0xFF2E7D9A),
                  Color(0xFF4A5A9A),
                ],
              ),
            ),
            child: Stack(
              children: [
                // 語言切換按鈕 - 右上角
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildLanguageToggle(isCN),
                ),
                // 主要內容
                Column(
                  children: [
                    const SizedBox(height: 60),
                    // 標題
                    const Text(
                      'Aquivio Firmware Tester',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCN ? '請選擇測試模式' : 'Select Test Mode',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // 自動偵測狀態（卡片上方，醒目提示）
                    _buildScanStatus(isCN),
                    const SizedBox(height: 20),
                    // 模式選擇按鈕
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Main Board 按鈕
                            _buildModeCard(
                              context: context,
                              mode: AppMode.main,
                              icon: Icons.developer_board,
                              title: 'Main Board',
                              subtitle: isCN
                                  ? 'Main 測試治具'
                                  : 'Main Test Fixture',
                              description: isCN
                                  ? '6 頁完整功能\nArduino + STM32 雙串口\n23 個 ADC 通道'
                                  : '6-Page Full Features\nArduino + STM32 Dual Serial\n23 ADC Channels',
                              color: const Color(0xFF2E7D32),
                            ),
                            const SizedBox(width: 40),
                            // Body&Door Board 按鈕
                            _buildModeCard(
                              context: context,
                              mode: AppMode.bodyDoor,
                              icon: Icons.door_sliding,
                              title: 'Body & Door Board',
                              subtitle: isCN
                                  ? 'BodyDoor 測試治具'
                                  : 'BodyDoor Test Fixture',
                              description: isCN
                                  ? '4 頁精簡功能\nArduino 單串口\n19 個 ADC 通道'
                                  : '4-Page Compact Features\nArduino Single Serial\n19 ADC Channels',
                              color: const Color(0xFF1565C0),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 底部版權
                    Padding(
                      padding: const EdgeInsets.only(bottom: 30),
                      child: Text(
                        '© 2026 Aquivio',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 建構掃描狀態列（卡片上方，醒目提示）
  Widget _buildScanStatus(bool isCN) {
    // 判斷是否需要顯示「請接上 USB」提示
    final showUsbHint =
        _scanStatus.contains('未偵測到') || _scanStatus.contains('No ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 掃描狀態
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isScanning) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              _scanStatus,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        // 「請接上 USB」提示
        if (showUsbHint) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.usb, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  isCN ? '請將 USB 接上電腦' : 'Please connect USB to computer',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 語言切換按鈕
  Widget _buildLanguageToggle(bool isCN) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 中文按鈕
          GestureDetector(
            onTap: isCN ? null : _toggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isCN ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '中文',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCN ? const Color(0xFF2E7D9A) : Colors.white,
                ),
              ),
            ),
          ),
          // EN 按鈕
          GestureDetector(
            onTap: isCN ? _toggleLanguage : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isCN ? Colors.transparent : Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'EN',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCN ? Colors.white : const Color(0xFF2E7D9A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required AppMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _selectMode(context, mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 280,
          height: 320,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 圖標
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: color),
              ),
              const SizedBox(height: 20),
              // 標題
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              // 副標題
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              // 說明
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
