# Body&Door Board 模式

## 概述

Body&Door Board 模式僅使用 **Arduino** 單串口通訊，專注於 ADC 感測器讀取功能。
共 4 個頁面、19 個 ADC 通道 (ID 0-18)。不支援 STM32 通訊和韌體燒錄。

---

## 目錄結構

```
bodydoor_mode/
├── bodydoor_navigation_page.dart      # 主導航頁面
├── controllers/
│   ├── auto_detection_controller.dart  # 自動偵測流程 Mixin（僅 Arduino）
│   └── serial_controller.dart          # 串口操作 Mixin（僅 Arduino）
├── services/
│   ├── serial_port_manager.dart        # 串口管理（僅文字模式）
│   └── threshold_settings_service.dart # ADC 閾值設定持久化
└── widgets/
    ├── auto_detection_page.dart        # 自動偵測頁面
    ├── data_storage_page.dart          # 數據儲存/匯出
    ├── detection_rules_page.dart       # 偵測規則設定
    ├── settings_page.dart              # 設定頁面
    └── ui_dialogs.dart                 # 共用對話框
```

---

## Mixin 組合

```dart
class _BodyDoorNavigationPageState extends State<BodyDoorNavigationPage>
    with SerialController, AutoDetectionController {
  // SerialController — 僅 Arduino 連線/斷線/指令發送
  // AutoDetectionController — 僅掃描 Arduino 並自動連接
  // 注意：無 FirmwareController（不支援韌體燒錄）
}
```

抽象成員：
- `SerialPortManager get arduinoManager;`
- `void showSnackBarMessage(String message);`
- `void onWrongModeDetected(String portName);`

---

## SerialPortManager（僅文字模式）

Body&Door 版本的 SerialPortManager 只支援文字模式（Arduino）：
- 心跳：發送 `"connect"`，期望回應 `"connectedbodydoor"`
- 不支援二進位模式、無 STM32 相關功能
- 無流量計控制

---

## 連線機制

```dart
// Arduino 連線（掃描所有可用埠口）
Future<void> connectArduino() async {
  final ports = PortFilterService.getAvailablePorts(excludeStLink: true);
  for (final port in ports) {
    final result = await arduinoManager.connectAndVerify(port);
    if (result == ConnectResult.success) return;
  }
}
```

---

## 與 Main Board 的差異

| 項目 | Body&Door | Main Board |
|------|-----------|-----------|
| 串口數量 | 1（僅 Arduino） | 2（Arduino + STM32） |
| ADC 通道數 | 19 (ID 0-18) | 24 (ID 0-23) |
| STM32 通訊 | 無 | 二進位協定 |
| 韌體燒錄 | 不支援 | 支援 (ST-Link) |
| 流量計控制 | 無 | flowon/flowoff |
| 頁面數量 | 4 頁 | 6 頁 |
| 心跳識別 | `"connectedbodydoor"` | `"connectedmain"` |
