// ============================================================================
// CliCheckDialog - CLI 工具檢查對話框
// ============================================================================
// 功能：顯示 CLI 工具檢查結果，引導使用者安裝缺少的工具
// ============================================================================

import 'package:flutter/material.dart';
import '../services/cli_checker_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';

/// 顯示 CLI 檢查對話框
/// 返回 true 表示使用者選擇繼續，false 表示取消
Future<bool> showCliCheckDialog(
  BuildContext context,
  CliCheckResult checkResult,
) async {
  final hasInstaller = await CliCheckerService.hasStm32Installer();

  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return _CliCheckDialogContent(
        checkResult: checkResult,
        hasInstaller: hasInstaller,
      );
    },
  );

  return result ?? false;
}

class _CliCheckDialogContent extends StatelessWidget {
  final CliCheckResult checkResult;
  final bool hasInstaller;

  const _CliCheckDialogContent({
    required this.checkResult,
    required this.hasInstaller,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade400, width: 2),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('cli_check_title'),
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 說明文字
            Text(
              tr('cli_check_description'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),

            // STM32CubeProgrammer 狀態
            _buildCliStatus(
              name: 'STM32CubeProgrammer CLI',
              isInstalled: checkResult.stm32ProgrammerExists,
              path: checkResult.stm32ProgrammerPath,
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // 安裝說明
            if (!checkResult.stm32ProgrammerExists) ...[
              Text(
                tr('cli_install_instruction'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),

              if (hasInstaller) ...[
                // 有安裝程式，顯示執行按鈕
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: Colors.blue.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('cli_installer_found'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'tools\\SetupSTM32CubeProgrammer.exe',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await CliCheckerService.runStm32Installer();
                        },
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(tr('cli_run_installer')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // 沒有安裝程式，顯示下載說明
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.download, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text(
                            tr('cli_download_instruction'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        'https://www.st.com/en/development-tools/stm32cubeprog.html',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('cli_installer_tip'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 開啟 tools 資料夾按鈕
              OutlinedButton.icon(
                onPressed: () async {
                  await CliCheckerService.openToolsFolder();
                },
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(tr('cli_open_tools_folder')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // 略過按鈕（繼續使用，但燒錄功能不可用）
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            tr('cli_skip_continue'),
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        // 重新檢查按鈕
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(tr('cli_recheck')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildCliStatus({
    required String name,
    required bool isInstalled,
    String? path,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isInstalled ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isInstalled ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isInstalled ? Icons.check_circle : Icons.cancel,
            color: isInstalled ? Colors.green : Colors.red,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isInstalled ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isInstalled
                      ? path ?? tr('cli_status_installed')
                      : tr('cli_status_not_found'),
                  style: TextStyle(
                    fontSize: 12,
                    color: isInstalled ? Colors.green.shade600 : Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}