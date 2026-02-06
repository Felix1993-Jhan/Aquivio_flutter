// ============================================================================
// SettingsPage - 設定頁面 (BodyDoor 版)
// ============================================================================
// 功能：應用程式設定
// - 語言選擇（繁體中文 / English）
// - 閾值設定（Arduino Idle，ID 0-18）
// - 恢復初始設定功能
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import 'data_storage_page.dart';
import 'detection_rules_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ThresholdSettingsService _thresholdService = ThresholdSettingsService();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, currentLanguage, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _thresholdService.settingsUpdateNotifier,
          builder: (context, _, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 語言設定區塊
                  _buildLanguageSection(context, currentLanguage),
                  const SizedBox(height: 24),
                  // 閾值設定區塊
                  _buildThresholdSection(context),
                  const SizedBox(height: 24),
                  // 檢測規則說明區塊
                  _buildDetectionRulesSection(context),
                  const SizedBox(height: 24),
                  // 關於區塊
                  _buildAboutSection(context),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 建構語言設定區塊
  Widget _buildLanguageSection(BuildContext context, AppLanguage currentLanguage) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  tr('language_setting'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...AppLanguage.values.map((language) {
              final isSelected = language == currentLanguage;
              return InkWell(
                onTap: () => LocalizationService().setLanguage(language),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade50 : null,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: Colors.blue.shade300, width: 2)
                        : Border.all(color: Colors.grey.shade300),
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            language == AppLanguage.zhTW ? '中' : 'EN',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              language.displayName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.blue.shade700 : Colors.black87,
                              ),
                            ),
                            Text(
                              language.code,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: Colors.blue.shade700),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 建構閾值設定區塊
  Widget _buildThresholdSection(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('threshold_settings'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      Text(
                        tr('threshold_settings_desc'),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showResetConfirmDialog,
                  icon: const Icon(Icons.restore, size: 18),
                  label: Text(tr('reset_to_defaults')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Arduino 閾值標題
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: EmeraldColors.primary.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
                color: EmeraldColors.primary.withValues(alpha: 0.05),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8, height: 24,
                        decoration: BoxDecoration(
                          color: EmeraldColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Arduino',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: EmeraldColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('bodydoor_hardware_threshold'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Idle 閾值磚塊
                  _buildThresholdCategoryTile(
                    title: tr('idle_threshold'),
                    color: EmeraldColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建構閾值類別磚塊
  Widget _buildThresholdCategoryTile({
    required String title,
    required Color color,
  }) {
    final thresholds = _thresholdService.getAllHardwareThresholds(DeviceType.arduino, StateType.idle);
    final sampleRange = thresholds[0];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 8, height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${tr('threshold_range')}: ${sampleRange?.min ?? 0} ~ ${sampleRange?.max ?? 0}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showThresholdEditDialog(title, color),
      ),
    );
  }

  /// 顯示閾值編輯對話框
  void _showThresholdEditDialog(String title, Color color) {
    final thresholds = _thresholdService.getAllHardwareThresholds(DeviceType.arduino, StateType.idle);

    showDialog(
      context: context,
      builder: (context) => _ThresholdEditDialog(
        title: title,
        color: color,
        thresholds: thresholds,
        onSave: (newThresholds) async {
          for (final entry in newThresholds.entries) {
            await _thresholdService.setHardwareThreshold(DeviceType.arduino, StateType.idle, entry.key, entry.value);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('save_success'))),
            );
          }
        },
        onApplyToAll: (range) async {
          await _thresholdService.setAllHardwareThresholds(DeviceType.arduino, StateType.idle, range);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('save_success'))),
            );
          }
        },
      ),
    );
  }

  /// 顯示恢復初始設定確認對話框
  void _showResetConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text(tr('reset_to_defaults')),
          ],
        ),
        content: Text(tr('reset_all_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              await _thresholdService.resetToDefaults();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('reset_success'))),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
  }

  /// 建構檢測規則說明區塊
  Widget _buildDetectionRulesSection(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Text(
                  tr('detection_rules_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              tr('detection_rules_desc'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DetectionRulesPage()),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(tr('detection_rules_title')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建構關於區塊
  Widget _buildAboutSection(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  'About',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('App Version', '1.0.0'),
            _buildInfoRow('Flutter', 'Stable'),
            _buildInfoRow('Platform', 'Windows'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ============================================================================
// 閾值編輯對話框（ID 0-18, 共 19 通道）
// ============================================================================

class _ThresholdEditDialog extends StatefulWidget {
  final String title;
  final Color color;
  final Map<int, ThresholdRange> thresholds;
  final Function(Map<int, ThresholdRange>) onSave;
  final Function(ThresholdRange) onApplyToAll;

  const _ThresholdEditDialog({
    required this.title,
    required this.color,
    required this.thresholds,
    required this.onSave,
    required this.onApplyToAll,
  });

  @override
  State<_ThresholdEditDialog> createState() => _ThresholdEditDialogState();
}

class _ThresholdEditDialogState extends State<_ThresholdEditDialog> {
  late Map<int, ThresholdRange> _editedThresholds;
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _editedThresholds = Map.from(widget.thresholds);
    final sample = _editedThresholds[0];
    _minController.text = '${sample?.min ?? 0}';
    _maxController.text = '${sample?.max ?? 0}';
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題列
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 批次設定區
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('min_value'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _maxController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('max_value'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final min = int.tryParse(_minController.text);
                      final max = int.tryParse(_maxController.text);
                      if (min != null && max != null && min <= max) {
                        final range = ThresholdRange(min: min, max: max);
                        setState(() {
                          for (int i = 0; i <= 18; i++) {
                            _editedThresholds[i] = range;
                          }
                        });
                      }
                    },
                    child: Text(tr('apply_to_all')),
                  ),
                ],
              ),
            ),
            // ID 列表 (19 通道)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: 19,
                itemBuilder: (context, index) {
                  final range = _editedThresholds[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: widget.color.withValues(alpha: 0.2),
                      child: Text(
                        '$index',
                        style: TextStyle(fontSize: 12, color: widget.color, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(DisplayNames.getName(index)),
                    subtitle: Text('${range?.min ?? 0} ~ ${range?.max ?? 0}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _showSingleEditDialog(index),
                    ),
                  );
                },
              ),
            ),
            // 按鈕列
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('cancel')),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onSave(_editedThresholds);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.color,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(tr('confirm')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSingleEditDialog(int id) {
    final range = _editedThresholds[id];
    final minCtrl = TextEditingController(text: '${range?.min ?? 0}');
    final maxCtrl = TextEditingController(text: '${range?.max ?? 0}');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tr('edit_threshold')} - ${DisplayNames.getName(id)}'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('min_value'), border: const OutlineInputBorder()),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('~')),
            Expanded(
              child: TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('max_value'), border: const OutlineInputBorder()),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
          ElevatedButton(
            onPressed: () {
              final min = int.tryParse(minCtrl.text);
              final max = int.tryParse(maxCtrl.text);
              if (min != null && max != null && min <= max) {
                setState(() { _editedThresholds[id] = ThresholdRange(min: min, max: max); });
                Navigator.pop(context);
              }
            },
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
  }
}
