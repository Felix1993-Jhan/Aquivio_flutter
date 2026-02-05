// ============================================================================
// CliCheckerService - CLI 工具檢查服務
// ============================================================================
// 功能：檢查必要的外部 CLI 工具是否已安裝
// ============================================================================

import 'dart:io';

/// CLI 工具檢查結果
class CliCheckResult {
  final bool stm32ProgrammerExists;
  final String? stm32ProgrammerPath;

  CliCheckResult({
    required this.stm32ProgrammerExists,
    this.stm32ProgrammerPath,
  });

  /// 所有必要的 CLI 是否都已安裝
  bool get allCliReady => stm32ProgrammerExists;
}

/// CLI 工具檢查服務
class CliCheckerService {
  // STM32CubeProgrammer CLI 可能的安裝路徑
  static const List<String> _stm32ProgrammerPaths = [
    // 預設安裝路徑
    r'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
    // 32 位元路徑
    r'C:\Program Files (x86)\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
  ];

  /// 取得 tools 資料夾路徑（應用程式目錄下）
  static String getToolsFolder() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}tools';
  }

  /// 取得 tools 資料夾內的 STM32 Programmer 安裝程式路徑
  static String getStm32InstallerPath() {
    return '${getToolsFolder()}${Platform.pathSeparator}SetupSTM32CubeProgrammer.exe';
  }

  /// 檢查 tools 資料夾內是否有安裝程式
  static Future<bool> hasStm32Installer() async {
    final file = File(getStm32InstallerPath());
    return await file.exists();
  }

  /// 檢查所有必要的 CLI 工具
  static Future<CliCheckResult> checkAllCli() async {
    String? stm32Path;
    bool stm32Exists = false;

    // 檢查 STM32CubeProgrammer CLI
    for (final path in _stm32ProgrammerPaths) {
      final file = File(path);
      if (await file.exists()) {
        stm32Exists = true;
        stm32Path = path;
        break;
      }
    }

    return CliCheckResult(
      stm32ProgrammerExists: stm32Exists,
      stm32ProgrammerPath: stm32Path,
    );
  }

  /// 開啟 tools 資料夾
  static Future<void> openToolsFolder() async {
    final toolsPath = getToolsFolder();
    final dir = Directory(toolsPath);

    // 如果資料夾不存在，先建立
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 使用 explorer 開啟資料夾
    await Process.run('explorer', [toolsPath]);
  }

  /// 執行 STM32CubeProgrammer 安裝程式
  static Future<bool> runStm32Installer() async {
    final installerPath = getStm32InstallerPath();
    final file = File(installerPath);

    if (!await file.exists()) {
      return false;
    }

    try {
      // 以管理員權限執行安裝程式
      await Process.run('cmd', ['/c', 'start', '', installerPath]);
      return true;
    } catch (e) {
      return false;
    }
  }
}