# Main Board 模式

## 概述

Main Board 模式支援 **Arduino + STM32** 雙串口通訊，包含 ADC 感測器讀取、MOSFET 輸出控制、韌體燒錄功能。
共 6 個頁面、24 個 ADC 通道 (ID 0-23)。

---

## 目錄結構

```
main_mode/
├── main_navigation_page.dart          # 主導航（StatefulWidget + Mixins）
├── controllers/
│   ├── auto_detection_controller.dart  # 自動偵測流程 Mixin（Arduino + STM32）
│   ├── serial_controller.dart          # 串口操作 Mixin（Arduino + STM32）
│   └── firmware_controller.dart        # 韌體燒錄控制 Mixin
├── services/
│   ├── serial_port_manager.dart        # 串口管理（文字 + 二進位雙模式）
│   ├── ur_command_builder.dart         # STM32 二進位指令建構器
│   ├── threshold_settings_service.dart # ADC 閾值設定持久化
│   ├── adjacent_pins_service.dart      # 相鄰腳位短路偵測
│   ├── stlink_programmer_service.dart  # ST-Link 韌體燒錄
│   └── cli_checker_service.dart        # CLI 工具檢查
└── widgets/
    ├── auto_detection_page.dart        # 自動偵測頁面
    ├── operation_page.dart             # 手動操作頁面
    ├── data_storage_page.dart          # 數據儲存/匯出
    ├── detection_rules_page.dart       # 偵測規則設定
    ├── settings_page.dart              # 設定（閾值/語言）
    ├── firmware_upload_page.dart       # 韌體上傳
    ├── ur_panel.dart                   # STM32 串口面板
    ├── ui_dialogs.dart                 # 共用對話框
    └── cli_check_dialog.dart           # CLI 工具檢查對話框
```

---

## Mixin 組合

```dart
class _MainNavigationPageState extends State<MainNavigationPage>
    with SerialController, AutoDetectionController, FirmwareController {
  // SerialController — Arduino + STM32 連線/斷線/指令發送/流量控制
  // AutoDetectionController — 掃描 Arduino + STM32 並自動連接
  // FirmwareController — ST-Link 韌體燒錄
}
```

每個 Mixin 定義需由 NavigationPage 實作的抽象成員：
- `SerialPortManager get arduinoManager;`
- `SerialPortManager get urManager;`
- `void showSnackBarMessage(String message);`
- `void onWrongModeDetected(String portName);`

---

## STM32 二進位通訊協定

`URCommandBuilder` 建構指令格式：`[0x40, 0x71, 0x30, payload..., checksum]`

| 指令碼 | 功能 |
|--------|------|
| `0x01` | 開啟輸出（MOSFET ON） |
| `0x02` | 關閉輸出（MOSFET OFF） |
| `0x03` | 讀取 ADC（帶 sensor ID） |
| `0x04` | 清除數值 |
| `0x05` | 讀取韌體版本 |

---

## SerialPortManager（雙模式）

Main 版本的 SerialPortManager 同時支援文字模式（Arduino）和二進位模式（STM32）：
- 文字模式：Arduino 通訊，心跳 `"connect"` / 回應 `"connectedmain"`
- 二進位模式：STM32 通訊，使用 URCommandBuilder 建構指令
- 額外功能：`firmwareVersionNotifier`、`connectAndVerifyStm32()`
- 流量計控制：`flowon` / `flowoff` + 定時讀取

---

## 連線機制

```dart
// Arduino 連線
Future<void> connectArduino() async {
  final ports = PortFilterService.getAvailablePorts(excludeStLink: true);
  for (final port in ports) {
    final result = await arduinoManager.connectAndVerify(port);
    if (result == ConnectResult.success) return;
  }
}

// STM32 連線（排除已使用的 Arduino 埠口）
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

---

## 韌體燒錄（ST-Link）

- `StlinkProgrammerService` 呼叫 STM32CubeProgrammer CLI 執行燒錄
- `CliCheckerService` 檢查 CLI 工具是否已安裝
- 支援 `.bin` / `.hex` 韌體檔案
- STM32CubeProgrammer CLI 預設路徑：
  - Windows: `C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe`
  - Linux: `/usr/local/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI`
