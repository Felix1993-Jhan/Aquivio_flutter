import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import 'data_storage_page.dart';

/// 檢測規則頁面（BodyDoor 簡化版）
/// 只有 Arduino Idle 閾值和輪詢參數
class DetectionRulesPage extends StatefulWidget {
  const DetectionRulesPage({super.key});

  @override
  State<DetectionRulesPage> createState() => _DetectionRulesPageState();
}

class _DetectionRulesPageState extends State<DetectionRulesPage> {
  final ThresholdSettingsService _service = ThresholdSettingsService();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: _service.settingsUpdateNotifier,
          builder: (context, _, __) {
            return Scaffold(
              appBar: AppBar(
                title: Text(tr('detection_rules_title')),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: tr('reset_all'),
                    onPressed: _confirmResetAll,
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== 閾值檢測規則 =====
                    _buildSectionTitle(tr('rules_threshold_section'), Icons.speed, Colors.blue),
                    _buildThresholdSection(),

                    const SizedBox(height: 24),

                    // ===== 3.3V 電源異常偵測 =====
                    _buildSectionTitle(tr('rules_33v_section'), Icons.bolt, Colors.orange),
                    _build33vRuleCard(),

                    const SizedBox(height: 16),

                    // ===== Body 12V 電源異常偵測 =====
                    _buildSectionTitle(tr('rules_body12v_section'), Icons.bolt, Colors.deepOrange),
                    _buildBody12vRuleCard(),

                    const SizedBox(height: 16),

                    // ===== Door 24V 升壓電路異常偵測 =====
                    _buildSectionTitle(tr('rules_door24v_section'), Icons.bolt, Colors.purple),
                    _buildDoor24vRuleCard(),

                    const SizedBox(height: 16),

                    // ===== Door 12V 電源異常偵測 =====
                    _buildSectionTitle(tr('rules_door12v_section'), Icons.bolt, Colors.indigo),
                    _buildDoor12vRuleCard(),

                    const SizedBox(height: 24),

                    // ===== 輪詢機制 =====
                    _buildSectionTitle(tr('rules_polling_section'), Icons.refresh, Colors.amber),
                    _buildEditableMultiCard(
                      title: tr('rules_polling_retry_title'),
                      description: tr('rules_polling_retry_desc'),
                      color: Colors.amber.shade700,
                      fields: [
                        _FieldConfig(
                          label: tr('rules_polling_max_retry_label'),
                          value: _service.maxRetryPerID,
                          defaultValue: ThresholdSettingsService.defaultMaxRetryPerID,
                          onSave: (v) => _service.setMaxRetryPerID(v),
                        ),
                        _FieldConfig(
                          label: tr('rules_polling_hw_wait_label'),
                          value: _service.hardwareWaitMs,
                          defaultValue: ThresholdSettingsService.defaultHardwareWaitMs,
                          onSave: (v) => _service.setHardwareWaitMs(v),
                        ),
                      ],
                      onReset: () async {
                        await _service.setMaxRetryPerID(ThresholdSettingsService.defaultMaxRetryPerID);
                        await _service.setHardwareWaitMs(ThresholdSettingsService.defaultHardwareWaitMs);
                        _showResetSnack();
                      },
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================== 閾值檢測區塊 ====================

  Widget _buildThresholdSection() {
    final allThresholds = _service.getAllHardwareThresholds(DeviceType.arduino, StateType.idle);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 4, height: 40,
          decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(tr('rules_arduino_idle_title'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
        subtitle: Text(
          '${tr('rules_arduino_idle_desc')}  (ID 0-18)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: 8),
                // 每個 ID 的閾值列表
                ...List.generate(19, (index) {
                  final range = allThresholds[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                      child: Text(
                        '$index',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(DisplayNames.getName(index)),
                    subtitle: Text('${range?.min ?? 0} ~ ${range?.max ?? 0}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _showSingleIdEditDialog(index),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                // 底部按鈕列
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 批次編輯按鈕
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: Text(tr('apply_to_all')),
                      onPressed: _showBatchEditDialog,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                    ),
                    const SizedBox(width: 8),
                    _buildResetButton(() async {
                      await _service.resetToDefaults();
                      _showResetSnack();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 單一 ID 閾值編輯對話框
  void _showSingleIdEditDialog(int id) {
    final range = _service.getHardwareThreshold(DeviceType.arduino, StateType.idle, id);
    final minCtrl = TextEditingController(text: '${range.min}');
    final maxCtrl = TextEditingController(text: '${range.max}');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tr('edit_threshold')} - ID $id (${DisplayNames.getName(id)})'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: tr('min_value'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~'),
            ),
            Expanded(
              child: TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: tr('max_value'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final min = int.tryParse(minCtrl.text);
              final max = int.tryParse(maxCtrl.text);
              if (min != null && max != null && min <= max && min >= 0 && max <= 1023) {
                _service.setHardwareThreshold(
                  DeviceType.arduino, StateType.idle, id,
                  ThresholdRange(min: min, max: max),
                );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
  }

  /// 批次設定所有 ID 閾值對話框
  void _showBatchEditDialog() {
    final sample = _service.getHardwareThreshold(DeviceType.arduino, StateType.idle, 0);
    final minCtrl = TextEditingController(text: '${sample.min}');
    final maxCtrl = TextEditingController(text: '${sample.max}');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('apply_to_all')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '將所有 ID (0-18) 設定為相同範圍',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: tr('min_value'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~'),
                ),
                Expanded(
                  child: TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: tr('max_value'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final min = int.tryParse(minCtrl.text);
              final max = int.tryParse(maxCtrl.text);
              if (min != null && max != null && min <= max && min >= 0 && max <= 1023) {
                _service.setAllHardwareThresholds(
                  DeviceType.arduino, StateType.idle,
                  ThresholdRange(min: min, max: max),
                );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
  }

  // ==================== 3.3V 電源異常偵測 ====================

  Widget _build33vRuleCard() {
    final checkIds = DisplayNames.power33vCheckIds;
    final idNames = checkIds.map((id) => DisplayNames.getName(id)).join('\n• ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 4, height: 40,
          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(tr('rules_33v_title'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
        subtitle: Text(
          '${tr('rules_33v_desc')}  [< ${_service.power33vThreshold}]',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        initiallyExpanded: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                // 檢測 ID 列表
                Text(
                  tr('rules_33v_ids'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    '• $idNames',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
                const SizedBox(height: 12),
                // 閾值
                _buildThresholdEditor(
                  label: tr('rules_33v_threshold_label'),
                  color: Colors.orange,
                  currentValue: _service.power33vThreshold,
                  onSave: (v) => _service.setPower33vThreshold(v),
                ),
                const SizedBox(height: 12),
                // 觸發條件
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('rules_33v_condition'),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 即時警告
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_active, size: 16, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('rules_33v_action_realtime'),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 檢測結果
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.assignment_turned_in, size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('rules_33v_action_result'),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Body 12V 電源異常偵測 ====================

  Widget _buildBody12vRuleCard() {
    final checkIds = DisplayNames.powerBody12vCheckIds;
    final idNames = checkIds.map((id) => DisplayNames.getName(id)).join('\n• ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.deepOrange.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 4, height: 40,
          decoration: BoxDecoration(color: Colors.deepOrange, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(tr('rules_body12v_title'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
        subtitle: Text(
          '${tr('rules_body12v_desc')}  [< ${_service.powerBody12vThreshold}]',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(tr('rules_body12v_ids'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.deepOrange.shade200),
                  ),
                  child: Text('• $idNames', style: TextStyle(fontSize: 12, color: Colors.deepOrange.shade900)),
                ),
                const SizedBox(height: 12),
                _buildThresholdEditor(
                  label: tr('rules_body12v_threshold_label'),
                  color: Colors.deepOrange,
                  currentValue: _service.powerBody12vThreshold,
                  onSave: (v) => _service.setPowerBody12vThreshold(v),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_tree, size: 16, color: Colors.deepOrange.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_body12v_prerequisite'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade800))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.deepOrange.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_body12v_condition'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_active, size: 16, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_body12v_action_realtime'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.assignment_turned_in, size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_body12v_action_result'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Door 24V 升壓電路異常偵測 ====================

  Widget _buildDoor24vRuleCard() {
    final checkIds = DisplayNames.powerDoor24vCheckIds;
    final idNames = checkIds.map((id) => DisplayNames.getName(id)).join('\n• ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 4, height: 40,
          decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(tr('rules_door24v_title'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
        subtitle: Text(
          '${tr('rules_door24v_desc')}  [< ${_service.powerDoor24vThreshold}]',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(tr('rules_door24v_ids'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Text('• $idNames', style: TextStyle(fontSize: 12, color: Colors.purple.shade900)),
                ),
                const SizedBox(height: 12),
                _buildThresholdEditor(
                  label: tr('rules_door24v_threshold_label'),
                  color: Colors.purple,
                  currentValue: _service.powerDoor24vThreshold,
                  onSave: (v) => _service.setPowerDoor24vThreshold(v),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_door24v_condition'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_active, size: 16, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_door24v_action_realtime'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.assignment_turned_in, size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_door24v_action_result'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Door 12V 電源異常偵測 ====================

  Widget _buildDoor12vRuleCard() {
    final checkIds = DisplayNames.powerDoor12vCheckIds;
    final idNames = checkIds.map((id) => DisplayNames.getName(id)).join('\n• ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 4, height: 40,
          decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(tr('rules_door12v_title'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
        subtitle: Text(
          '${tr('rules_door12v_desc')}  [< ${_service.powerDoor12vThreshold}]',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(tr('rules_door12v_ids'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Text('• $idNames', style: TextStyle(fontSize: 12, color: Colors.indigo.shade900)),
                ),
                const SizedBox(height: 12),
                _buildThresholdEditor(
                  label: tr('rules_door12v_threshold_label'),
                  color: Colors.indigo,
                  currentValue: _service.powerDoor12vThreshold,
                  onSave: (v) => _service.setPowerDoor12vThreshold(v),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.indigo.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_door12v_condition'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_active, size: 16, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_door12v_action_realtime'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.assignment_turned_in, size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('rules_door12v_action_result'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 電源閾值編輯器 ====================

  Widget _buildThresholdEditor({
    required String label,
    required Color color,
    required int currentValue,
    required Future<void> Function(int) onSave,
  }) {
    return Row(
      children: [
        Icon(Icons.speed, size: 16, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Text('$label:  ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        Text('< ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        SizedBox(
          width: 60,
          height: 28,
          child: TextField(
            controller: TextEditingController(text: '$currentValue'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              isDense: true,
              filled: true,
              fillColor: Colors.red.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.red.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.red.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: color, width: 2),
              ),
            ),
            onSubmitted: (text) {
              final v = int.tryParse(text);
              if (v != null && v >= 0 && v <= 1023) {
                onSave(v);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '(0~1023)',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ==================== 通用 Widget 構建 ====================

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildEditableMultiCard({
    required String title,
    required String description,
    required Color color,
    required List<_FieldConfig> fields,
    required VoidCallback onReset,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 4, height: 40,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: 8),
                ...fields.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 160, child: Text(f.label, style: const TextStyle(fontSize: 13))),
                      SizedBox(
                        width: 100,
                        child: _NumberField(
                          label: '',
                          value: f.value,
                          defaultValue: f.defaultValue,
                          onChanged: f.onSave,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${tr('default_value')}: ${f.defaultValue})',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: _buildResetButton(onReset)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton(VoidCallback onReset) {
    return Tooltip(
      message: tr('reset_single'),
      child: IconButton(
        icon: Icon(Icons.restore, color: Colors.grey.shade600, size: 20),
        onPressed: () => _confirmReset(onReset),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }

  // ==================== 對話框 ====================

  void _confirmReset(VoidCallback onReset) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('reset_confirm_title')),
        content: Text(tr('reset_confirm_msg')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
          TextButton(
            onPressed: () { Navigator.pop(ctx); onReset(); },
            child: Text(tr('confirm'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmResetAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('reset_confirm_title')),
        content: Text(tr('reset_all_confirm_msg')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.resetToDefaults();
              _showResetSnack();
            },
            child: Text(tr('confirm'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showResetSnack() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('reset_factory_done')), duration: const Duration(seconds: 1)),
      );
    }
  }
}

// ==================== 欄位設定資料 ====================

class _FieldConfig {
  final String label;
  final int value;
  final int defaultValue;
  final Future<void> Function(int) onSave;

  _FieldConfig({
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.onSave,
  });
}

// ==================== 數值輸入欄位 ====================

class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final int defaultValue;
  final Future<void> Function(int) onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late TextEditingController _controller;
  bool _isModified = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _isModified = widget.value != widget.defaultValue;
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
      _isModified = widget.value != widget.defaultValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
      decoration: InputDecoration(
        labelText: widget.label.isNotEmpty ? widget.label : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: _isModified ? Colors.orange : Colors.grey.shade400,
            width: _isModified ? 2 : 1,
          ),
        ),
      ),
      style: TextStyle(
        fontSize: 14,
        fontWeight: _isModified ? FontWeight.bold : FontWeight.normal,
        color: _isModified ? Colors.orange.shade800 : null,
      ),
      onSubmitted: (text) {
        final v = int.tryParse(text);
        if (v != null) {
          widget.onChanged(v);
          setState(() => _isModified = v != widget.defaultValue);
        }
      },
      onEditingComplete: () {
        final v = int.tryParse(_controller.text);
        if (v != null) {
          widget.onChanged(v);
          setState(() => _isModified = v != widget.defaultValue);
        }
      },
    );
  }
}
