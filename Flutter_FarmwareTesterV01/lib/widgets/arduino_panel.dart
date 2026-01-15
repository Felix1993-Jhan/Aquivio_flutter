// ============================================================================
// ArduinoPanel - Arduino 控制面板 Widget
// ============================================================================
// 功能：提供 Arduino 串口的控制介面
// - COM 埠選擇與連接
// - 指令按鈕發送
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

  /// flow 數值輸入框控制器
  final TextEditingController flowController;

  /// Arduino 指令分組（按 ID 順序排列）
  /// ID 0-9: s0-s9 (馬達)
  /// ID 10: water (水泵)
  /// ID 11-13: u0-u2 (紫外燈)
  /// ID 14-16: arl, crl, srl (繼電器)
  /// ID 17: o3 (臭氧)
  /// ID 18: flowon/flowoff (流量)
  /// ID 19-20: prec, prew (壓力)
  /// ID 21: mcutemp (溫度)
  static List<Map<String, dynamic>> getCommandGroups() => [
    {
      'label': tr('cmd_motor'),
      'commands': ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9'],
    },
    {
      'label': tr('cmd_water_pump'),
      'commands': ['water'],
    },
    {
      'label': tr('cmd_uvc'),
      'commands': ['u0', 'u1', 'u2'],
    },
    {
      'label': tr('cmd_relay'),
      'commands': ['arl', 'crl', 'srl'],
    },
    {
      'label': tr('cmd_ozone'),
      'commands': ['o3'],
    },
    {
      'label': tr('cmd_flow'),
      'commands': ['flowon', 'flowoff'],
    },
    {
      'label': tr('cmd_pressure'),
      'commands': ['prec', 'prew'],
    },
    {
      'label': tr('cmd_temperature'),
      'commands': ['mcutemp'],
    },
  ];

  const ArduinoPanel({
    super.key,
    required this.manager,
    required this.selectedPort,
    required this.availablePorts,
    required this.flowController,
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
            const SizedBox(height: 4),
            // flowXXXX 輸入區
            _buildFlowInput(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 建構 flowXXXX 輸入區
  Widget _buildFlowInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text('flow', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: flowController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '125-5000',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final text = flowController.text.trim();
              if (text.isEmpty) return;
              final value = int.tryParse(text);
              if (value == null || value < 125 || value > 5000) {
                return;
              }
              onSendCommand('flow$text');
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(60, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: _EmeraldColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('send'), style: const TextStyle(fontSize: 12)),
          ),
        ],
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