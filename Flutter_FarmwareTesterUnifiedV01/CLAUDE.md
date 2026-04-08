# 專案規範

## 撰寫規範

- 所有程式碼註解與修改說明使用**繁體中文**
- commit 訊息使用繁體中文描述修改內容
- 與使用者對話時全程使用**繁體中文**回應（專有名詞、程式碼、變數名稱除外）

---

## 專案概述

**Firmware Tester Unified** — Flutter Windows/Linux 桌面應用，硬體韌體測試治具上位機。
兩種測試模式：**Main Board**（主板）與 **Body&Door Board**（車身&門板），透過串口與 Arduino / STM32 通訊。

流程：`main.dart → SplashScreen (3秒) → ModeSelectionPage (自動偵測) → MainNavigationPage / BodyDoorNavigationPage`

- Arduino 回傳 `"connectedmain"` → Main Board 模式
- Arduino 回傳 `"connectedbodydoor"` → Body&Door Board 模式

---

## 目錄結構

```
lib/
├── main.dart                    # 入口，視窗初始化
├── mode_selection_page.dart     # 模式選擇，自動偵測 Arduino
├── config/app_mode.dart         # AppMode 列舉
├── main_mode/                   # Main Board 模式（詳見 main_mode/CLAUDE.md）
├── bodydoor_mode/               # Body&Door 模式（詳見 bodydoor_mode/CLAUDE.md）
└── shared/                      # 共用模組
    ├── language_state.dart           # globalLanguageNotifier
    ├── services/
    │   ├── data_storage_service.dart       # ADC 數值 + 硬體狀態
    │   ├── arduino_connection_service.dart # Arduino 連線驗證 Mixin
    │   ├── port_filter_service.dart        # COM 埠過濾（排除 ST-Link）
    │   └── localization_service.dart       # 多語系（繁中/英文）
    └── widgets/
        ├── splash_screen.dart              # 啟動畫面
        └── arduino_panel.dart              # Arduino 串口面板
```

---

## 架構設計

### Mixin 模式

`NavigationPage` 透過 Mixin 組合功能，每個 Mixin 定義抽象成員由 NavigationPage 實作。

| Mixin | Main Board | BodyDoor | 功能 |
|-------|-----------|----------|------|
| `SerialController` | Arduino + STM32 | 僅 Arduino | 連線/指令/流量控制 |
| `AutoDetectionController` | Arduino + STM32 | 僅 Arduino | 自動偵測連接 |
| `FirmwareController` | 有 | 無 | ST-Link 韌體燒錄 |
| `ArduinoConnectionMixin` | 有 | 有 | 共用 Arduino 連線驗證 |

### 兩種模式差異

| 項目 | Main Board | Body&Door Board |
|------|-----------|----------------|
| 串口數量 | 2（Arduino + STM32） | 1（僅 Arduino） |
| ADC 通道數 | 24 (ID 0-23) | 19 (ID 0-18) |
| STM32 通訊 | 二進位協定 | 無 |
| 韌體燒錄 | 支援 (ST-Link) | 不支援 |
| 心跳識別 | `"connectedmain"` | `"connectedbodydoor"` |
| 頁面數量 | 6 頁 | 4 頁 |

---

## 共用服務

- **ArduinoConnectionMixin** — `connectAndVerify()` 統一連線驗證，回傳 `success`/`wrongMode`/`failed`/`portError`
- **PortFilterService** — 透過 USB VID (0x0483) 識別並排除 ST-Link 設備
- **LocalizationService** — `tr(key)` 多語系翻譯，`globalLanguageNotifier` 跨模式同步
- **DataStorageService** — ADC 數值 (`ValueNotifier<Map<int, int>>`) + 硬體狀態管理

---

## 通訊協定

### Arduino（文字模式，兩種模式共用）
- 115200 8N1，指令以 `\n` 結尾，心跳每秒發送 `"connect"`
- 數據格式：`"名稱(腳位): 數值"`

### STM32（二進位模式，僅 Main Board）
- 115200 8N1，`URCommandBuilder` 建構指令：`[0x40, 0x71, 0x30, payload..., checksum]`
- 指令：`0x01` ON / `0x02` OFF / `0x03` 讀ADC / `0x04` 清除 / `0x05` 韌體版本

---

## 開發注意事項

- **平台**：Windows + Linux（依賴 `flutter_libserialport` + `window_manager`）
- **SDK**：Flutter ^3.10.4
- **建構**：`flutter build windows --release` / `flutter build linux --release`
- **分析**：`flutter analyze`（忽略 `unnecessary_null_comparison`、`unintended_html_in_doc_comment`）
- **串口安全**：所有串口操作 try-catch 保護，USB 拔除自動斷線
- **導航**：`Navigator.pushReplacement` 避免堆疊
- **依賴**：`flutter_libserialport` ^0.6.0 / `shared_preferences` ^2.2.2 / `window_manager` ^0.4.3 / `file_picker` ^8.0.0
- **Monorepo**：位於 `Aquivio_flutter/Flutter_FarmwareTesterUnifiedV01/`，GitHub Actions 自動建構 Windows + Linux