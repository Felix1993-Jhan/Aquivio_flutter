// ============================================================================
// ArduinoPanel - Arduino 控制面板 Widget
// ============================================================================
// 功能：提供 Arduino 串口的控制介面
// - COM 埠選擇與連接
// - BodyDoor 指令按鈕發送
// - 接收日誌顯示
// - 配色：翡翠綠主色調
// ============================================================================

import 'package:flutter/material.dart';
import '../services/serial_port_manager.dart';
import '../services/localization_service.dart';

/// 翡翠綠色調
class _EmeraldColors {
  static const Color primary = Color(0xFF50C878);
  static const Color light = Color(0xFFE8F5E9);
  static const Color dark = Color(0xFF2E7D32);
  static const Color background = Color(0xFFF1F8E9);
  static const Color header = Color(0xFF81C784);
}

class ArduinoPanel extends StatelessWidget {
  /// 串口管理器
  final SerialPortManager manager;

  /// 目前選擇的 COM 埠
  final String? selectedPort;

  /// 可用的 COM 埠列表
  final List<String> availablePorts;

  /// COM 埠選擇變更回調
  final ValueChanged<String?> onPortChanged;

  /// 連接按鈕回調
  final VoidCallback onConnect;

  /// 斷開按鈕回調
  final VoidCallback onDisconnect;

  /// 發送指令回調
  final ValueChanged<String> onSendCommand;

  /// BodyDoor Arduino 指令分組（Body 12V / Body 3.3V / Door）
  /// Body 12V (ID 0-5,7): ambientrl ~ mainuvc, flowmeter
  /// Body 3.3V (ID 6,8-11): bibtemp, watertemp, leak, waterpressure, co2pressure
  /// Door (ID 12-18): spoutuvc, mixuvc, flowmeter2, bp24v, bp12v, bpup, bplow
  static List<Map<String, dynamic>> getCommandGroups() => [
    {
      'label': 'Body 12V (ID 0-5,7)',
      'commands': ['ambientrl', 'coolrl', 'sparklingrl', 'waterpump', 'o3', 'mainuvc', 'flowmeter'],
    },
    {
      'label': 'Body 3.3V (ID 6,8-11)',
      'commands': ['bibtemp', 'watertemp', 'leak', 'waterpressure', 'co2pressure'],
    },
    {
      'label': 'Door (ID 12-14)',
      'commands': ['spoutuvc', 'mixuvc', 'flowmeter2'],
    },
    {
      'label': 'Door (ID 15-18)',
      'commands': ['bp24v', 'bp12v', 'bpup', 'bplow'],
    },
    {
      'label': tr('cmd_tool'),
      'commands': ['readall'],
    },
  ];

  const ArduinoPanel({
    super.key,
    required this.manager,
    required this.selectedPort,
    required this.availablePorts,
    required this.onPortChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSendCommand,
  });

  @override
  Widget build(BuildContext context) {
    // 監聽語言變更，自動更新 UI
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return Container(
          color: _EmeraldColors.background,
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

  /// 建構標題列
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: _EmeraldColors.header,
      child: Row(
        children: [
          Icon(Icons.memory, color: _EmeraldColors.dark),
          const SizedBox(width: 8),
          Text(
            tr('arduino_control'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          // 心跳狀態指示器（持續連接中）
          ValueListenableBuilder<bool>(
            valueListenable: manager.heartbeatOkNotifier,
            builder: (context, heartbeatOk, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: manager.isConnectedNotifier,
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
          // 連接狀態指示器
          ValueListenableBuilder<bool>(
            valueListenable: manager.isConnectedNotifier,
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

  /// 建構串口選擇區
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
            valueListenable: manager.isConnectedNotifier,
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

  /// 建構指令按鈕區
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
            // 按分組顯示指令按鈕
            ...getCommandGroups().map((group) {
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
                              backgroundColor: _EmeraldColors.primary,
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 建構日誌顯示區
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
                  onPressed: () => manager.clearLog(),
                  style: TextButton.styleFrom(
                    foregroundColor: _EmeraldColors.dark,
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
                border: Border.all(color: _EmeraldColors.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: ValueListenableBuilder<String>(
                      valueListenable: manager.logNotifier,
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
