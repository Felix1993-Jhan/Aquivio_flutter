# BodyDoor Tester V01

## 專案概述

Flutter Windows 桌面應用程式，用於 BodyDoor 測試治具操作。
透過 Arduino USB 串口通訊讀取 19 個 ADC 通道 (ID 0-18)，進行自動檢測與 Pass/Fail 判定。

## 建置指令

```bash
# 建置 Windows Release
c:/flutter/flutter/bin/flutter.bat build windows

# 清除快取後重建（遇到 ephemeral C++ 檔案錯誤時使用）
c:/flutter/flutter/bin/flutter.bat clean && c:/flutter/flutter/bin/flutter.bat pub get && c:/flutter/flutter/bin/flutter.bat build windows
```

## 專案架構

```
lib/
├── main.dart                              # 主程式入口、MainNavigationPage（含 IndexedStack 頁面管理）
├── controllers/
│   ├── auto_detection_controller.dart     # 自動檢測流程 Mixin（連接 → 讀取 → 判定）
│   └── serial_controller.dart             # Arduino 串口操作 Mixin（連線/斷線/重試）
├── services/
│   ├── serial_port_manager.dart           # 串口管理（開啟/關閉/收發/心跳機制/資料解析）
│   ├── data_storage_service.dart          # 數據儲存（Arduino Idle/Running 資料分開存放）
│   ├── threshold_settings_service.dart    # 閾值設定（SharedPreferences 持久化）
│   ├── localization_service.dart          # 多語系（繁體中文/English）
│   └── adjacent_pins_service.dart         # STM32 GPIO 相鄰腳位對照表
└── widgets/
    ├── auto_detection_page.dart           # 自動檢測頁面（19 通道數據表 + Pass/Fail 狀態燈）
    ├── arduino_panel.dart                 # Arduino 命令控制面板（翡翠綠主題）
    ├── data_storage_page.dart             # 數據顯示頁面（左 Idle / 右 Running）
    ├── detection_rules_page.dart          # 檢測規則設定（閾值編輯/電源異常偵測）
    ├── settings_page.dart                 # 設定頁面（語言切換/閾值設定）
    ├── splash_screen.dart                 # 啟動畫面
    └── ui_dialogs.dart                    # 共用對話框元件
```

## 關鍵設計

### 頁面管理
- 使用 `IndexedStack` 保留所有頁面狀態，避免切換時重建
- Drawer 切換：先關閉 Drawer，延遲 250ms 後 setState 切換頁面
- AppBar 訊息使用 `ValueNotifier<String>` + `ValueListenableBuilder` 避免全頁 setState

### Arduino 通訊
- 串口：115200, 8N1, DTR/RTS off
- 心跳機制：每秒發送 `connect`，期望回傳 `connected`，連續 3 次失敗視為斷線
- 資料格式：`名稱(腳位): 數值`，例如 `AmbientRL(A0): 1023`
- 讀取定時器：每 50ms 輪詢串口

### BodyDoor 硬體通道 (ID 0-18)
- ID 0-14：直接 ADC 感測器 (A0-A14)
- ID 15-18：BodyPower 透過 4051 多工器 (A15, CH4-CH7)
- 只讀取 Idle 狀態，無 Running / MOSFET 測試

### 閾值驗證
- 每個 ID 有獨立的 min/max 範圍
- 電源異常偵測：3.3V / Body 12V / Door 24V / Door 12V
- 所有閾值可透過 UI 編輯，持久化至 SharedPreferences

## 注意事項

- 所有 UI 文字和註解使用**繁體中文**
- Windows 建置遇到 `ephemeral/cpp_client_wrapper` 錯誤時，需要 `flutter clean` 後重建
- `ThresholdSettingsService` 的 `_arduinoIdleThresholds` 使用直接初始化（非 late），因為 IndexedStack 會立即建構所有子頁面
- 與使用者對話時全程使用**繁體中文**回應，包含技術說明與解釋，避免中途切換成英文（專有名詞、程式碼、變數名稱除外）