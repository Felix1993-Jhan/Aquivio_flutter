# 專案規範

## 撰寫規範

- 所有程式碼註解與修改說明使用**繁體中文**
- commit 訊息使用繁體中文描述修改內容
- 與使用者對話時全程使用**繁體中文**回應，包含技術說明與解釋，避免中途切換成英文（專有名詞、程式碼、變數名稱除外）

---

## 專案概述

**Firmware Tester Unified** 是一套 Flutter Windows 桌面應用程式，用於硬體韌體測試治具的上位機操作。
統一管理兩種測試模式：**Main Board**（主板）與 **Body&Door Board**（車身&門板），透過串口與 Arduino / STM32 微控制器通訊，執行 ADC 感測器讀取、MOSFET 輸出控制、韌體燒錄等測試流程。

### 應用程式流程

```
main.dart → SplashScreen (3 秒) → ModeSelectionPage (自動偵測 Arduino) → MainNavigationPage / BodyDoorNavigationPage
```

- `ModeSelectionPage` 自動掃描所有 COM 埠，發送 `"connect"` 指令
- Arduino 回傳 `"connectedmain"` → 進入 Main Board 模式
- Arduino 回傳 `"connectedbodydoor"` → 進入 Body&Door Board 模式
- 偵測到錯誤模式時，支援直接切換到正確模式（不經模式選擇頁）

---

## 目錄結構

```
lib/
├── main.dart                          # 應用程式入口，視窗初始化
├── mode_selection_page.dart           # 模式選擇頁，自動偵測 Arduino 韌體類型
├── config/
│   └── app_mode.dart                  # AppMode 列舉 (main / bodyDoor)
├── main_mode/                         # ===== Main Board 模式 =====
│   ├── main_navigation_page.dart      # 主導航頁面 (StatefulWidget + Mixins)
│   ├── controllers/
│   │   ├── auto_detection_controller.dart  # 自動偵測流程 Mixin
│   │   ├── serial_controller.dart          # 串口操作 Mixin (Arduino + STM32)
│   │   └── firmware_controller.dart        # 韌體燒錄控制 Mixin
│   ├── services/
│   │   ├── serial_port_manager.dart        # 串口管理 (文字 + 二進位雙模式)
│   │   ├── ur_command_builder.dart         # STM32 二進位指令建構器
│   │   ├── threshold_settings_service.dart # ADC 閾值設定持久化
│   │   ├── adjacent_pins_service.dart      # 相鄰腳位短路偵測
│   │   ├── stlink_programmer_service.dart  # ST-Link 韌體燒錄
│   │   └── cli_checker_service.dart        # CLI 工具檢查
│   └── widgets/
│       ├── auto_detection_page.dart        # 自動偵測頁面
│       ├── operation_page.dart             # 手動操作頁面
│       ├── data_storage_page.dart          # 數據儲存/匯出頁面
│       ├── detection_rules_page.dart       # 偵測規則設定頁面
│       ├── settings_page.dart              # 設定頁面 (閾值/語言)
│       ├── firmware_upload_page.dart       # 韌體上傳頁面
│       ├── ur_panel.dart                   # STM32 串口面板
│       ├── ui_dialogs.dart                 # 共用對話框
│       └── cli_check_dialog.dart           # CLI 工具檢查對話框
├── bodydoor_mode/                     # ===== Body&Door Board 模式 =====
│   ├── bodydoor_navigation_page.dart  # 主導航頁面
│   ├── controllers/
│   │   ├── auto_detection_controller.dart  # 自動偵測流程 Mixin
│   │   └── serial_controller.dart          # 串口操作 Mixin (僅 Arduino)
│   ├── services/
│   │   ├── serial_port_manager.dart        # 串口管理 (僅文字模式)
│   │   └── threshold_settings_service.dart # ADC 閾值設定持久化
│   └── widgets/
│       ├── auto_detection_page.dart        # 自動偵測頁面
│       ├── data_storage_page.dart          # 數據儲存/匯出頁面
│       ├── detection_rules_page.dart       # 偵測規則設定頁面
│       ├── settings_page.dart              # 設定頁面
│       └── ui_dialogs.dart                 # 共用對話框
└── shared/                            # ===== 共用模組 =====
    ├── language_state.dart            # 全域語言狀態 (globalLanguageNotifier)
    ├── services/
    │   ├── data_storage_service.dart       # 數據儲存服務 (ADC 數值 + 硬體狀態)
    │   ├── arduino_connection_service.dart # Arduino 連線驗證 Mixin + 列舉定義
    │   ├── port_filter_service.dart        # COM 埠過濾服務 (排除 ST-Link)
    │   └── localization_service.dart       # 多語系翻譯服務 (繁中/英文)
    └── widgets/
        ├── splash_screen.dart              # 啟動畫面
        └── arduino_panel.dart              # Arduino 串口面板（共用元件）
```

---

## 架構設計

### Mixin 模式

`NavigationPage` 是各模式的核心 StatefulWidget，透過 Mixin 組合功能：

