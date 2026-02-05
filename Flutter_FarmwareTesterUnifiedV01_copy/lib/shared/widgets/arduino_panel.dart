// ============================================================================
// ArduinoPanel - Arduino 控制面板 Widget（共用版本）
// ============================================================================
// 功能：提供 Arduino 串口的控制介面
// - COM 口選擇與連線
// - 指令按鈕區（由外部傳入 commandGroups）
// - 接收日誌顯示
// - 可選的額外指令區域（如 flow 輸入區）
// - 配色：翡翠綠主色調
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';

/// 翡翠綠色系
class EmeraldColors {
  static const Color primary = Color(0xFF50C878);
  static const Color light = Color(0xFFE8F5E9);
  static const Color dark = Color(0xFF2E7D32);
  static const Color background = Color(0xFFF1F8E9);
  static const Color header = Color(0xFF81C784);
}

class ArduinoPanel extends StatelessWidget {
  /// 日誌 Notifier
  final ValueNotifier<String> logNotifier;

  /// 心跳狀態 Notifier
  final ValueNotifier<bool> heartbeatOkNotifier;

  /// 連線狀態 Notifier
  final ValueNotifier<bool> isConnectedNotifier;

  /// 清除日誌回調
  final VoidCallback onClearLog;

  /// 當前選中的 COM 口
  final String? selectedPort;

  /// 可用的 COM 口列表
  final List<String> availablePorts;

  /// COM 口選擇變更回調
  final ValueChanged<String?> onPortChanged;

  /// 連線按鈕回調
  final VoidCallback onConnect;

  /// 斷線按鈕回調
  final VoidCallback onDisconnect;

  /// 發送指令回調
  final ValueChanged<String> onSendCommand;

  /// 指令分組列表（由各模式傳入）
  final List<Map<String, dynamic>> commandGroups;

  /// 額外指令區域 Widget（如 Main 模式的 flow 輸入區）
  final Widget? extraCommandWidget;

  const ArduinoPanel({
    super.key,
    required this.logNotifier,
    required this.heartbeatOkNotifier,
    required this.isConnectedNotifier,
    required this.onClearLog,
    required this.selectedPort,
    required this.availablePorts,
    required this.onPortChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSendCommand,
    required this.commandGroups,
    this.extraCommandWidget,
  });

  @override
  Widget build(BuildContext context) {
    // 監聽語言變更，自動更新 UI
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, _) {
        return Container(
          color: EmeraldColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 標題列
              _buildHeader(),
              // 串口選擇區
              _buildPortSelector(),
              // 指令按鈕區
              _buildCommandButtons(),
              // 接收日誌區
              _buildLogSection(),
            ],
          ),
        );
      },
    );
  }

  /// 建立標題列
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: EmeraldColors.header,
      child: Row(
        children: [
          Icon(Icons.memory, color: EmeraldColors.dark),
          const SizedBox(width: 8),
          Text(
            tr('arduino_control'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          // 心跳指示器（持續連線中）
          ValueListenableBuilder<bool>(
            valueListenable: heartbeatOkNotifier,
            builder: (context, heartbeatOk, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: isConnectedNotifier,
                builder: (context, isConnected, _) {
                  if (!isConnected) return const SizedBox.shrink();
                  return Tooltip(
                    message: heartbeatOk ? tr('continuous_connection') : tr('connection_lost'),
                    child: Icon(
                      heartbeatOk ? Icons.link : Icons.link_off,
                      color: heartbeatOk ? Colors.green.shade700 : Colors.red,
                      size: 20,
                    ),
                  );
                },
              );
            },
          ),
          const Spacer(),
          // 連線狀態指示器
          ValueListenableBuilder<bool>(
            valueListenable: isConnectedNotifier,
            builder: (context, isConnected, _) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isConnected ? tr('connected') : tr('disconnected'),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 建立串口選擇區
  Widget _buildPortSelector() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: tr('select_com_port'),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: availablePorts.contains(selectedPort) ? selectedPort : null,
                  hint: Text(tr('select_com_port')),
                  isExpanded: true,
                  isDense: true,
                  items: availablePorts.map((port) {
                    return DropdownMenuItem(value: port, child: Text(port));
                  }).toList(),
                  onChanged: onPortChanged,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: isConnectedNotifier,
            builder: (context, isConnected, _) {
              return ElevatedButton(
                onPressed: isConnected ? onDisconnect : onConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(isConnected ? tr('disconnect') : tr('connect')),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 建立指令按鈕區
  Widget _buildCommandButtons() {
    return Expanded(
      flex: 0,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(tr('command_buttons'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            // 分組顯示指令按鈕
            ...commandGroups.map((group) {
              final label = group['label'] as String;
              final commands = group['commands'] as List<String>;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: commands.map((cmd) {
                          return ElevatedButton(
                            onPressed: () => onSendCommand(cmd),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(50, 28),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              backgroundColor: EmeraldColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(cmd, style: const TextStyle(fontSize: 10)),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            // 額外指令區域（如 flow 輸入區）
            if (extraCommandWidget != null) extraCommandWidget!,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 建立日誌顯示區
  Widget _buildLogSection() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(tr('receive_log'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: onClearLog,
                  style: TextButton.styleFrom(
                    foregroundColor: EmeraldColors.dark,
                  ),
                  child: Text(tr('clear')),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: EmeraldColors.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: ValueListenableBuilder<String>(
                      valueListenable: logNotifier,
                      builder: (context, log, _) {
                        return SingleChildScrollView(
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: SelectableText(
                              log,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
