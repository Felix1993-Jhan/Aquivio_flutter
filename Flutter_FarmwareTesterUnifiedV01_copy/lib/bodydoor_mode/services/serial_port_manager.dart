// ============================================================================
// SerialPortManager - 串口管理類別
// ============================================================================
// 功能：負責處理 Arduino 串口的所有操作，包括：
// - 開啟/關閉串口連接
// - 發送字串指令
// - 接收並解析串口資料
// - 管理日誌記錄
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialPortManager {
  // -------------------- 私有成員變數 --------------------

  /// 串口物件，null 表示尚未連接
  SerialPort? _port;

  /// 定時讀取計時器（每 50ms 輪詢讀取串口資料）
  Timer? _readTimer;

  // -------------------- 公開成員變數 --------------------

  /// 串口識別名稱（如 "Arduino"），用於日誌顯示
  final String name;

  /// 日誌通知器
  final ValueNotifier<String> logNotifier = ValueNotifier('');

  /// 連接狀態通知器
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier(false);

  /// 接收緩衝區 - 用於累積不完整的位元組資料
  final List<int> _receiveBuffer = [];

  /// 是否為文字模式（BodyDoor 只使用文字模式）
  final bool isTextMode;

  /// 數據接收回調（用於儲存數據）
  /// 參數: (int id, int value)
  void Function(int id, int value)? onDataReceived;

  /// 當前連接的串口名稱
  String? _currentPortName;

  // -------------------- 心跳機制 --------------------

  /// 心跳定時器（每秒發送一次心跳指令）
  Timer? _heartbeatTimer;

  /// 心跳回應狀態通知器（true = 連接正常，false = 等待回應中）
  final ValueNotifier<bool> heartbeatOkNotifier = ValueNotifier(false);

  /// 連續心跳失敗計數
  int _heartbeatFailCount = 0;

  /// 心跳失敗閾值（連續幾次失敗後視為斷開）
  static const int _heartbeatFailThreshold = 3;

  /// 是否正在等待心跳回應
  bool _waitingForHeartbeat = false;

  /// 上次活動時間（任何指令發送或接收都會更新）
  DateTime _lastActivityTime = DateTime.now();

  /// 心跳失敗回調（用於通知外部連接可能已斷開）
  void Function()? onHeartbeatFailed;

  /// 偵測到錯誤模式的裝置通知器
  /// 當收到其他模式的心跳回應時設為 true（例如在 BodyDoor 模式下收到 "connectedmain"）
  final ValueNotifier<bool> wrongModeDetectedNotifier = ValueNotifier(false);

  // -------------------- 建構函式 --------------------

  SerialPortManager(this.name, {this.isTextMode = true});

  // -------------------- Getter --------------------

  /// 檢查串口是否已連接
  bool get isConnected => _port != null && isConnectedNotifier.value;

  /// 取得當前連接的串口名稱
  String? get currentPortName => _currentPortName;

  // ============================================================================
  // 串口連接操作
  // ============================================================================

  /// 開啟串口連接
  bool open(String portName, {int baudRate = 115200}) {
    close();

    try {
      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        final error = SerialPort.lastError;
        _log('無法開啟串口 $portName: $error');
        _port = null;
        return false;
      }

      // 設定串口參數: 115200 波特率, 8 資料位元, 無校驗, 1 停止位元
      final config = SerialPortConfig();
      config.baudRate = baudRate;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      config.rts = SerialPortRts.off;
      config.dtr = SerialPortDtr.off;
      _port!.config = config;

      _currentPortName = portName;

      isConnectedNotifier.value = true;
      wrongModeDetectedNotifier.value = false;
      _log('串口 $portName 已開啟 (115200, 8, N, 1)');
      _startReading();
      return true;
    } catch (e) {
      _log('開啟串口錯誤: $e');
      _port = null;
      return false;
    }
  }

  /// 釋放串口資源（關閉並銷毀串口物件）
  void _disposePort() {
    if (_port == null) return;

    final port = _port!;
    _port = null;

    try {
      port.close();
    } catch (e) {
      _log('關閉串口錯誤: $e');
    }

    try {
      port.dispose();
    } catch (e) {
      // dispose 可能會失敗，忽略錯誤
    }
  }

  /// 關閉串口連接
  void close() {
    stopHeartbeat();
    _readTimer?.cancel();
    _readTimer = null;

    _disposePort();

    _currentPortName = null;
    isConnectedNotifier.value = false;
  }

  /// 強制關閉串口連接（USB 被拔除或心跳失敗時使用）
  void forceClose() {
    stopHeartbeat();
    _readTimer?.cancel();
    _readTimer = null;

    _disposePort();
    _log('⚠️ 串口已強制關閉');

    _currentPortName = null;
    _receiveBuffer.clear();
    isConnectedNotifier.value = false;
  }

  // ============================================================================
  // 心跳機制
  // ============================================================================

  /// 啟動心跳機制
  /// Arduino: 每秒發送 "connect" 指令，期望回傳 "connected"
  void startHeartbeat() {
    stopHeartbeat();
    _heartbeatFailCount = 0;
    _waitingForHeartbeat = false;
    heartbeatOkNotifier.value = true;
    _lastActivityTime = DateTime.now();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendHeartbeat();
    });
  }

  /// 停止心跳機制
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _waitingForHeartbeat = false;
    _heartbeatFailCount = 0;
    heartbeatOkNotifier.value = false;
  }

  /// 發送心跳指令
  void _sendHeartbeat() {
    if (_port == null || !isConnectedNotifier.value) {
      stopHeartbeat();
      return;
    }

    // 如果最近 800ms 內有活動，跳過這次心跳
    final now = DateTime.now();
    if (now.difference(_lastActivityTime).inMilliseconds < 800) {
      _heartbeatFailCount = 0;
      heartbeatOkNotifier.value = true;
      _waitingForHeartbeat = false;
      return;
    }

    // 如果上次心跳還在等待回應
    if (_waitingForHeartbeat) {
      _heartbeatFailCount++;
      if (_heartbeatFailCount >= _heartbeatFailThreshold) {
        _log('⚠️ 心跳失敗 $_heartbeatFailCount 次，連接可能已斷開或連接錯誤');
        heartbeatOkNotifier.value = false;
        onHeartbeatFailed?.call();
        stopHeartbeat();
        return;
      }
    }

    // 發送心跳指令
    try {
      // Arduino: 發送 "connect" 心跳指令（Arduino 會回傳各自韌體識別字串）
      final data = Uint8List.fromList('connect\n'.codeUnits);
      _port!.write(data);
      _waitingForHeartbeat = true;
    } catch (e) {
      // write 拋出異常代表串口已無法通訊（USB 拔除等）
      // 立即觸發斷線，不再等待計數
      _log('⚠️ 心跳發送異常: $e，立即觸發斷線處理');
      heartbeatOkNotifier.value = false;
      onHeartbeatFailed?.call();
      stopHeartbeat();
    }
  }

  /// 處理心跳回應（收到 "connected" 時調用）
  void _handleHeartbeatResponse() {
    _waitingForHeartbeat = false;
    _heartbeatFailCount = 0;
    heartbeatOkNotifier.value = true;
    _lastActivityTime = DateTime.now();
  }

  /// 更新活動時間
  void _updateActivityTime() {
    _lastActivityTime = DateTime.now();
    if (_heartbeatFailCount > 0) {
      _heartbeatFailCount = 0;
      heartbeatOkNotifier.value = true;
    }
  }

  // ============================================================================
  // 資料發送方法
  // ============================================================================

  /// 發送字串指令
  bool sendString(String command) {
    if (_port == null) {
      _log('串口未開啟');
      return false;
    }

    try {
      final data = Uint8List.fromList('$command\n'.codeUnits);
      _port!.write(data);
      _log('發送: $command');
      return true;
    } catch (e) {
      _log('⚠️ 發送錯誤: $e，觸發斷線處理');
      heartbeatOkNotifier.value = false;
      onHeartbeatFailed?.call();
      stopHeartbeat();
      return false;
    }
  }


  // ============================================================================
  // 資料接收方法
  // ============================================================================

  /// 開始讀取串口資料（使用 Timer.periodic 輪詢）
  void _startReading() {
    _readTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_port == null) {
        _readTimer?.cancel();
        _readTimer = null;
        return;
      }

      try {
        final available = _port!.bytesAvailable;

        if (available > 0) {
          final data = _port!.read(available);

          if (data.isNotEmpty) {
            _processReceivedData(data);
          }
        }
      } catch (e) {
        _log('讀取錯誤: $e');
        _log('⚠️ 讀取異常，觸發斷線處理');
        heartbeatOkNotifier.value = false;
        onHeartbeatFailed?.call();
        stopHeartbeat();
        _readTimer?.cancel();
        _readTimer = null;
      }
    });
  }

  /// 處理接收到的串口資料
  void _processReceivedData(Uint8List data) {
    if (data.isEmpty) return;

    // 文字模式處理（Arduino）
    _receiveBuffer.addAll(data);

    while (_receiveBuffer.contains(0x0A)) {
      int newlineIndex = _receiveBuffer.indexOf(0x0A);
      List<int> lineBytes = _receiveBuffer.sublist(0, newlineIndex);
      _receiveBuffer.removeRange(0, newlineIndex + 1);
      lineBytes.removeWhere((b) => b == 0x0D);

      if (lineBytes.isNotEmpty) {
        String line = utf8.decode(lineBytes, allowMalformed: true).trim();
        if (line.isNotEmpty) {
          // 檢查是否為心跳回應
          if (line.toLowerCase() == 'connectedbodydoor') {
            _handleHeartbeatResponse();
            continue;
          }

          // 檢查是否為其他模式的心跳回應（Main Board 的 Arduino）
          if (line.toLowerCase() == 'connectedmain') {
            wrongModeDetectedNotifier.value = true;
            continue;
          }

          _log('接收: $line');
          _updateActivityTime();
          // 解析 Arduino 回應並儲存數據
          _parseArduinoResponse(line);
        }
      }
    }
  }

  // ============================================================================
  // Arduino 回應解析（BodyDoor 版本）
  // ============================================================================

  /// Arduino 回應名稱與 ID 對照表
  /// BodyDoor 韌體回傳格式: "名稱(腳位): 數值"
  /// 例如: "AmbientRL(A0): 1234" 或 "BodyPower_24V(A15,CH5): 1234"
  static const Map<String, int> _arduinoResponseToId = {
    // 直接 ADC 感測器 (A0-A14)
    'ambientrl': 0,       // A0
    'coolrl': 1,          // A1
    'sparklingrl': 2,     // A2
    'waterpump': 3,       // A3
    'o3': 4,              // A4
    'mainuvc': 5,         // A5
    'bibtemp': 6,         // A6
    'flowmeter': 7,       // A7
    'watertemp': 8,       // A8
    'leak': 9,            // A9
    'waterpressure': 10,  // A10
    'co2pressure': 11,    // A11
    'spoutuvc': 12,       // A12
    'mixuvc': 13,         // A13
    'flowmeter2': 14,     // A14
    // BodyPower (A15 透過 4051 多工器)
    'bodypower_24v': 15,       // A15,CH5
    'bodypower_12v': 16,       // A15,CH7
    'bodypower_upscreen': 17,  // A15,CH6
    'bodypower_lowscreen': 18, // A15,CH4
  };

  /// 解析 Arduino 回應
  /// BodyDoor 韌體回傳格式:
  /// - "AmbientRL(A0): 1234"
  /// - "BodyPower_24V(A15,CH5): 1234"
  /// - "4051 Enabled" / "4051 Disabled" (不需解析數值)
  void _parseArduinoResponse(String line) {
    // 格式: "名稱(腳位): 數值"
    // 名稱可包含底線和數字，例如 BodyPower_24V、FlowMeter2
    final adcPattern = RegExp(r'^([\w]+)\(([^)]+)\):\s*(-?\d+)');
    final adcMatch = adcPattern.firstMatch(line);
    if (adcMatch != null) {
      final name = adcMatch.group(1)!.toLowerCase();
      final valueStr = adcMatch.group(3)!;
      final value = int.tryParse(valueStr);
      if (value != null) {
        final id = _arduinoResponseToId[name];
        if (id != null) {
          onDataReceived?.call(id, value);
          return;
        }
      }
    }
  }

  // ============================================================================
  // 日誌管理方法
  // ============================================================================

  /// 記錄日誌訊息
  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    logNotifier.value = '[$timestamp] $message\n${logNotifier.value}';

    if (logNotifier.value.length > 10000) {
      logNotifier.value = logNotifier.value.substring(0, 8000);
    }
  }

  /// 清除所有日誌
  void clearLog() {
    logNotifier.value = '';
  }

  /// 釋放資源
  void dispose() {
    close();
    logNotifier.dispose();
    isConnectedNotifier.dispose();
    wrongModeDetectedNotifier.dispose();
  }
}
