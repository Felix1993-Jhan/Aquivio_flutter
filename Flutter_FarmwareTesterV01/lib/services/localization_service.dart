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
      'page_auto_detection': '自動檢測流程-雙串口',
      'page_command_control': '命令控制',
      'page_data_storage': '資料儲存',
      'page_firmware_upload': '韌體燒錄',
      'page_settings': '設定',

      // 側邊抽屜
      'drawer_title': '自動檢測流程系統',
      'drawer_subtitle': 'Arduino & STM32',
      'connection_status': '連接狀態',

      // 連接相關
      'connected': '已連接',
      'disconnected': '未連接',
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

      // STM32 相關
      'stm32_control': 'STM32U073MCT6',
      'stm32_connected': 'STM32 已連接',
      'stm32_disconnected': 'STM32 已斷開',
      'stm32_connect_failed': 'STM32 連接失敗，請稍後再試',
      'stm32_port_in_use': '此串口已被 Arduino 使用',
      'select_stm32_port': '請先選擇 STM32 串口',
      'connect_stm32_first': '請先連接 STM32',
      'stm32_usb_removed': 'STM32 USB 已拔除，連接已自動關閉',
      'stm32_wrong_port': '連接的 COM 埠不是 STM32\n請選擇正確的 COM 埠',
      'stm32_connection_error': 'STM32 連接可能已斷開\n或連接錯誤',
      'firmware_version': '韌體版本',

      // COM 埠相關
      'no_com_port': '未偵測到任何 COM 埠，請檢查 USB 連接',
      'com_port_detected': '偵測到 {count} 個 COM 埠',
      'new_com_port_detected': '偵測到新 COM 埠: {ports}',

      // 硬體狀態
      'hardware_idle': '硬體無動作 (Idle)',
      'hardware_running': '硬體動作中 (Running)',
      'sensor_detection': '感應偵測',

      // 資料儲存頁面
      'arduino_data': 'Arduino 數據',
      'stm32_data': 'STM32 數據',
      'hardware_data': '硬體數據',
      'sensor_data': '感測器數據',
      'batch_read': '一鍵讀取',
      'stop': '停止',
      'stm32_output_control': 'STM32 輸出控制',
      'open_all_outputs': '開啟全部的輸出',
      'close_all_outputs': '關閉全部的輸出',

      // 表格欄位
      'column_name': '名稱',
      'column_arduino': 'Arduino',
      'column_stm32': 'STM32',
      'column_diff': '差值',
      'column_status': '狀態',

      // 設定頁面
      'settings': '設定',
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
      'cmd_motor': '馬達 (ID 0-9)',
      'cmd_water_pump': '水泵 (ID 10)',
      'cmd_uvc': '紫外燈 (ID 11-13)',
      'cmd_relay': '繼電器 (ID 14-16)',
      'cmd_ozone': '臭氧 (ID 17)',
      'cmd_flow': '流量 (ID 18)',
      'cmd_pressure': '壓力 (ID 19-20)',
      'cmd_temperature': '溫度 (ID 21)',

      // STM32 面板
      'command_mode': '命令模式:',
      'mode_start': '啟動 (0x01)',
      'mode_stop': '停止 (0x02)',
      'mode_read': '讀取 (0x03)',
      'id_select_single': 'ID 選擇 (單選):',
      'id_select_multi': 'ID 選擇 (可多選):',
      'select_all': '全選',
      'select_id_to_preview': '請選擇 ID 以預覽命令',
      'command_preview': '命令預覽 (含 Header + CS):',
      'send_start_cmd': '發送啟動命令',
      'send_stop_cmd': '發送停止命令',
      'send_read_cmd': '發送讀取命令',
      'clear_flow': '清Flow',
      'custom_payload': '自訂 Payload',
      'hex_example': '16進制，例: 01 00 04 00 00',

      // 連接過程訊息
      'stm32_firmware_version': 'STM32 韌體版本: {version}',
      'arduino_connecting': 'Arduino 連接中... ({current}/{max})',
      'stm32_connecting': 'STM32 連接中... ({current}/{max})',
      'stm32_verifying': 'STM32 連接中，驗證裝置...',
      'sent_arduino_command': '已發送 Arduino 指令: {command}',
      'sent_stm32_read_command': '已發送 STM32 讀取指令: ID {id}',
      'all_outputs_toggled': '已{action}全部輸出',
      'output_opened': '開啟',
      'output_closed': '關閉',

      // 錯誤訊息
      'enter_payload': '請輸入 payload (不含 header 和 CS)',
      'hex_length_error': '16進制字串長度必須為偶數',
      'parse_error': '解析錯誤: {error}',

      // 自動檢測流程
      'auto_detection_start': '自動檢測開始',
      'auto_detection_running': '自動檢測進行中...',
      'auto_detection_step_connect': '步驟 1/6: 連接設備',
      'auto_detection_step_idle': '步驟 2/6: 讀取無動作狀態',
      'auto_detection_step_running': '步驟 3/6: 讀取動作中狀態',
      'auto_detection_step_close': '步驟 4/6: 關閉輸出',
      'auto_detection_step_sensor': '步驟 5/6: 感測器測試',
      'auto_detection_step_result': '步驟 6/6: 結果判定',
      'test_result_pass': '通過',
      'test_result_fail': '異常',
      'test_all_passed': '所有項目檢測通過',
      'test_failed_items': '以下項目異常:',
      'usb_not_connected': '請將 USB 接上電腦',
      'retry_step': '重試中 ({current}/{max})...',
      'auto_detection_cancelled': '自動檢測已取消',
      'connecting_arduino': '正在連接 Arduino...',
      'connecting_stm32': '正在連接 STM32...',
      'reading_hardware_data': '讀取硬體數據...',
      'starting_flow_test': '啟動流量計測試...',
      'stopping_flow_test': '停止流量計測試...',

      // 閾值設定
      'threshold_settings': '閾值設定',
      'threshold_settings_desc': '設定自動檢測的數值範圍',
      'arduino_idle_threshold': 'Arduino 無動作閾值',
      'arduino_running_threshold': 'Arduino 動作中閾值',
      'stm32_idle_threshold': 'STM32 無動作閾值',
      'stm32_running_threshold': 'STM32 動作中閾值',
      'idle_threshold': '無動作閾值',
      'running_threshold': '動作中閾值',
      'sensor_threshold': '感測器閾值',
      'diff_threshold': '差值閾值',
      'min_value': '最小值',
      'max_value': '最大值',
      'threshold_range': '範圍',
      'reset_to_defaults': '恢復初始設定',
      'reset_all_confirm': '確定要恢復所有閾值為初始設定嗎？',
      'reset_success': '已恢復初始設定',
      'save_success': '設定已儲存',
      'hardware_threshold': '硬體閾值 (ID 0-17)',
      'apply_to_all': '套用到所有 ID',
      'edit_threshold': '編輯閾值',
      'id_label': 'ID {id}',
      'value_out_of_range': '數值超出範圍',

      // 韌體燒錄頁面
      'firmware_upload': '韌體燒錄',
      'checking_stlink': '檢查 ST-Link 連接...',
      'stlink_connected': 'ST-Link 已連接',
      'stlink_not_connected': 'ST-Link 未連接',
      'refresh_stlink': '刷新 ST-Link 狀態',
      'cli_not_found': '找不到 STM32CubeProgrammer CLI',
      'cli_not_found_hint': '請確認已安裝 STM32CubeProgrammer，CLI 工具應位於以下路徑：',
      'status': '狀態',
      'not_connected': '未連接',
      'version': '版本',
      'serial_number': '序號',
      'firmware_file': '韌體檔案',
      'click_to_select': '點擊選擇韌體檔案',
      'select_firmware_file': '選擇韌體檔案',
      'supported_formats': '支援格式: .elf, .bin, .hex',
      'program_options': '燒錄選項',
      'verify_after_program': '燒錄後驗證',
      'verify_hint': '驗證寫入的資料是否正確',
      'reset_after_program': '燒錄後重置',
      'reset_hint': '燒錄完成後自動重置 MCU',
      'program_firmware': '燒錄韌體',
      'programming': '燒錄中...',
      'please_select_firmware': '請先選擇韌體檔案',
      'starting_program': '開始燒錄...',
      'waiting_stm32_startup': '等待 STM32 啟動中...',
      'program_success': '韌體燒錄成功',
      'erase': '擦除',
      'reset': '重置',
      'confirm_erase': '確認擦除',
      'erase_warning': '這將擦除 STM32 上的所有韌體，確定要繼續嗎？',
      'erasing_flash': '擦除 Flash...',
      'resetting_mcu': '重置 MCU...',
      'progress': '進度',
      'stlink_frequency': 'ST-Link 頻率',
      'stlink_frequency_hint': 'SWD 通訊頻率 (kHz)',
      'cli_output': 'CLI 輸出訊息',
      'select_other_file': '選擇其他檔案...',
      'firmware_folder_hint': '韌體檔案請放置於 firmware 資料夾',
      'connect_mode': '連接模式',
      'connect_mode_hint': 'ST-Link 連接模式設定',
      'reset_mode': '重置模式',
      'reset_mode_hint': 'MCU 重置方式',
      'program_timeout': '燒錄超時',
      'erase_timeout': '擦除超時',
      'reset_timeout': '重置超時',
      'check_timeout': '連接檢查超時',
      'disconnecting_stm32_for_program': '燒錄前斷開 STM32 連線...',

      // 燒錄結果訊息
      'program_success_retry': '韌體燒錄成功（第 {attempt} 次嘗試，頻率 {frequency} kHz）',
      'program_timeout_error': '燒錄超時 (120秒)',
      'firmware_file_not_found': '韌體檔案不存在',
      'unsupported_file_format': '不支援的檔案格式: .{extension}',
      'stlink_not_detected': 'ST-Link 未連接',
      'target_not_connected': '目標 MCU 未連接',
      'flash_erase_failed': 'Flash 擦除失敗',
      'program_failed': '燒錄失敗',
      'execution_error': '執行錯誤',
      'erase_timeout_error': '擦除超時 (60秒)',
      'erase_completed': '擦除完成',
      'erase_failed': '擦除失敗',
      'erase_error': '擦除錯誤',
      'mcu_reset_timeout_error': '重置超時 (30秒)',
      'mcu_reset_completed': 'MCU 重置完成',
      'mcu_reset_failed': 'MCU 重置失敗',
      'mcu_reset_error': 'MCU 重置錯誤',

      // ST-Link 燒入控制區
      'no_firmware_files': '無韌體檔案',
      'select_firmware': '選擇韌體',
      'program_and_detect': '燒入並檢測',
    },

    // ==================== English ====================
    AppLanguage.en: {
      // App title
      'app_title': 'Command Control',

      // Page titles
      'page_auto_detection': 'Auto Detection - Dual Serial',
      'page_command_control': 'Command Control',
      'page_data_storage': 'Data Storage',
      'page_firmware_upload': 'Firmware Upload',
      'page_settings': 'Settings',

      // Drawer
      'drawer_title': 'Auto Detection System',
      'drawer_subtitle': 'Arduino & STM32',
      'connection_status': 'Connection Status',

      // Connection related
      'connected': 'Connected',
      'disconnected': 'Disconnected',
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

      // STM32 related
      'stm32_control': 'STM32U073MCT6',
      'stm32_connected': 'STM32 Connected',
      'stm32_disconnected': 'STM32 Disconnected',
      'stm32_connect_failed': 'STM32 connection failed, please try again',
      'stm32_port_in_use': 'This port is already used by Arduino',
      'select_stm32_port': 'Please select STM32 port first',
      'connect_stm32_first': 'Please connect STM32 first',
      'stm32_usb_removed': 'STM32 USB removed, connection closed',
      'stm32_wrong_port': 'Connected COM port is not STM32\nPlease select correct COM port',
      'stm32_connection_error': 'STM32 connection may be lost\nor connection error',
      'firmware_version': 'Firmware Version',

      // COM port related
      'no_com_port': 'No COM port detected, please check USB connection',
      'com_port_detected': 'Detected {count} COM port(s)',
      'new_com_port_detected': 'New COM port detected: {ports}',

      // Hardware status
      'hardware_idle': 'Hardware Idle',
      'hardware_running': 'Hardware Running',
      'sensor_detection': 'Sensor Detection',

      // Data storage page
      'arduino_data': 'Arduino Data',
      'stm32_data': 'STM32 Data',
      'hardware_data': 'Hardware Data',
      'sensor_data': 'Sensor Data',
      'batch_read': 'Batch Read',
      'stop': 'Stop',
      'stm32_output_control': 'STM32 Output Control',
      'open_all_outputs': 'Open All Outputs',
      'close_all_outputs': 'Close All Outputs',

      // Table columns
      'column_name': 'Name',
      'column_arduino': 'Arduino',
      'column_stm32': 'STM32',
      'column_diff': 'Diff',
      'column_status': 'Status',

      // Settings page
      'settings': 'Settings',
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
      'cmd_motor': 'Motor (ID 0-9)',
      'cmd_water_pump': 'Water Pump (ID 10)',
      'cmd_uvc': 'UVC (ID 11-13)',
      'cmd_relay': 'Relay (ID 14-16)',
      'cmd_ozone': 'Ozone (ID 17)',
      'cmd_flow': 'Flow (ID 18)',
      'cmd_pressure': 'Pressure (ID 19-20)',
      'cmd_temperature': 'Temp (ID 21)',

      // STM32 panel
      'command_mode': 'Command Mode:',
      'mode_start': 'Start (0x01)',
      'mode_stop': 'Stop (0x02)',
      'mode_read': 'Read (0x03)',
      'id_select_single': 'ID Select (Single):',
      'id_select_multi': 'ID Select (Multi):',
      'select_all': 'All',
      'select_id_to_preview': 'Select ID to preview command',
      'command_preview': 'Command Preview (with Header + CS):',
      'send_start_cmd': 'Send Start Command',
      'send_stop_cmd': 'Send Stop Command',
      'send_read_cmd': 'Send Read Command',
      'clear_flow': 'ClearFlow',
      'custom_payload': 'Custom Payload',
      'hex_example': 'Hex, e.g.: 01 00 04 00 00',

      // Connection process messages
      'stm32_firmware_version': 'STM32 Firmware: {version}',
      'arduino_connecting': 'Arduino connecting... ({current}/{max})',
      'stm32_connecting': 'STM32 connecting... ({current}/{max})',
      'stm32_verifying': 'STM32 connecting, verifying device...',
      'sent_arduino_command': 'Sent Arduino command: {command}',
      'sent_stm32_read_command': 'Sent STM32 read command: ID {id}',
      'all_outputs_toggled': 'All outputs {action}',
      'output_opened': 'opened',
      'output_closed': 'closed',

      // Error messages
      'enter_payload': 'Enter payload (without header and CS)',
      'hex_length_error': 'Hex string length must be even',
      'parse_error': 'Parse error: {error}',

      // Auto detection process
      'auto_detection_start': 'Start Auto Detection',
      'auto_detection_running': 'Auto Detection in Progress...',
      'auto_detection_step_connect': 'Step 1/6: Connecting Devices',
      'auto_detection_step_idle': 'Step 2/6: Reading Idle State',
      'auto_detection_step_running': 'Step 3/6: Reading Running State',
      'auto_detection_step_close': 'Step 4/6: Closing Outputs',
      'auto_detection_step_sensor': 'Step 5/6: Sensor Test',
      'auto_detection_step_result': 'Step 6/6: Result Check',
      'test_result_pass': 'Pass',
      'test_result_fail': 'Error',
      'test_all_passed': 'All items passed',
      'test_failed_items': 'Failed items:',
      'usb_not_connected': 'Please connect USB to computer',
      'retry_step': 'Retrying ({current}/{max})...',
      'auto_detection_cancelled': 'Auto detection cancelled',
      'connecting_arduino': 'Connecting Arduino...',
      'connecting_stm32': 'Connecting STM32...',
      'reading_hardware_data': 'Reading hardware data...',
      'starting_flow_test': 'Starting flow test...',
      'stopping_flow_test': 'Stopping flow test...',

      // Threshold settings
      'threshold_settings': 'Threshold Settings',
      'threshold_settings_desc': 'Configure value ranges for auto detection',
      'arduino_idle_threshold': 'Arduino Idle Threshold',
      'arduino_running_threshold': 'Arduino Running Threshold',
      'stm32_idle_threshold': 'STM32 Idle Threshold',
      'stm32_running_threshold': 'STM32 Running Threshold',
      'idle_threshold': 'Idle Threshold',
      'running_threshold': 'Running Threshold',
      'sensor_threshold': 'Sensor Threshold',
      'diff_threshold': 'Difference Threshold',
      'min_value': 'Min',
      'max_value': 'Max',
      'threshold_range': 'Range',
      'reset_to_defaults': 'Reset to Defaults',
      'reset_all_confirm': 'Are you sure you want to reset all thresholds to defaults?',
      'reset_success': 'Reset to defaults',
      'save_success': 'Settings saved',
      'hardware_threshold': 'Hardware Threshold (ID 0-17)',
      'apply_to_all': 'Apply to All IDs',
      'edit_threshold': 'Edit Threshold',
      'id_label': 'ID {id}',
      'value_out_of_range': 'Value out of range',

      // Firmware upload page
      'firmware_upload': 'Firmware Upload',
      'checking_stlink': 'Checking ST-Link connection...',
      'stlink_connected': 'ST-Link Connected',
      'stlink_not_connected': 'ST-Link Not Connected',
      'refresh_stlink': 'Refresh ST-Link Status',
      'cli_not_found': 'STM32CubeProgrammer CLI Not Found',
      'cli_not_found_hint': 'Please ensure STM32CubeProgrammer is installed. CLI tool should be at:',
      'status': 'Status',
      'not_connected': 'Not Connected',
      'version': 'Version',
      'serial_number': 'Serial Number',
      'firmware_file': 'Firmware File',
      'click_to_select': 'Click to select firmware file',
      'select_firmware_file': 'Select Firmware File',
      'supported_formats': 'Supported formats: .elf, .bin, .hex',
      'program_options': 'Program Options',
      'verify_after_program': 'Verify After Program',
      'verify_hint': 'Verify that written data is correct',
      'reset_after_program': 'Reset After Program',
      'reset_hint': 'Automatically reset MCU after programming',
      'program_firmware': 'Program Firmware',
      'programming': 'Programming...',
      'please_select_firmware': 'Please select a firmware file first',
      'starting_program': 'Starting programming...',
      'waiting_stm32_startup': 'Waiting for STM32 startup...',
      'program_success': 'Firmware programmed successfully',
      'erase': 'Erase',
      'reset': 'Reset',
      'confirm_erase': 'Confirm Erase',
      'erase_warning': 'This will erase all firmware on STM32. Are you sure?',
      'erasing_flash': 'Erasing Flash...',
      'resetting_mcu': 'Resetting MCU...',
      'progress': 'Progress',
      'stlink_frequency': 'ST-Link Frequency',
      'stlink_frequency_hint': 'SWD communication frequency (kHz)',
      'cli_output': 'CLI Output',
      'select_other_file': 'Select other file...',
      'firmware_folder_hint': 'Place firmware files in the firmware folder',
      'connect_mode': 'Connect Mode',
      'connect_mode_hint': 'ST-Link connection mode',
      'reset_mode': 'Reset Mode',
      'reset_mode_hint': 'MCU reset method',
      'program_timeout': 'Program Timeout',
      'erase_timeout': 'Erase Timeout',
      'reset_timeout': 'Reset Timeout',
      'check_timeout': 'Connection Check Timeout',
      'disconnecting_stm32_for_program': 'Disconnecting STM32 before programming...',

      // Programming result messages
      'program_success_retry': 'Firmware programmed successfully (attempt {attempt}, {frequency} kHz)',
      'program_timeout_error': 'Program timeout (120s)',
      'firmware_file_not_found': 'Firmware file not found',
      'unsupported_file_format': 'Unsupported file format: .{extension}',
      'stlink_not_detected': 'ST-Link not connected',
      'target_not_connected': 'Target MCU not connected',
      'flash_erase_failed': 'Flash erase failed',
      'program_failed': 'Program failed',
      'execution_error': 'Execution error',
      'erase_timeout_error': 'Erase timeout (60s)',
      'erase_completed': 'Erase completed',
      'erase_failed': 'Erase failed',
      'erase_error': 'Erase error',
      'mcu_reset_timeout_error': 'Reset timeout (30s)',
      'mcu_reset_completed': 'MCU reset completed',
      'mcu_reset_failed': 'MCU reset failed',
      'mcu_reset_error': 'MCU reset error',

      // ST-Link programming control bar
      'no_firmware_files': 'No firmware files',
      'select_firmware': 'Select firmware',
      'program_and_detect': 'Program & Detect',
    },
  };
}

/// 全域快捷方法，方便使用
String tr(String key) => LocalizationService().tr(key);

/// 全域帶參數翻譯方法
String trParams(String key, Map<String, dynamic> params) =>
    LocalizationService().trParams(key, params);