```dart
class _MainNavigationPageState extends State<MainNavigationPage>
    with SerialController, AutoDetectionController, FirmwareController {
  // Mixin 提供各自的操作邏輯
  // NavigationPage 實作 Mixin 所需的抽象成員
}
```

| Mixin | Main Board | BodyDoor | 功能 |
|-------|-----------|----------|------|
| `SerialController` | Arduino + STM32 | 僅 Arduino | 連線/斷線/指令發送/流量控制 |
| `AutoDetectionController` | 掃描 Arduino + STM32 | 僅掃描 Arduino | 自動偵測並連接裝置 |
| `FirmwareController` | 有 | 無 | ST-Link 韌體燒錄 |
| `ArduinoConnectionMixin` | 有 | 有 | 共用的 Arduino 連線驗證邏輯 |

每個 Mixin 定義需由 NavigationPage 實作的抽象成員（getter / setter / callback），例如：
- `SerialPortManager get arduinoManager;`
- `void showSnackBarMessage(String message);`
- `void onWrongModeDetected(String portName);`

### 兩種模式差異

| 項目 | Main Board | Body&Door Board |
|------|-----------|----------------|
| 串口數量 | 2（Arduino + STM32） | 1（僅 Arduino） |
| ADC 通道數 | 24 (ID 0-23) | 19 (ID 0-18) |
| STM32 通訊 | 二進位協定 (URCommandBuilder) | 無 |
| 韌體燒錄 | 支援 (ST-Link) | 不支援 |
| 流量計控制 | flowon/flowoff + 定時讀取 | 無 |
| 頁面數量 | 6 頁 | 4 頁 |
| 心跳識別字串 | `"connectedmain"` | `"connectedbodydoor"` |

---

## 通訊協定

### Arduino（文字模式）

- 波特率：115200, 8N1, 無流量控制
- 發送指令：以 `\n` 結尾的純文字字串
- 心跳機制：每秒發送 `"connect"`，期望回傳模式識別字串
- 數據回傳格式：`"名稱(腳位): 數值"`，例如 `"AmbientRL(A0): 1234"`

### STM32（二進位模式，僅 Main Board）

- 波特率：115200, 8N1
- 指令格式由 `URCommandBuilder` 建構：`[0x40, 0x71, 0x30, payload..., checksum]`
- 指令類型：
  - `0x01` — 開啟輸出（MOSFET ON）
  - `0x02` — 關閉輸出（MOSFET OFF）
  - `0x03` — 讀取 ADC（帶 sensor ID）
  - `0x04` — 清除數值
  - `0x05` — 讀取韌體版本

### 跨模式偵測

當 Arduino 回傳不屬於當前模式的心跳字串時（例如在 Main 模式下收到 `"connectedbodydoor"`），
`wrongModeDetectedNotifier` 觸發，顯示對話框並支援直接切換到正確模式頁面。

---

## 重要服務

### SerialPortManager

各模式各自擁有獨立的 `SerialPortManager` 實作，透過 `ArduinoConnectionMixin` 共用連線驗證邏輯：
- 串口開啟/關閉/釋放
- 定時輪詢讀取（50ms 間隔）
- 心跳機制（連續 3 次失敗判定斷線）
- 接收緩衝區管理與資料解析
- `ValueNotifier` 通知：`isConnectedNotifier`、`heartbeatOkNotifier`、`wrongModeDetectedNotifier`、`logNotifier`
- Main 版本額外支援：
  - 二進位模式（STM32）
  - `firmwareVersionNotifier`
  - `connectAndVerifyStm32()` 方法

### ArduinoConnectionMixin（shared）

提供統一的 Arduino 連線驗證方法 `connectAndVerify()`：
- 開啟串口並等待初始化
- 發送 `"connect"` 指令並輪詢回應
- 根據回應判斷連線結果：`success`、`wrongMode`、`failed`、`portError`
- 被 Main 和 BodyDoor 的 `SerialPortManager` 共用

### PortFilterService（shared）

提供 COM 埠過濾功能：
- `getAvailablePorts(excludeStLink: true)` — 取得可用埠口，排除 ST-Link VCP
- `getFilteredPorts(excludePorts, excludeStLink)` — 進一步排除指定埠口
- `isStLinkPort(portName)` — 檢查指定埠口是否為 ST-Link
- 透過 USB VID (0x0483) 識別 ST-Link 設備

### LocalizationService（shared）

提供多語系翻譯功能：
- `tr(key)` 函式取得翻譯文字
- 支援繁體中文 (`zh`) 和英文 (`en`)
- 透過 `globalLanguageNotifier` 跨模式同步語言設定

### DataStorageService（shared）

- 儲存所有 ADC 通道數值（`ValueNotifier<Map<int, int>>`）
- 管理硬體狀態（`HardwareState.idle` / `HardwareState.running`）
- 被兩種模式共同使用

### ThresholdSettingsService

- 使用 `shared_preferences` 持久化 ADC 閾值設定
- 各模式各自擁有獨立的實作（不同 sensor 組合）

---

## 連線機制

### 手動連線

按下連線按鈕時，自動掃描所有可用 COM 埠：

