# Farmware Tester Suite

基於 Flutter 的硬體韌體測試工具套件，專為 Farmware 產品設計。

---

## 🎯 主力專案：Unified Tester（推薦使用）

**Flutter_FarmwareTesterUnifiedV01** - 整合版測試工具

### 主要功能

- ✅ **Main Board（主板）測試**
  - Arduino + STM32 雙控制器支援
  - 24 通道 ADC 感測器讀取
  - MOSFET 輸出控制
  - VDD/VSS 短路測試
  - 相鄰腳位短路偵測
  - 診斷偵測功能

- ✅ **Body & Door Board（車身&門板）測試**
  - 19 通道 ADC 感測器讀取
  - 電源異常偵測（3.3V, Body12V, Door24V, Door12V）

- ✅ **韌體燒錄**
  - STM32 韌體透過 ST-Link 燒錄
  - 支援倒數計時自動燒錄

- ✅ **自動偵測**
  - 自動掃描並連接 Arduino/STM32
  - 錯誤模式偵測與切換
  - 完整測試流程自動化

- ✅ **跨平台支援**
  - Windows 10+
  - Linux (Ubuntu, Debian, Fedora, Arch)
  - 支援繁體中文與英文介面

### 📥 下載最新版本

前往 [GitHub Actions](https://github.com/Felix1993-Jhan/Aquivio_flutter/actions) 下載自動建構的最新版本：

- **Windows**: `FarmwareTesterUnified-Windows.zip`
- **Linux**: `FarmwareTesterUnified-Linux.zip`

---

## 📦 其他專案（歷史版本）

### Flutter_FarmwareTestBodyDoorV01
Body & Door Board 獨立測試工具

**狀態：** 已整合至 Unified 版本，保留作為參考

### Flutter_FarmwareTesterV01
Main Board 獨立測試工具

**狀態：** 已整合至 Unified 版本，保留作為參考

---

## 🚀 快速開始

### Windows 部署

1. 下載 `FarmwareTesterUnified-Windows.zip`
2. 解壓縮到任意目錄
3. 執行 `flutter_firmware_tester_unified.exe`

**額外需求（僅 Main 模式燒錄功能）：**
- [STM32CubeProgrammer](https://www.st.com/en/development-tools/stm32cubeprog.html)

### Linux 部署

詳細部署說明請參考：[LINUX_DEPLOYMENT.md](Flutter_FarmwareTesterUnifiedV01/LINUX_DEPLOYMENT.md)

**重點步驟：**
1. 解壓縮 `FarmwareTesterUnified-Linux.zip`
2. 設定串口權限（加入 `dialout` 群組）
3. 執行程式

**串口權限設定：**
```bash
sudo usermod -a -G dialout $USER
# 登出並重新登入
```

---

## 🛠️ 開發環境設定

### 需求

- Flutter SDK 3.10.4+
- Windows 10+ 或 Linux (GTK 3.0+)

### 開發步驟

```bash
# 進入 Unified 專案目錄
cd Flutter_FarmwareTesterUnifiedV01

# 安裝依賴
flutter pub get

# 啟用桌面支援（首次執行）
flutter config --enable-windows-desktop  # Windows
flutter config --enable-linux-desktop    # Linux

# 執行程式
flutter run -d windows  # Windows
flutter run -d linux    # Linux

# 建構 Release 版本
flutter build windows --release
flutter build linux --release
```

---

## 📋 系統需求

### Windows
- **作業系統：** Windows 10 或更新版本
- **記憶體：** 最低 512MB，建議 1GB+
- **儲存空間：** 約 100MB
- **USB：** USB 2.0+ 埠口用於串口通訊

### Linux
- **作業系統：** Linux x64（GTK 3.0+）
- **記憶體：** 最低 512MB，建議 1GB+
- **儲存空間：** 約 100MB
- **USB：** USB 2.0+ 埠口用於串口通訊

**已測試的 Linux 發行版：**
- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 / 12
- Fedora 38+
- Arch Linux

---

## 🔧 技術架構

- **框架：** Flutter 3.10.4
- **語言：** Dart
- **串口通訊：** flutter_libserialport
- **設定儲存：** shared_preferences
- **視窗管理：** window_manager
- **多語系：** 內建繁體中文/英文切換

**架構特色：**
- Mixin 模式組合功能模組
- Monorepo 統一管理多專案
- GitHub Actions 自動化建構

---

## 📖 專案文件

- [專案規範 (CLAUDE.md)](Flutter_FarmwareTesterUnifiedV01/CLAUDE.md) - 開發規範與架構說明
- [Linux 部署指南](Flutter_FarmwareTesterUnifiedV01/LINUX_DEPLOYMENT.md) - Linux 完整部署說明

---

## 🤝 貢獻

本專案為 Aquivio 內部使用工具，目前不接受外部貢獻。

---

## 📄 授權

© 2024-2026 Aquivio. All rights reserved.

---

## 📞 聯絡資訊

如有問題或建議，請透過 GitHub Issues 回報。

---

## 🔄 自動建構

本專案使用 GitHub Actions 自動建構 Windows 和 Linux 版本：

- 每次 push 到 `main` 分支時自動觸發
- 可手動觸發建構（workflow_dispatch）
- Artifacts 保留 30 天

**查看建構狀態：** [GitHub Actions](https://github.com/Felix1993-Jhan/Aquivio_flutter/actions)
