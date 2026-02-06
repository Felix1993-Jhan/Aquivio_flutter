// ============================================================================
// OperationPage - 操作畫面
// ============================================================================
// 功能：
// - 自動偵測並連線 STM32
// - 常溫水按鈕：開啟 ID10~ID14
// - 停止按鈕：關閉 ID0~ID17
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import 'package:flutter_firmware_tester_unified/shared/services/serial_port_manager.dart';
import '../services/ur_command_builder.dart';

class OperationPage extends StatefulWidget {
  final SerialPortManager urManager;
  final List<String> availablePorts;
  final String? selectedUrPort;
  final String? arduinoPortName;
  final bool isStm32Connected;
  final VoidCallback onConnectStm32;
  final VoidCallback onDisconnectStm32;
  final void Function(String port) onStm32PortChanged;
  final void Function(List<int> payload) onSendUrCommand;
  final void Function(String message) onShowSnackBar;

  const OperationPage({
    super.key,
    required this.urManager,
    required this.availablePorts,
    required this.selectedUrPort,
    required this.arduinoPortName,
    required this.isStm32Connected,
    required this.onConnectStm32,
    required this.onDisconnectStm32,
    required this.onStm32PortChanged,
    required this.onSendUrCommand,
    required this.onShowSnackBar,
  });

  @override
  State<OperationPage> createState() => _OperationPageState();
}

class _OperationPageState extends State<OperationPage> {
  bool _isConnecting = false;

  /// 自動偵測連線 STM32（與自動檢測頁面相同邏輯）
  Future<void> _autoConnectStm32() async {
    if (widget.isStm32Connected || _isConnecting) return;

    setState(() => _isConnecting = true);

    try {
      // 取得可用 COM 埠（排除 Arduino 使用的）
      final availableForStm32 = widget.availablePorts
          .where((p) => p != widget.arduinoPortName)
          .toList();

      if (availableForStm32.isEmpty) {
        widget.onShowSnackBar(tr('operation_connect_failed'));
        setState(() => _isConnecting = false);
        return;
      }

      // 建立要嘗試的 COM 埠列表（優先嘗試已選擇的）
      final portsToTry = <String>[];
      if (widget.selectedUrPort != null &&
          availableForStm32.contains(widget.selectedUrPort)) {
        portsToTry.add(widget.selectedUrPort!);
        portsToTry.addAll(
            availableForStm32.where((p) => p != widget.selectedUrPort));
      } else {
        portsToTry.addAll(availableForStm32);
      }

      bool connected = false;

      for (final port in portsToTry) {
        if (widget.urManager.open(port)) {
          // 發送韌體版本查詢來驗證是否為 STM32
          final payload = [0x05, 0x00, 0x00, 0x00, 0x00];
          final cmd = URCommandBuilder.buildCommand(payload);
          widget.urManager.sendHex(cmd);

          // 等待驗證回應
          await Future.delayed(const Duration(milliseconds: 1500));

          if (widget.urManager.firmwareVersionNotifier.value != null) {
            widget.urManager.startHeartbeat();
            connected = true;
            widget.onStm32PortChanged(port);
            break;
          } else {
            widget.urManager.close();
          }
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (connected) {
        widget.onShowSnackBar(tr('operation_connected'));
      } else {
        widget.onShowSnackBar(tr('operation_connect_failed'));
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  /// 常溫水：開啟 ID10~ID14
  void _sendWarmWater() {
    if (!widget.isStm32Connected) {
      widget.onShowSnackBar(tr('operation_stm32_not_connected'));
      return;
    }

    // ID 10-14 的 bitmask: bits 10,11,12,13,14
    // = 0x7C00 → low=0x00, mid=0x7C, high=0x00
    final payload = [0x01, 0x00, 0x7C, 0x00, 0x00];
    widget.onSendUrCommand(payload);
    widget.onShowSnackBar(tr('operation_warm_water_sent'));
  }

  /// 停止：關閉 ID0~ID17
  void _sendStop() {
    if (!widget.isStm32Connected) {
      widget.onShowSnackBar(tr('operation_stm32_not_connected'));
      return;
    }

    // ID 0-17 全部關閉: 0xFF, 0xFF, 0x03
    final payload = [0x02, 0xFF, 0xFF, 0x03, 0x00];
    widget.onSendUrCommand(payload);
    widget.onShowSnackBar(tr('operation_stop_sent'));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, _) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // STM32 連線狀態 & 自動連線按鈕
              _buildConnectionCard(),
              const SizedBox(height: 32),
              // 操作按鈕區
              Expanded(
                child: _buildOperationButtons(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard() {
    final connected = widget.isStm32Connected;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: connected ? Colors.green : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // 連線狀態指示
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'STM32',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: connected ? Colors.green.shade800 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              connected ? tr('connected') : tr('disconnected'),
              style: TextStyle(
                fontSize: 14,
                color: connected ? Colors.green : Colors.red,
              ),
            ),
            const Spacer(),
            // 連線/斷線按鈕
            if (_isConnecting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!connected)
              ElevatedButton.icon(
                onPressed: _autoConnectStm32,
                icon: const Icon(Icons.usb),
                label: Text(tr('operation_auto_connect')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: widget.onDisconnectStm32,
                icon: const Icon(Icons.usb_off),
                label: Text(tr('disconnect')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationButtons() {
    final connected = widget.isStm32Connected;
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 常溫水按鈕
          _buildOperationButton(
            label: tr('operation_warm_water'),
            description: tr('operation_warm_water_desc'),
            icon: Icons.water_drop,
            color: Colors.blue,
            enabled: connected,
            onPressed: _sendWarmWater,
          ),
          const SizedBox(width: 40),
          // 停止按鈕
          _buildOperationButton(
            label: tr('operation_stop'),
            description: tr('operation_stop_desc'),
            icon: Icons.stop_circle,
            color: Colors.red,
            enabled: connected,
            onPressed: _sendStop,
          ),
        ],
      ),
    );
  }

  Widget _buildOperationButton({
    required String label,
    required String description,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 200,
      height: 200,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? color : Colors.grey.shade300,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: enabled ? 6 : 2,
          padding: const EdgeInsets.all(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: enabled ? Colors.white : Colors.grey),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: enabled ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: enabled
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
