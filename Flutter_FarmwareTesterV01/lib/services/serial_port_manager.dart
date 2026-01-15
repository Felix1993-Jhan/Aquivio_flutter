// ============================================================================
// SerialPortManager - 串口管理類別
// ============================================================================
// 功能：負責處理單一串口的所有操作，包括：
// - 開啟/關閉串口連接
// - 發送字串指令（Arduino 用）
// - 發送 16 進制指令（UR 用）
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

  /// 定時器，用於週期性讀取串口資料（每 50 毫秒檢查一次）
  Timer? _readTimer;

  // -------------------- 公開成員變數 --------------------

  /// 串口識別名稱（如 "Arduino" 或 "UR"），用於日誌顯示
  final String name;

  /// 日誌通知器
  /// 使用 ValueNotifier 實現響應式更新，當日誌內容變化時會自動通知 UI 更新
  final ValueNotifier<String> logNotifier = ValueNotifier('');

  /// 連接狀態通知器
  /// 當連接狀態變化時會自動通知 UI 更新連接指示燈
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier(false);

  /// 接收緩衝區 - 用於累積不完整的位元組資料
  ///
  /// 為什麼需要緩衝區？
  /// 1. 串口資料可能分多次到達（例如一行文字分成 3 次傳送）
  /// 2. UTF-8 編碼的中文字元占用 3 個 bytes，可能被切斷
  /// 3. 需要等待收到換行符才能確定一行資料完整
  final List<int> _receiveBuffer = [];

  /// 是否為文字模式
  /// - true（預設）: Arduino 用，接收的是 UTF-8 文字
  /// - false: UR 用，接收的是原始 16 進制資料
  final bool isTextMode;

  /// 數據接收回調（用於儲存數據）
  /// 參數: (int id, int value)
  void Function(int id, int value)? onDataReceived;

  /// 韌體版本通知器（格式: "0.0.0.X"）
  final ValueNotifier<String?> firmwareVersionNotifier = ValueNotifier(null);

  /// 韌體版本回調（用於通知版本已接收）
  void Function(String version)? onFirmwareVersionReceived;

  /// STM32 連接驗證回調（收到正確 PING 回應時調用）
  void Function(bool success)? onConnectionVerified;

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

  // -------------------- 建構函式 --------------------

  /// 建構函式
  /// @param name 串口識別名稱，用於日誌顯示
  /// @param isTextMode 是否為文字模式，預設為 true
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
  ///
  /// @param portName COM 埠名稱，如 "COM3" (Windows) 或 "/dev/ttyUSB0" (Linux)
  /// @param baudRate 波特率，預設 115200
  /// @return true 表示連接成功，false 表示失敗
  bool open(String portName, {int baudRate = 115200}) {
    close();

    try {
      _port = SerialPort(portName);

      // 先開啟串口
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
      // RTS 和 DTR 關閉（與 SSCOM 設定一致）
      config.rts = SerialPortRts.off;
      config.dtr = SerialPortDtr.off;
      _port!.config = config;

      // 記錄當前串口名稱
      _currentPortName = portName;

      isConnectedNotifier.value = true;
      _log('串口 $portName 已開啟 (115200, 8, N, 1)');
      _startReading();
      return true;
    } catch (e) {
      _log('開啟串口錯誤: $e');
      _port = null;
      return false;
    }
  }

  /// 關閉串口連接
  void close() {
    stopHeartbeat();  // 停止心跳
    _readTimer?.cancel();
    _readTimer = null;

    _disposePort();

    _currentPortName = null;
    // 重置韌體版本，以便下次連接時可以重新觸發驗證
    firmwareVersionNotifier.value = null;
    isConnectedNotifier.value = false;
  }

  /// 強制關閉串口連接（USB 被拔除或心跳失敗時使用）
  /// 嘗試關閉串口（對 Arduino CDC 有效），然後清理內部狀態
  void forceClose() {
    stopHeartbeat();  // 停止心跳
    _readTimer?.cancel();
    _readTimer = null;

    _disposePort();
    _log('⚠️ 串口已強制關閉');

    _currentPortName = null;
    _receiveBuffer.clear();
    // 重置韌體版本，以便下次連接時可以重新觸發驗證
    firmwareVersionNotifier.value = null;
    isConnectedNotifier.value = false;
  }

  /// 釋放串口資源（關閉並銷毀串口物件）
  void _disposePort() {
    if (_port == null) return;

    final port = _port!;
    _port = null;  // 先清空引用

    try {
      // 1. 關閉串口連接
      port.close();
    } catch (e) {
      _log('關閉串口錯誤: $e');
    }

    try {
      // 2. 釋放底層資源（libserialport 的 sp_free_port）
      port.dispose();
    } catch (e) {
      // dispose 可能會失敗，忽略錯誤
    }
  }

  // ============================================================================
  // 心跳機制（Arduino 和 STM32 共用）
  // ============================================================================

  /// 啟動心跳機制
  /// - Arduino（文字模式）：每秒發送 "connect" 指令
  /// - STM32（HEX 模式）：每秒發送 PING 指令（0x05 查詢韌體版本）
  void startHeartbeat() {
    stopHeartbeat();  // 先停止舊的
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

    // 如果最近 800ms 內有活動，跳過這次心跳（避免干擾正常通訊）
    final now = DateTime.now();
    if (now.difference(_lastActivityTime).inMilliseconds < 800) {
      // 有活動表示連接正常
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
      if (isTextMode) {
        // Arduino: 發送 "connect" 文字指令
        final data = Uint8List.fromList('connect\n'.codeUnits);
        _port!.write(data);
      } else {
        // STM32: 發送 PING 指令（0x05 查詢韌體版本）
        // 指令格式: 40 71 30 05 00 00 00 00 [CS]
        final pingCommand = _buildStm32PingCommand();
        _port!.write(Uint8List.fromList(pingCommand));
      }
      _waitingForHeartbeat = true;
      // 心跳指令不記錄日誌，避免干擾
    } catch (e) {
      _heartbeatFailCount++;
      if (_heartbeatFailCount >= _heartbeatFailThreshold) {
        _log('⚠️ 心跳發送失敗，連接可能已斷開或連接錯誤');
        heartbeatOkNotifier.value = false;
        onHeartbeatFailed?.call();
        stopHeartbeat();
      }
    }
  }

  /// 建構 STM32 PING 指令（查詢韌體版本）
  /// 格式: Header(40 71 30) + 命令(05) + Data(00 00 00 00) + CS
  List<int> _buildStm32PingCommand() {
    const header = [0x40, 0x71, 0x30];
    const payload = [0x05, 0x00, 0x00, 0x00, 0x00];
    final command = [...header, ...payload];

    // 計算 checksum
    final sum = command.fold(0, (int prev, int e) => prev + e);
    final cs = (0x100 - (sum & 0xFF)) & 0xFF;

    return [...command, cs];
  }

  /// 處理心跳回應
  /// - Arduino: 當收到 "connected" 時調用
  /// - STM32: 當收到韌體版本回應（0x05）時調用
  void _handleHeartbeatResponse() {
    _waitingForHeartbeat = false;
    _heartbeatFailCount = 0;
    heartbeatOkNotifier.value = true;
    _lastActivityTime = DateTime.now();
  }

  /// 更新活動時間（任何指令發送或接收時調用）
  void _updateActivityTime() {
    _lastActivityTime = DateTime.now();
    // 有活動時重置失敗計數
    if (_heartbeatFailCount > 0) {
      _heartbeatFailCount = 0;
      heartbeatOkNotifier.value = true;
    }
  }

  // ============================================================================
  // 資料發送方法
  // ============================================================================

  /// 發送字串指令（Arduino 用）
  ///
  /// @param command 要發送的指令字串，如 "flowon"、"s0" 等
  /// @return true 表示發送成功，false 表示失敗
  bool sendString(String command) {
    if (_port == null) {
      _log('串口未開啟');
      return false;
    }

    try {
      final data = Uint8List.fromList('$command\n'.codeUnits);
      _port!.write(data);
      _log('發送: $command');
      _updateActivityTime();  // 更新活動時間
      return true;
    } catch (e) {
      _log('發送錯誤: $e');
      return false;
    }
  }

  /// 發送 16 進制指令（UR 用）
  ///
  /// @param bytes 要發送的位元組列表
  /// @return true 表示發送成功，false 表示失敗
  bool sendHex(List<int> bytes) {
    if (_port == null) {
      _log('串口未開啟');
      return false;
    }

    try {
      final data = Uint8List.fromList(bytes);
      _port!.write(data);

      final hexStr = bytes
          .map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      _log('發送HEX: $hexStr');
      _updateActivityTime();  // 更新活動時間，避免心跳機制誤判
      return true;
    } catch (e) {
      _log('發送錯誤: $e');
      return false;
    }
  }

  // ============================================================================
  // 資料接收方法
  // ============================================================================

  /// 開始定時讀取串口資料
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
            if (isTextMode) {
              // 文字模式處理（Arduino）
              _receiveBuffer.addAll(data);

              while (_receiveBuffer.contains(0x0A)) {
                int newlineIndex = _receiveBuffer.indexOf(0x0A);
                List<int> lineBytes = _receiveBuffer.sublist(0, newlineIndex);
                _receiveBuffer.removeRange(0, newlineIndex + 1);
                lineBytes.removeWhere((b) => b == 0x0D);

                if (lineBytes.isNotEmpty) {
                  String line =
                      utf8.decode(lineBytes, allowMalformed: true).trim();
                  if (line.isNotEmpty) {
                    // 檢查是否為心跳回應
                    if (line.toLowerCase() == 'connected') {
                      _handleHeartbeatResponse();
                      // 心跳回應不記錄日誌
                      continue;
                    }

                    _log('接收: $line');
                    _updateActivityTime();  // 更新活動時間
                    // 解析 Arduino 回應並儲存數據
                    _parseArduinoResponse(line);
                  }
                }
              }
            } else {
              // HEX 模式處理（UR）
              // 先解析回應，判斷是否為心跳回應
              final isHeartbeatResponse = _parseUrReadResponse(data);

              // 心跳回應不記錄日誌，避免干擾
              if (!isHeartbeatResponse) {
                String hexStr = data
                    .map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase())
                    .join(' ');

                String text = String.fromCharCodes(data)
                    .replaceAll('\r', '')
                    .replaceAll('\n', ' ')
                    .trim();

                if (text.isNotEmpty && _isPrintable(text)) {
                  _log('接收: $hexStr ($text)');
                } else {
                  _log('接收: $hexStr');
                }
              }
            }
          }
        }
      } catch (e) {
        _log('讀取錯誤: $e');
      }
    });
  }

  /// 檢查字串是否全部為可列印的 ASCII 字元
  bool _isPrintable(String s) {
    return s.runes.every((r) => r >= 32 && r < 127);
  }

  // ============================================================================
  // Arduino 回應解析
  // ============================================================================

  /// Arduino 回應名稱與 ID 對照表
  /// 根據 Arduino 實際回傳的格式來對應
  static const Map<String, int> _arduinoResponseToId = {
    // SLOT0~SLOT9 對應 ID 0-9
    'slot0': 0, 'slot1': 1, 'slot2': 2, 'slot3': 3, 'slot4': 4,
    'slot5': 5, 'slot6': 6, 'slot7': 7, 'slot8': 8, 'slot9': 9,
    // WATER 對應 ID 10
    'water': 10,
    // UVC 燈對應 ID 11-13
    'mainuvc': 11, 'spoutuvc': 12, 'mixuvc': 13,
    // 繼電器對應 ID 14-16
    'ambientrl': 14, 'coolrl': 15, 'sparking': 16,
    // O3 對應 ID 17
    'o3': 17,
    // 流量計對應 ID 18
    'flow': 18,
    // 壓力計對應 ID 19-20
    'pressureco2': 19, 'pressurewater': 20,
    // 溫度對應 ID 21-23
    'mcu': 21, 'mcutemp': 21,
  };

  /// 解析 Arduino 回應
  /// 支援 Arduino 實際回傳的格式:
  /// - "SLOT0 (AD09): 1234"
  /// - "WATER (AD12): 1234"
  /// - "MainUVC (AD15): 1234"
  /// - "MCU 溫度: 25.5 °C"
  /// - "流量計數值: 1234 pulses"
  void _parseArduinoResponse(String line) {
    // 格式1: "名稱 (ADxx): 數值" - 例如 "SLOT0 (AD09): 1234"
    final adcPattern = RegExp(r'^(\w+)\s*\([^)]+\):\s*(-?\d+)');
    final adcMatch = adcPattern.firstMatch(line);
    if (adcMatch != null) {
      final name = adcMatch.group(1)!.toLowerCase();
      final valueStr = adcMatch.group(2)!;
      final value = int.tryParse(valueStr);
      if (value != null) {
        final id = _arduinoResponseToId[name];
        if (id != null) {
          onDataReceived?.call(id, value);
          return;
        }
      }
    }

    // 格式2: "MCU 溫度: 25.5 °C" - 溫度格式（浮點數轉整數，乘以10保留一位小數）
    final tempPattern = RegExp(r'^MCU\s*溫度:\s*(-?\d+\.?\d*)\s*°?C?', caseSensitive: false);
    final tempMatch = tempPattern.firstMatch(line);
    if (tempMatch != null) {
      final tempStr = tempMatch.group(1)!;
      final tempFloat = double.tryParse(tempStr);
      if (tempFloat != null) {
        // 將溫度乘以10轉為整數保存（例如 25.5 -> 255）
        final value = (tempFloat * 10).round();
        onDataReceived?.call(21, value);  // ID 21 = mcutemp
        return;
      }
    }

    // 格式3: "流量計數值: 1234 pulses" - 流量計格式
    final flowPattern = RegExp(r'流量計數值:\s*(\d+)\s*pulses?', caseSensitive: false);
    final flowMatch = flowPattern.firstMatch(line);
    if (flowMatch != null) {
      final valueStr = flowMatch.group(1)!;
      final value = int.tryParse(valueStr);
      if (value != null) {
        onDataReceived?.call(18, value);  // ID 18 = flow
        return;
      }
    }

    // 格式4: "最終計數值: 1234 pulses" - flowoff 回傳
    final finalFlowPattern = RegExp(r'最終計數值:\s*(\d+)\s*pulses?', caseSensitive: false);
    final finalFlowMatch = finalFlowPattern.firstMatch(line);
    if (finalFlowMatch != null) {
      final valueStr = finalFlowMatch.group(1)!;
      final value = int.tryParse(valueStr);
      if (value != null) {
        onDataReceived?.call(18, value);  // ID 18 = flow
        return;
      }
    }
  }

  /// 解析 UR 讀取命令回應
  /// UR 回應格式: Header(3 bytes) + 命令(1 byte) + Data(4 bytes) + CS(1 byte)
  /// 總共固定 9 bytes
  /// 返回值: true 表示為心跳回應（0x05），不需記錄日誌；false 表示其他回應
  bool _parseUrReadResponse(Uint8List data) {
    // STM32 回應固定為 9 bytes
    if (data.length != 9) return false;

    // 檢查 Header: 0x40 0x71 0x30
    if (data[0] != 0x40 || data[1] != 0x71 || data[2] != 0x30) return false;

    // 驗證 checksum (前 8 bytes 的校驗)
    final sum = data.sublist(0, 8).fold(0, (int prev, int e) => prev + e);
    final expectedCs = (0x100 - (sum & 0xFF)) & 0xFF;
    if (data[8] != expectedCs) return false;

    final command = data[3];

    // 讀取命令回應 (0x03)
    if (command == 0x03) {
      final id = data[4];
      final value = data[5] | (data[6] << 8) | (data[7] << 16);
      final result = _formatReadResult(id, value);
      _log(result);
      onDataReceived?.call(id, value);
      return false;  // 不是心跳回應
    }
    // 韌體版本回應 (0x05) - 也作為心跳回應
    // 格式: 40 71 30 05 [v1] [v2] [v3] [v4] CS
    else if (command == 0x05) {
      final v1 = data[4];  // 最低位元
      final v2 = data[5];
      final v3 = data[6];
      final v4 = data[7];  // 最高位元
      final versionStr = '$v4.$v3.$v2.$v1';

      // 處理心跳回應（STM32 的心跳使用 0x05 指令）
      _handleHeartbeatResponse();

      // 只有在版本變化或首次收到時才記錄日誌和觸發回調（避免心跳干擾）
      if (firmwareVersionNotifier.value != versionStr) {
        _log('📦 韌體版本: $versionStr');
        firmwareVersionNotifier.value = versionStr;
        onFirmwareVersionReceived?.call(versionStr);
        // 只在首次收到韌體版本時觸發連接驗證（之後的心跳回應不再觸發）
        onConnectionVerified?.call(true);
      }
      return true;  // 是心跳回應，不需額外記錄日誌
    }

    return false;
  }

  /// ID 資訊對照表：圖標、名稱、是否為溫度
  static const Map<int, Map<String, dynamic>> _idInfoMap = {
    // s0~s9: 小顆馬達 (SLOT)
    0: {'icon': '⚙️', 'name': 'SLOT1', 'isTemp': false},
    1: {'icon': '⚙️', 'name': 'SLOT2', 'isTemp': false},
    2: {'icon': '⚙️', 'name': 'SLOT3', 'isTemp': false},
    3: {'icon': '⚙️', 'name': 'SLOT4', 'isTemp': false},
    4: {'icon': '⚙️', 'name': 'SLOT5', 'isTemp': false},
    5: {'icon': '⚙️', 'name': 'SLOT6', 'isTemp': false},
    6: {'icon': '⚙️', 'name': 'SLOT7', 'isTemp': false},
    7: {'icon': '⚙️', 'name': 'SLOT8', 'isTemp': false},
    8: {'icon': '⚙️', 'name': 'SLOT9', 'isTemp': false},
    9: {'icon': '⚙️', 'name': 'SLOT10', 'isTemp': false},
    // water: 水泵
    10: {'icon': '💧', 'name': 'WATERPUMP', 'isTemp': false},
    // u0~u2: 紫外殺菌燈
    11: {'icon': '💡', 'name': 'MainUVC', 'isTemp': false},
    12: {'icon': '💡', 'name': 'SpoutUVC', 'isTemp': false},
    13: {'icon': '💡', 'name': 'MixUVC', 'isTemp': false},
    // relay
    14: {'icon': '🔌', 'name': 'AmbientRL', 'isTemp': false},
    15: {'icon': '🔌', 'name': 'CoolRL', 'isTemp': false},
    16: {'icon': '🔌', 'name': 'SparklRL', 'isTemp': false},
    // o3: 臭氧
    17: {'icon': '🌀', 'name': 'O3', 'isTemp': false},
    // flow: 流量計
    18: {'icon': '🌊', 'name': 'Flow', 'isTemp': false},
    // 壓力計
    19: {'icon': '📊', 'name': 'PressureCO2', 'isTemp': false},
    20: {'icon': '📊', 'name': 'PressureWater', 'isTemp': false},
    // 溫度感測器 (Arduino 只有 MCUtemp)
    21: {'icon': '🌡️', 'name': 'MCUtemp', 'isTemp': true},
    // 以下為 STM32 專用（Arduino 沒有）
    22: {'icon': '🌡️', 'name': 'WATERtemp', 'isTemp': true},
    23: {'icon': '🌡️', 'name': 'BIBtemp', 'isTemp': true},
  };

  /// 根據 ID 取得格式化的讀取結果字串
  String _formatReadResult(int id, int value) {
    final info = _idInfoMap[id];
    if (info == null) {
      return '❓ ID$id, ADC= $value';
    }

    final icon = info['icon'] as String;
    final name = info['name'] as String;
    final isTemp = info['isTemp'] as bool;

    if (isTemp) {
      return '$icon $name, 量測溫度= $value';
    } else {
      return '$icon $name, ADC= $value';
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
    firmwareVersionNotifier.dispose();
  }
}