```dart
// Arduino 連線（兩種模式皆使用）
Future<void> connectArduino() async {
  final ports = PortFilterService.getAvailablePorts(excludeStLink: true);
  for (final port in ports) {
    final result = await arduinoManager.connectAndVerify(port);
    if (result == ConnectResult.success) return;
  }
}

// STM32 連線（僅 Main 模式）
Future<void> connectUr() async {
  final ports = PortFilterService.getFilteredPorts(
    excludePorts: [selectedArduinoPort],
    excludeStLink: true,
  );
  for (final port in ports) {
    final result = await urManager.connectAndVerifyStm32(port);
    if (result == Stm32ConnectResult.success) return;
  }
}
```

### 自動偵測

自動偵測流程同樣使用 `connectAndVerify()` 和 `connectAndVerifyStm32()`，確保連線邏輯一致。

---

## 依賴套件

| 套件 | 用途 |
|------|------|
| `flutter_libserialport` ^0.6.0 | 串口通訊（底層 libserialport） |
| `shared_preferences` ^2.2.2 | 閾值設定持久化儲存 |
| `window_manager` ^0.4.3 | 視窗尺寸控制（最小 800x600） |
| `file_picker` ^8.0.0 | 韌體檔案選擇（.bin / .hex） |

---

## 開發注意事項

- **平台**：支援 Windows 和 Linux 桌面（依賴 flutter_libserialport 與 window_manager）
- **SDK 版本**：Flutter SDK ^3.10.4
- **建構指令**：
  - Windows: `flutter build windows --release`
  - Linux: `flutter build linux --release`（需在 Linux 環境執行）
- **靜態分析**：`flutter analyze`（已忽略 `unnecessary_null_comparison` 與 `unintended_html_in_doc_comment`）
- **串口安全**：所有串口操作均有 try-catch 保護，USB 拔除時自動觸發斷線處理
- **導航方式**：模式切換使用 `Navigator.pushReplacement` 避免畫面堆疊
- **語言同步**：透過全域 `globalLanguageNotifier`（`ValueNotifier<String>`）跨模式同步語言設定
- **ST-Link 排除**：所有連線掃描功能自動排除 ST-Link VCP 埠口，避免衝突

---

## 跨平台支援

### 平台對應的預設路徑

**STM32CubeProgrammer CLI 路徑** (自動偵測)：
- Windows: `C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe`
- Linux: `/usr/local/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI`
- macOS: `/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI`

### Linux 特殊需求

**串口權限：**
```bash
sudo usermod -a -G dialout $USER
# 登出並重新登入
```

**ST-Link 權限（udev 規則）：**
```bash
sudo nano /etc/udev/rules.d/49-stlinkv2.rules
# 參考 LINUX_DEPLOYMENT.md
```

詳細部署說明：[LINUX_DEPLOYMENT.md](LINUX_DEPLOYMENT.md)

---

## GitHub Actions 自動建構

專案位於 Monorepo 結構中，使用 GitHub Actions 自動建構：

### 儲存庫結構
```
Aquivio_flutter/                              ← Monorepo 根目錄
├── .github/
│   └── workflows/
│       └── Flutter_FarmwareTesterUnifiedV01.yml  ← 此專案的工作流程
├── Flutter_FarmwareTesterUnifiedV01/         ← 本專案（會自動建構）
├── Flutter_FarmwareTestBodyDoorV01/          ← 歷史版本（無自動建構）
└── Flutter_FarmwareTesterV01/                ← 歷史版本（無自動建構）
```

### 觸發條件

工作流程會在以下情況觸發：
1. Push 到 `main` 或 `master` 分支，且修改了以下路徑：
   - `Flutter_FarmwareTesterUnifiedV01/**`
   - `.github/workflows/Flutter_FarmwareTesterUnifiedV01.yml`
2. 手動觸發（workflow_dispatch）

### 建構產物

- **Windows**: `FarmwareTesterUnified-Windows.zip`
- **Linux**: `FarmwareTesterUnified-Linux.zip`
- **保留期限**: 30 天

### 費用消耗

每次建構消耗約 5-10 分鐘的 GitHub Actions 額度：
- Windows runner: 2x 倍率（約 2 分鐘 = 4 分鐘額度）
- Linux runner: 1x 倍率（約 1 分鐘 = 1 分鐘額度）

免費帳號每月 2000 分鐘，足以支援約 200-400 次建構。

---

## 專案定位

本專案為 **Farmware Tester Suite** 的主力版本：

- ✅ **Flutter_FarmwareTesterUnifiedV01** — 整合版（**推薦使用**）
  - 支援 Main Board + Body&Door Board 雙模式
  - 自動偵測並切換模式
  - 完整功能（Arduino + STM32 + ST-Link 燒錄）

- 📦 **Flutter_FarmwareTestBodyDoorV01** — Body&Door Board 獨立版（歷史版本）
  - 已整合至 Unified 版本
  - 保留作為參考

- 📦 **Flutter_FarmwareTesterV01** — Main Board 獨立版（歷史版本）
  - 已整合至 Unified 版本
  - 保留作為參考

**建議使用者直接下載 Unified 版本，享受完整功能與持續更新支援。**
