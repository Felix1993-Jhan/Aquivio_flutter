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
  // STM32CubeProgrammer CLI 可能的安裝路徑（根據平台）
  static List<String> get _stm32ProgrammerPaths {
    if (Platform.isWindows) {
      return [
        // 預設安裝路徑
        r'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
        // 32 位元路徑
        r'C:\Program Files (x86)\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
      ];
    } else if (Platform.isLinux) {
      return [
        // Linux 預設安裝路徑
        '/usr/local/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI',
        // 使用者安裝路徑
        '${Platform.environment['HOME']}/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI',
        // opt 路徑
        '/opt/stm32cubeprog/bin/STM32_Programmer_CLI',
      ];
    } else if (Platform.isMacOS) {
      return [
        // macOS 預設安裝路徑
        '/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI',
      ];
    }
    return [];
  }

  /// 取得 tools 資料夾路徑（應用程式目錄下）
  static String getToolsFolder() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}tools';
  }

  /// 取得 tools 資料夾內的 STM32 Programmer 安裝程式路徑
  static String getStm32InstallerPath() {
    if (Platform.isWindows) {
      return '${getToolsFolder()}${Platform.pathSeparator}SetupSTM32CubeProgrammer.exe';
    } else if (Platform.isLinux) {
      // Linux 使用 .deb 或 .run 安裝檔
      return '${getToolsFolder()}${Platform.pathSeparator}SetupSTM32CubeProgrammer.linux';
    } else if (Platform.isMacOS) {
      // macOS 使用 .pkg 或 .dmg 安裝檔
      return '${getToolsFolder()}${Platform.pathSeparator}SetupSTM32CubeProgrammer.pkg';
    }
    return '${getToolsFolder()}${Platform.pathSeparator}SetupSTM32CubeProgrammer';
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

    // 根據平台開啟資料夾
    if (Platform.isWindows) {
      await Process.run('explorer', [toolsPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [toolsPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [toolsPath]);
    }
  }

  /// 執行 STM32CubeProgrammer 安裝程式
  static Future<bool> runStm32Installer() async {
    final installerPath = getStm32InstallerPath();
    final file = File(installerPath);

    if (!await file.exists()) {
      return false;
    }

    try {
      if (Platform.isWindows) {
        // Windows: 以管理員權限執行安裝程式
        await Process.run('cmd', ['/c', 'start', '', installerPath]);
      } else if (Platform.isLinux) {
        // Linux: 執行 .run 安裝檔（需要執行權限）
        await Process.run('chmod', ['+x', installerPath]);
        await Process.run(installerPath, []);
      } else if (Platform.isMacOS) {
        // macOS: 開啟 .pkg 安裝檔
        await Process.run('open', [installerPath]);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}