# 路徑引導

本文件整理專案所有關鍵檔案與資料夾的路徑，方便快速定位。

---

## AI 文件索引

| 文件 | 路徑 | 說明 |
|------|------|------|
| 專案總規範 | `CLAUDE.md`（根目錄） | Claude Code 自動載入的專案指引 |
| Main Board 模式文件 | `aidocs/main_mode.md` | Main Board 架構、通訊、韌體燒錄 |
| Body&Door 模式文件 | `aidocs/bodydoor_mode.md` | Body&Door 架構、連線機制 |
| 串口通訊協定 | `aidocs/serial_protocol.md` | Arduino/STM32 完整協定、封包格式、ADC 對應表、快速開發參考 |
| 路徑引導（本文件） | `aidocs/path_guide.md` | 專案路徑總覽 |

---

## 專案入口與核心流程

| 檔案 | 路徑 | 說明 |
|------|------|------|
| 應用入口 | `lib/main.dart` | 視窗初始化、啟動應用 |
| 模式選擇頁 | `lib/mode_selection_page.dart` | 自動偵測 Arduino，進入對應模式 |
| 啟動畫面 | `lib/shared/widgets/splash_screen.dart` | 3 秒啟動動畫 |
| 模式列舉 | `lib/config/app_mode.dart` | `AppMode.mainBoard` / `AppMode.bodyDoor` |

---

## Main Board 模式（`lib/main_mode/`）

### 主頁面
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 導航主頁 | `lib/main_mode/main_navigation_page.dart` | StatefulWidget + Mixins 組合 |

### Controllers（Mixin）
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 串口控制 | `lib/main_mode/controllers/serial_controller.dart` | Arduino + STM32 連線/指令/流量控制 |
| 自動偵測 | `lib/main_mode/controllers/auto_detection_controller.dart` | 掃描 Arduino + STM32 自動連接 |
| 韌體控制 | `lib/main_mode/controllers/firmware_controller.dart` | ST-Link 韌體燒錄控制 |

### Services
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 串口管理 | `lib/main_mode/services/serial_port_manager.dart` | 文字 + 二進位雙模式 |
| STM32 指令 | `lib/main_mode/services/ur_command_builder.dart` | 二進位指令建構器 |
| 閾值設定 | `lib/main_mode/services/threshold_settings_service.dart` | ADC 閾值持久化 |
| 相鄰腳位偵測 | `lib/main_mode/services/adjacent_pins_service.dart` | 短路偵測邏輯 |
| ST-Link 燒錄 | `lib/main_mode/services/stlink_programmer_service.dart` | 呼叫 STM32CubeProgrammer CLI |
| CLI 檢查 | `lib/main_mode/services/cli_checker_service.dart` | 檢查燒錄工具是否安裝 |

### Widgets（頁面）
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 自動偵測頁 | `lib/main_mode/widgets/auto_detection_page.dart` | 自動偵測 UI |
| 手動操作頁 | `lib/main_mode/widgets/operation_page.dart` | 手動操作 MOSFET/ADC |
| 數據儲存頁 | `lib/main_mode/widgets/data_storage_page.dart` | 數據匯出 |
| 偵測規則頁 | `lib/main_mode/widgets/detection_rules_page.dart` | 偵測規則設定 |
| 設定頁 | `lib/main_mode/widgets/settings_page.dart` | 閾值/語言設定 |
| 韌體上傳頁 | `lib/main_mode/widgets/firmware_upload_page.dart` | 韌體檔案上傳 |
| STM32 面板 | `lib/main_mode/widgets/ur_panel.dart` | STM32 串口操作面板 |
| 對話框 | `lib/main_mode/widgets/ui_dialogs.dart` | 共用對話框元件 |
| CLI 對話框 | `lib/main_mode/widgets/cli_check_dialog.dart` | CLI 工具檢查對話框 |

---

## Body&Door Board 模式（`lib/bodydoor_mode/`）

### 主頁面
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 導航主頁 | `lib/bodydoor_mode/bodydoor_navigation_page.dart` | StatefulWidget + Mixins 組合 |

### Controllers（Mixin）
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 串口控制 | `lib/bodydoor_mode/controllers/serial_controller.dart` | 僅 Arduino 連線/指令 |
| 自動偵測 | `lib/bodydoor_mode/controllers/auto_detection_controller.dart` | 僅掃描 Arduino 自動連接 |

### Services
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 串口管理 | `lib/bodydoor_mode/services/serial_port_manager.dart` | 僅文字模式 |
| 閾值設定 | `lib/bodydoor_mode/services/threshold_settings_service.dart` | ADC 閾值持久化 |

### Widgets（頁面）
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 自動偵測頁 | `lib/bodydoor_mode/widgets/auto_detection_page.dart` | 自動偵測 UI |
| 數據儲存頁 | `lib/bodydoor_mode/widgets/data_storage_page.dart` | 數據匯出 |
| 偵測規則頁 | `lib/bodydoor_mode/widgets/detection_rules_page.dart` | 偵測規則設定 |
| 設定頁 | `lib/bodydoor_mode/widgets/settings_page.dart` | 設定頁面 |
| 對話框 | `lib/bodydoor_mode/widgets/ui_dialogs.dart` | 共用對話框元件 |

---

## 共用模組（`lib/shared/`）

### Services
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 數據儲存 | `lib/shared/services/data_storage_service.dart` | ADC 數值 + 硬體狀態管理 |
| Arduino 連線驗證 | `lib/shared/services/arduino_connection_service.dart` | `connectAndVerify()` Mixin |
| COM 埠過濾 | `lib/shared/services/port_filter_service.dart` | 排除 ST-Link 設備 |
| 多語系 | `lib/shared/services/localization_service.dart` | `tr(key)` 翻譯系統 |

### Widgets
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 啟動畫面 | `lib/shared/widgets/splash_screen.dart` | 3 秒啟動動畫 |
| Arduino 面板 | `lib/shared/widgets/arduino_panel.dart` | Arduino 串口操作面板 |

### 其他
| 檔案 | 路徑 | 說明 |
|------|------|------|
| 語言狀態 | `lib/shared/language_state.dart` | `globalLanguageNotifier` 跨模式同步 |

---

## 設定與建構

| 檔案 | 路徑 | 說明 |
|------|------|------|
| Flutter 設定 | `pubspec.yaml` | 專案依賴與版本 |
| 分析設定 | `analysis_options.yaml` | Lint 規則 |
| Windows 建構 | `windows/` | Windows 平台建構設定 |
| Linux 建構 | `linux/` | Linux 平台建構設定 |

---

## 外部工具路徑

| 工具 | Windows 路徑 | Linux 路徑 |
|------|-------------|-----------|
| STM32CubeProgrammer CLI | `C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe` | `/usr/local/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI` |
