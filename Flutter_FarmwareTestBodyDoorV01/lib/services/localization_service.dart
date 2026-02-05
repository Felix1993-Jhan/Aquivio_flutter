// ============================================================================
// LocalizationService - 多語言管理服務
// ============================================================================
// 功能：管理應用程式的多語言字串
// - 支援中文（繁體）和英文
// - 使用 ValueNotifier 實現響應式更新
// - 方便日後擴充更多語言
// ============================================================================

import 'package:flutter/material.dart';

/// 支援的語言列表
enum AppLanguage {
  zhTW, // 繁體中文
  en,   // 英文
}

/// 語言顯示名稱
extension AppLanguageExtension on AppLanguage {
  String get displayName {
    switch (this) {
      case AppLanguage.zhTW:
        return '繁體中文';
      case AppLanguage.en:
        return 'English';
    }
  }

  String get code {
    switch (this) {
      case AppLanguage.zhTW:
        return 'zh-TW';
      case AppLanguage.en:
        return 'en';
    }
  }
}

/// 多語言管理服務（單例模式）
class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  /// 當前語言通知器
  final ValueNotifier<AppLanguage> currentLanguageNotifier =
      ValueNotifier(AppLanguage.zhTW);

  /// 取得當前語言
  AppLanguage get currentLanguage => currentLanguageNotifier.value;

  /// 設定語言
  void setLanguage(AppLanguage language) {
    currentLanguageNotifier.value = language;
  }

  /// 取得翻譯字串
  String tr(String key) {
    final translations = _translations[currentLanguage];
    return translations?[key] ?? key;
  }

  /// 取得帶參數的翻譯字串
  /// 使用 {param} 格式的佔位符
  String trParams(String key, Map<String, dynamic> params) {
    String result = tr(key);
    params.forEach((paramKey, value) {
      result = result.replaceAll('{$paramKey}', value.toString());
    });
    return result;
  }

  /// 翻譯字串對照表
  static final Map<AppLanguage, Map<String, String>> _translations = {
    // ==================== 繁體中文 ====================
    AppLanguage.zhTW: {
      // 應用程式標題
      'app_title': '命令控制',

      // 頁面標題
      'page_auto_detection': '自動檢測流程',
      'page_command_control': '命令控制',
      'page_data_storage': '資料儲存',
      'page_settings': '設定',

      // 側邊抽屜
      'drawer_title': '自動檢測流程系統',
      'drawer_subtitle': 'Arduino & STM32',
      'connection_status': '連接狀態',

      // 連接相關
      'connected': '已連接',
      'disconnected': '未連接',
      'not_connected': '未連接',
      'connect': '連接',
      'disconnect': '斷開',
      'select_com_port': '選擇 COM 埠',
      'connecting': '連接中',
      'verifying_device': '驗證裝置...',

      // Arduino 相關
      'arduino_control': 'Arduino 控制',
      'arduino_connected': 'Arduino 已連接',
      'arduino_disconnected': 'Arduino 已斷開',
      'arduino_connect_failed': 'Arduino 連接失敗，請稍後再試',
      'arduino_port_in_use': '此串口已被 STM32 使用',
      'select_arduino_port': '請先選擇 Arduino 串口',
      'connect_arduino_first': '請先連接 Arduino',
      'arduino_usb_removed': 'Arduino USB 已拔除，連接已自動關閉',
      'arduino_connection_error': 'Arduino 連接可能已斷開\n或連接錯誤',

      // COM 埠相關
      'no_com_port': '未偵測到任何 COM 埠，請檢查 USB 連接',
      'com_port_detected': '偵測到 {count} 個 COM 埠',
      'new_com_port_detected': '偵測到新 COM 埠: {ports}',

      // 資料儲存頁面
      'arduino_data': 'Arduino 數據',
      'hardware_data': '硬體數據',
      'batch_read': '一鍵讀取',
      'stop': '停止',
      // 表格欄位
      'column_name': '名稱',
      'column_arduino': 'Arduino',

      // 設定頁面
      'settings': '設定',
      'detection_rules_title': '檢測規則說明',
      'detection_rules_desc': '查看所有自動檢測的規則、閾值設定和判斷條件',
      'reset_single': '恢復原廠',
      'reset_all': '全部恢復原廠',
      'reset_confirm_title': '確認恢復',
      'reset_confirm_msg': '確定要恢復此項目為原廠設定嗎？',
      'reset_all_confirm_msg': '確定要全部恢復為原廠設定嗎？',
      'reset_factory_done': '已恢復原廠設定',
      'value_saved': '已儲存',
      'min_label': '最小',
      'max_label': '最大',
      'value_label': '數值',
      'current_value': '當前值',
      'default_value': '預設值',
      'language': '語言',
      'language_setting': '語言設定',
      'select_language': '選擇語言',

      // 通用
      'send': '發送',
      'refresh': '刷新',
      'cancel': '取消',
      'confirm': '確認',
      'error': '錯誤',
      'warning': '警告',
      'success': '成功',
      'loading': '載入中...',
      'clear': '清除',

      // Arduino 面板
      'command_buttons': '指令按鈕:',
      'receive_log': '接收日誌:',
      'continuous_connection': '持續連接中',
      'connection_lost': '連線中斷',
      'cmd_sensor': '感測器 (ID 0-5)',
      'cmd_sensor_ext': '感測器續 (ID 6-9)',
      'cmd_pressure': '壓力 (ID 10-11)',
      'cmd_uvc': 'UVC (ID 12-13)',
      'cmd_flowmeter2': '流量計2 (ID 14)',
      'cmd_bodypower': 'BodyPower (ID 15-18)',
      'cmd_tool': '工具',

      // 連接過程訊息
      'arduino_connecting': 'Arduino 連接中... ({current}/{max})',
      'sent_arduino_command': '已發送 Arduino 指令: {command}',

      // 自動檢測流程
      'auto_detection_start': '自動檢測開始',
      'auto_detection_running': '自動檢測進行中...',
      'auto_detection_step_connect': '步驟 1/6: 連接設備',
      'auto_detection_step_idle': '步驟 2/6: 讀取無動作狀態',
      'auto_detection_step_result': '步驟 6/6: 結果判定',
      'test_result_pass': '通過',
      'test_result_fail': '異常',
      'test_all_passed': '所有項目檢測通過',
      'test_failed_items': '以下項目異常:',
      'no_test_result': '尚無檢測結果',
      'slow_debug_mode_on': '慢速調試模式已開啟',
      'slow_debug_mode_off': '慢速調試模式已關閉',
      'debug_mode': '調試模式',
      'debug_pause': '暫停',
      'debug_resume': '繼續',
      'prev_record': '上一筆',
      'next_record': '下一筆',
      'power_33v_anomaly': '3.3V 電源異常（ID 6,8,9,10,11 數值全部過低）',
      'power_body12v_anomaly': 'Body 12V 電源異常（ID 0,1,2,3,4,5,7 數值全部過低，且 3.3V 異常）',
      'power_door24v_anomaly': 'Door 24V 升壓電路異常（BP_24V 數值過低）',
      'power_door12v_anomaly': 'Door 12V 電源異常（ID 12,13,14,16,17,18 數值全部過低）',
      'usb_not_connected': '請將 USB 接上電腦',
      'retry_step': '重試中 ({current}/{max})...',
      'auto_detection_cancelled': '自動檢測已取消',
      'connecting_arduino': '正在連接 Arduino...',
      'reading_hardware_data': '讀取硬體數據...',

      // 檢測規則頁面
      'rules_threshold_section': '閾值檢測規則',
      'rules_arduino_idle_title': 'Arduino Idle 閾值',
      'rules_arduino_idle_desc': 'Arduino 在無動作狀態下的 ADC 數值範圍',
      'rules_33v_section': '3.3V 電源異常偵測',
      'rules_33v_title': '3.3V 電源異常判定',
      'rules_33v_desc': '當以下 5 個 3.3V 感測器的 ADC 數值同時低於閾值時，判定為 3.3V 電源異常',
      'rules_33v_ids': '檢測 ID：BibTemp、WaterTemp、Leak、WaterPressure、CO2Pressure',
      'rules_33v_threshold_label': '異常閾值（低於此值）',
      'rules_33v_condition': '觸發條件：以上 5 個 ID 的數值「全部」低於閾值',
      'rules_33v_action_realtime': '即時警告：DataStorage 頁面和 AutoDetection 頁面顯示紅色警告橫幅',
      'rules_33v_action_result': '檢測結果：自動偵測結果中標記「3.3V 電源異常」',
      'rules_body12v_section': 'Body 12V 電源異常偵測',
      'rules_body12v_title': 'Body 12V 電源異常判定',
      'rules_body12v_desc': '當以下 7 個 Body 12V 通道的 ADC 數值同時低於閾值，且 3.3V 電源異常也被觸發時，判定為 Body 12V 電源異常',
      'rules_body12v_ids': '檢測 ID：AmbientRL、CoolRL、SparklingRL、WaterPump、O3、MainUVC、FlowMeter',
      'rules_body12v_threshold_label': '異常閾值（低於此值）',
      'rules_body12v_condition': '觸發條件：以上 7 個 ID 的數值「全部」低於閾值',
      'rules_body12v_prerequisite': '前置條件：3.3V 電源異常必須同時被觸發（階層式檢測）',
      'rules_body12v_action_realtime': '即時警告：DataStorage 頁面和 AutoDetection 頁面顯示深橘色警告橫幅',
      'rules_body12v_action_result': '檢測結果：自動偵測結果中標記「Body 12V 電源異常」',
      'rules_door24v_section': 'Door 24V 升壓電路異常偵測',
      'rules_door24v_title': 'Door 24V 升壓電路異常判定',
      'rules_door24v_desc': '當 BP_24V 的 ADC 數值低於閾值時，判定為升壓電路異常',
      'rules_door24v_ids': '檢測 ID：BP_24V',
      'rules_door24v_threshold_label': '異常閾值（低於此值）',
      'rules_door24v_condition': '觸發條件：BP_24V 數值低於閾值',
      'rules_door24v_action_realtime': '即時警告：DataStorage 頁面和 AutoDetection 頁面顯示紫色警告橫幅',
      'rules_door24v_action_result': '檢測結果：自動偵測結果中標記「Door 24V 升壓電路異常」',
      'rules_door12v_section': 'Door 12V 電源異常偵測',
      'rules_door12v_title': 'Door 12V 電源異常判定',
      'rules_door12v_desc': '當以下 6 個 Door 12V 通道的 ADC 數值同時低於閾值時，判定為 Door 12V 電源異常',
      'rules_door12v_ids': '檢測 ID：SpoutUVC、MixUVC、FlowMeter2、BP_12V、BP_UpScreen、BP_LowScreen',
      'rules_door12v_threshold_label': '異常閾值（低於此值）',
      'rules_door12v_condition': '觸發條件：以上 6 個 ID 的數值「全部」低於閾值',
      'rules_door12v_action_realtime': '即時警告：DataStorage 頁面和 AutoDetection 頁面顯示靛藍色警告橫幅',
      'rules_door12v_action_result': '檢測結果：自動偵測結果中標記「Door 12V 電源異常」',
      'rules_polling_section': '輪詢機制',
      'rules_polling_retry_title': '資料讀取重試',
      'rules_polling_retry_desc': '當某個 ID 沒有收到回應時的重試機制',
      'rules_polling_max_retry_label': '最大重試次數',
      'rules_polling_hw_wait_label': '硬體等待 (ms)',

      // 閾值設定
      'threshold_settings': '閾值設定',
      'threshold_settings_desc': '設定自動檢測的數值範圍',
      'arduino_idle_threshold': 'Arduino 無動作閾值',
      'idle_threshold': '無動作閾值',
      'min_value': '最小值',
      'max_value': '最大值',
      'threshold_range': '範圍',
      'reset_to_defaults': '恢復初始設定',
      'reset_all_confirm': '確定要恢復所有閾值為初始設定嗎？',
      'reset_success': '已恢復初始設定',
      'save_success': '設定已儲存',
      'hardware_threshold': '硬體閾值 (ID 0-18)',
      'apply_to_all': '套用到所有 ID',
      'edit_threshold': '編輯閾值',
      'id_label': 'ID {id}',
      'value_out_of_range': '數值超出範圍',

    },

    // ==================== English ====================
    AppLanguage.en: {
      // App title
      'app_title': 'Command Control',

      // Page titles
      'page_auto_detection': 'Auto Detection',
      'page_command_control': 'Command Control',
      'page_data_storage': 'Data Storage',
      'page_settings': 'Settings',

      // Drawer
      'drawer_title': 'Auto Detection System',
      'drawer_subtitle': 'Arduino & STM32',
      'connection_status': 'Connection Status',

      // Connection related
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'not_connected': 'Not Connected',
      'connect': 'Connect',
      'disconnect': 'Disconnect',
      'select_com_port': 'Select COM Port',
      'connecting': 'Connecting',
      'verifying_device': 'Verifying device...',

      // Arduino related
      'arduino_control': 'Arduino Control',
      'arduino_connected': 'Arduino Connected',
      'arduino_disconnected': 'Arduino Disconnected',
      'arduino_connect_failed': 'Arduino connection failed, please try again',
      'arduino_port_in_use': 'This port is already used by STM32',
      'select_arduino_port': 'Please select Arduino port first',
      'connect_arduino_first': 'Please connect Arduino first',
      'arduino_usb_removed': 'Arduino USB removed, connection closed',
      'arduino_connection_error': 'Arduino connection may be lost\nor connection error',

      // COM port related
      'no_com_port': 'No COM port detected, please check USB connection',
      'com_port_detected': 'Detected {count} COM port(s)',
      'new_com_port_detected': 'New COM port detected: {ports}',

      // Data storage page
      'arduino_data': 'Arduino Data',
      'hardware_data': 'Hardware Data',
      'batch_read': 'Batch Read',
      'stop': 'Stop',

      // Table columns
      'column_name': 'Name',
      'column_arduino': 'Arduino',

      // Settings page
      'settings': 'Settings',
      'detection_rules_title': 'Detection Rules',
      'detection_rules_desc': 'View all auto-detection rules, thresholds and conditions',
      'reset_single': 'Reset',
      'reset_all': 'Reset All',
      'reset_confirm_title': 'Confirm Reset',
      'reset_confirm_msg': 'Reset this item to factory defaults?',
      'reset_all_confirm_msg': 'Reset all settings to factory defaults?',
      'reset_factory_done': 'Reset to factory defaults',
      'value_saved': 'Saved',
      'min_label': 'Min',
      'max_label': 'Max',
      'value_label': 'Value',
      'current_value': 'Current',
      'default_value': 'Default',
      'language': 'Language',
      'language_setting': 'Language Setting',
      'select_language': 'Select Language',

      // General
      'send': 'Send',
      'refresh': 'Refresh',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'error': 'Error',
      'warning': 'Warning',
      'success': 'Success',
      'loading': 'Loading...',
      'clear': 'Clear',

      // Arduino panel
      'command_buttons': 'Commands:',
      'receive_log': 'Receive Log:',
      'continuous_connection': 'Connected',
      'connection_lost': 'Connection Lost',
      'cmd_sensor': 'Sensor (ID 0-5)',
      'cmd_sensor_ext': 'Sensor Ext (ID 6-9)',
      'cmd_pressure': 'Pressure (ID 10-11)',
      'cmd_uvc': 'UVC (ID 12-13)',
      'cmd_flowmeter2': 'FlowMeter2 (ID 14)',
      'cmd_bodypower': 'BodyPower (ID 15-18)',
      'cmd_tool': 'Tool',

      // Connection process messages
      'arduino_connecting': 'Arduino connecting... ({current}/{max})',
      'sent_arduino_command': 'Sent Arduino command: {command}',

      // Auto detection process
      'auto_detection_start': 'Auto Detect',
      'auto_detection_running': 'Detecting...',
      'auto_detection_step_connect': 'Step 1/6: Connecting Devices',
      'auto_detection_step_idle': 'Step 2/6: Reading Idle State',
      'auto_detection_step_result': 'Step 6/6: Result Check',
      'test_result_pass': 'Pass',
      'test_result_fail': 'Error',
      'test_all_passed': 'All items passed',
      'test_failed_items': 'Failed items:',
      'no_test_result': 'No test result yet',
      'slow_debug_mode_on': 'Slow debug mode enabled',
      'slow_debug_mode_off': 'Slow debug mode disabled',
      'debug_mode': 'Debug Mode',
      'debug_pause': 'Pause',
      'debug_resume': 'Resume',
      'prev_record': 'Previous',
      'next_record': 'Next',
      'power_33v_anomaly': '3.3V power anomaly (ID 6,8,9,10,11 all below threshold)',
      'power_body12v_anomaly': 'Body 12V power anomaly (ID 0,1,2,3,4,5,7 all below threshold + 3.3V anomaly)',
      'power_door24v_anomaly': 'Door 24V boost circuit anomaly (BP_24V below threshold)',
      'power_door12v_anomaly': 'Door 12V power anomaly (ID 12,13,14,16,17,18 all below threshold)',
      'usb_not_connected': 'Please connect USB to computer',
      'retry_step': 'Retrying ({current}/{max})...',
      'auto_detection_cancelled': 'Auto detection cancelled',
      'connecting_arduino': 'Connecting Arduino...',
      'reading_hardware_data': 'Reading hardware data...',

      // Detection rules page
      'rules_threshold_section': 'Threshold Detection Rules',
      'rules_arduino_idle_title': 'Arduino Idle Threshold',
      'rules_arduino_idle_desc': 'ADC value range when Arduino is idle',
      'rules_33v_section': '3.3V Power Anomaly Detection',
      'rules_33v_title': '3.3V Power Anomaly Rule',
      'rules_33v_desc': 'When all 5 ADC values of the 3.3V sensors are below threshold, it indicates 3.3V power anomaly',
      'rules_33v_ids': 'Monitored IDs: BibTemp, WaterTemp, Leak, WaterPressure, CO2Pressure',
      'rules_33v_threshold_label': 'Anomaly threshold (below this value)',
      'rules_33v_condition': 'Trigger condition: ALL 5 IDs must be below threshold simultaneously',
      'rules_33v_action_realtime': 'Real-time warning: Red warning banner on DataStorage and AutoDetection pages',
      'rules_33v_action_result': 'Detection result: Auto detection marks "3.3V power anomaly"',
      'rules_body12v_section': 'Body 12V Power Anomaly Detection',
      'rules_body12v_title': 'Body 12V Power Anomaly Rule',
      'rules_body12v_desc': 'When all 7 Body 12V channel ADC values are below threshold AND 3.3V anomaly is triggered, it indicates Body 12V power failure',
      'rules_body12v_ids': 'Monitored IDs: AmbientRL, CoolRL, SparklingRL, WaterPump, O3, MainUVC, FlowMeter',
      'rules_body12v_threshold_label': 'Anomaly threshold (below this value)',
      'rules_body12v_condition': 'Trigger condition: ALL 7 IDs must be below threshold simultaneously',
      'rules_body12v_prerequisite': 'Prerequisite: 3.3V power anomaly must also be triggered (hierarchical check)',
      'rules_body12v_action_realtime': 'Real-time warning: Deep orange warning banner on DataStorage and AutoDetection pages',
      'rules_body12v_action_result': 'Detection result: Auto detection marks "Body 12V power anomaly"',
      'rules_door24v_section': 'Door 24V Boost Circuit Anomaly Detection',
      'rules_door24v_title': 'Door 24V Boost Circuit Anomaly Rule',
      'rules_door24v_desc': 'When BP_24V ADC value is below threshold, it indicates boost circuit failure',
      'rules_door24v_ids': 'Monitored ID: BP_24V',
      'rules_door24v_threshold_label': 'Anomaly threshold (below this value)',
      'rules_door24v_condition': 'Trigger condition: BP_24V value below threshold',
      'rules_door24v_action_realtime': 'Real-time warning: Purple warning banner on DataStorage and AutoDetection pages',
      'rules_door24v_action_result': 'Detection result: Auto detection marks "Door 24V boost circuit anomaly"',
      'rules_door12v_section': 'Door 12V Power Anomaly Detection',
      'rules_door12v_title': 'Door 12V Power Anomaly Rule',
      'rules_door12v_desc': 'When all 6 Door 12V channel ADC values are below threshold, it indicates Door 12V power failure',
      'rules_door12v_ids': 'Monitored IDs: SpoutUVC, MixUVC, FlowMeter2, BP_12V, BP_UpScreen, BP_LowScreen',
      'rules_door12v_threshold_label': 'Anomaly threshold (below this value)',
      'rules_door12v_condition': 'Trigger condition: ALL 6 IDs must be below threshold simultaneously',
      'rules_door12v_action_realtime': 'Real-time warning: Indigo warning banner on DataStorage and AutoDetection pages',
      'rules_door12v_action_result': 'Detection result: Auto detection marks "Door 12V power anomaly"',
      'rules_polling_section': 'Polling Mechanism',
      'rules_polling_retry_title': 'Data Read Retry',
      'rules_polling_retry_desc': 'Retry mechanism when an ID does not receive response',
      'rules_polling_max_retry_label': 'Max retries',
      'rules_polling_hw_wait_label': 'Hardware wait (ms)',

      // Threshold settings
      'threshold_settings': 'Threshold Settings',
      'threshold_settings_desc': 'Configure value ranges for auto detection',
      'idle_threshold': 'Idle Threshold',
      'min_value': 'Min',
      'max_value': 'Max',
      'threshold_range': 'Range',
      'reset_to_defaults': 'Reset to Defaults',
      'reset_all_confirm': 'Are you sure you want to reset all thresholds to defaults?',
      'reset_success': 'Reset to defaults',
      'save_success': 'Settings saved',
      'hardware_threshold': 'Hardware Threshold (ID 0-18)',
      'apply_to_all': 'Apply to All IDs',
      'edit_threshold': 'Edit Threshold',
      'id_label': 'ID {id}',
      'value_out_of_range': 'Value out of range',

    },
  };
}

/// 全域快捷方法，方便使用
String tr(String key) => LocalizationService().tr(key);

/// 全域帶參數翻譯方法
String trParams(String key, Map<String, dynamic> params) =>
    LocalizationService().trParams(key, params);
