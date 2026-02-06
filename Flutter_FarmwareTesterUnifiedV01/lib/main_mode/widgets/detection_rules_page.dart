import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_firmware_tester_unified/shared/services/localization_service.dart';
import '../services/threshold_settings_service.dart';

/// 檢測規則頁面（可編輯版本）
/// 顯示所有自動檢測的規則和閾值設定，支援修改、儲存、恢復原廠
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
      builder: (context, _, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _service.settingsUpdateNotifier,
          builder: (context, _, _) {
            return Scaffold(
              appBar: AppBar(
                title: Text(tr('detection_rules_title')),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                actions: [
                  // 全部恢復原廠按鈕
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

                    // ===== 短路測試規則 =====
                    _buildSectionTitle(tr('rules_short_circuit_section'), Icons.flash_on, Colors.orange),
                    _buildShortCircuitSection(),

                    const SizedBox(height: 24),

                    // ===== 診斷偵測規則 =====
                    _buildSectionTitle(tr('rules_diagnostic_section'), Icons.medical_services, Colors.teal),
                    _buildDiagnosticSection(),

                    const SizedBox(height: 24),

                    // ===== 感測器檢測規則 =====
                    _buildSectionTitle(tr('rules_sensor_section'), Icons.sensors, Colors.cyan),
                    _buildSensorSection(),

                    const SizedBox(height: 24),

                    // ===== 輪詢機制（可編輯）=====
                    _buildSectionTitle(tr('rules_polling_section'), Icons.refresh, Colors.amber),
                    _buildEditableMultiCard(
                      title: tr('rules_polling_retry_title'),
                      description: tr('rules_polling_retry_desc'),
                      color: Colors.amber.shade700,
                      fields: [
                        _FieldConfig(label: tr('rules_polling_max_retry_label'), value: _service.maxRetryPerID,
                          defaultValue: ThresholdSettingsService.defaultMaxRetryPerID,
                          onSave: (v) => _service.setMaxRetryPerID(v)),
                        _FieldConfig(label: tr('rules_polling_hw_wait_label'), value: _service.hardwareWaitMs,
                          defaultValue: ThresholdSettingsService.defaultHardwareWaitMs,
                          onSave: (v) => _service.setHardwareWaitMs(v)),
                        _FieldConfig(label: tr('rules_polling_sensor_wait_label'), value: _service.sensorWaitMs,
                          defaultValue: ThresholdSettingsService.defaultSensorWaitMs,
                          onSave: (v) => _service.setSensorWaitMs(v)),
                      ],
                      onReset: () async {
                        await _service.setMaxRetryPerID(ThresholdSettingsService.defaultMaxRetryPerID);
                        await _service.setHardwareWaitMs(ThresholdSettingsService.defaultHardwareWaitMs);
                        await _service.setSensorWaitMs(ThresholdSettingsService.defaultSensorWaitMs);
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
    final arduinoIdle = _service.getHardwareThreshold(DeviceType.arduino, StateType.idle, 0);
    final arduinoRunning = _service.getHardwareThreshold(DeviceType.arduino, StateType.running, 0);
    final stm32Idle = _service.getHardwareThreshold(DeviceType.stm32, StateType.idle, 0);
    final stm32Running = _service.getHardwareThreshold(DeviceType.stm32, StateType.running, 0);

    return Column(
      children: [
        _buildEditableRangeCard(
          title: tr('rules_arduino_idle_title'),
          description: tr('rules_arduino_idle_desc'),
          color: Colors.green,
          minValue: arduinoIdle.min,
          maxValue: arduinoIdle.max,
          defaultMin: 770,
          defaultMax: 830,
          onSave: (min, max) => _service.setAllHardwareThresholds(
            DeviceType.arduino, StateType.idle, ThresholdRange(min: min, max: max)),
          onReset: () async {
            await _service.resetCategoryToDefaults(DeviceType.arduino, StateType.idle);
            _showResetSnack();
          },
        ),
        _buildEditableRangeCard(
          title: tr('rules_arduino_running_title'),
          description: tr('rules_arduino_running_desc'),
          color: Colors.green,
          minValue: arduinoRunning.min,
          maxValue: arduinoRunning.max,
          defaultMin: 25,
          defaultMax: 60,
          onSave: (min, max) => _service.setAllHardwareThresholds(
            DeviceType.arduino, StateType.running, ThresholdRange(min: min, max: max)),
          onReset: () async {
            await _service.resetCategoryToDefaults(DeviceType.arduino, StateType.running);
            _showResetSnack();
          },
        ),
        _buildEditableRangeCard(
          title: tr('rules_stm32_idle_title'),
          description: tr('rules_stm32_idle_desc'),
          color: Colors.blue,
          minValue: stm32Idle.min,
          maxValue: stm32Idle.max,
          defaultMin: 0,
          defaultMax: 55,
          onSave: (min, max) => _service.setAllHardwareThresholds(
            DeviceType.stm32, StateType.idle, ThresholdRange(min: min, max: max)),
          onReset: () async {
            await _service.resetCategoryToDefaults(DeviceType.stm32, StateType.idle);
            _showResetSnack();
          },
        ),
        _buildEditableRangeCard(
          title: tr('rules_stm32_running_title'),
          description: tr('rules_stm32_running_desc'),
          color: Colors.blue,
          minValue: stm32Running.min,
          maxValue: stm32Running.max,
          defaultMin: 300,
          defaultMax: 380,
          onSave: (min, max) => _service.setAllHardwareThresholds(
            DeviceType.stm32, StateType.running, ThresholdRange(min: min, max: max)),
          onReset: () async {
            await _service.resetCategoryToDefaults(DeviceType.stm32, StateType.running);
            _showResetSnack();
          },
        ),
      ],
    );
  }

  // ==================== 短路測試區塊 ====================

  Widget _buildShortCircuitSection() {
    return Column(
      children: [
        // VDD 短路 - 唯讀說明
        _buildReadOnlyCard(
          title: tr('rules_vdd_short_title'),
          description: tr('rules_vdd_short_desc'),
          rules: [
            tr('rules_vdd_short_cond1'),
            tr('rules_vdd_short_cond2'),
            tr('rules_vdd_short_reason'),
          ],
          color: Colors.deepOrange,
        ),
        // D-12V 短路 - 可編輯閾值
        _buildEditableSingleCard(
          title: tr('rules_d12v_short_title'),
          description: tr('rules_d12v_short_desc'),
          color: Colors.red.shade800,
          label: 'Arduino ADC >',
          value: _service.d12vShortArduinoThreshold,
          defaultValue: ThresholdSettingsService.defaultD12vShortArduinoThreshold,
          onSave: (v) => _service.setD12vShortArduinoThreshold(v),
          onReset: () async {
            await _service.setD12vShortArduinoThreshold(ThresholdSettingsService.defaultD12vShortArduinoThreshold);
            _showResetSnack();
          },
          extraRules: [
            tr('rules_d12v_short_reason'),
          ],
        ),
        // 相鄰短路 - 可編輯閾值
        _buildEditableSingleCard(
          title: tr('rules_adjacent_short_title'),
          description: tr('rules_adjacent_short_desc'),
          color: Colors.indigo,
          label: tr('rules_adjacent_short_label'),
          value: _service.adjacentShortThreshold,
          defaultValue: ThresholdSettingsService.defaultAdjacentShortThreshold,
          onSave: (v) => _service.setAdjacentShortThreshold(v),
          onReset: () async {
            await _service.setAdjacentShortThreshold(ThresholdSettingsService.defaultAdjacentShortThreshold);
            _showResetSnack();
          },
          extraRules: [
            tr('rules_adjacent_short_method'),
          ],
        ),
      ],
    );
  }

  // ==================== 診斷偵測區塊 ====================

  Widget _buildDiagnosticSection() {
    return Column(
      children: [
        // 負載未連接
        _buildEditableMultiCard(
          title: tr('rules_load_disconnected_title'),
          description: tr('rules_load_disconnected_desc'),
          color: Colors.grey,
          fields: [
            _FieldConfig(label: 'Arduino Diff <', value: _service.arduinoDiffThreshold,
              defaultValue: ThresholdSettingsService.defaultArduinoDiffThreshold,
              onSave: (v) => _service.setArduinoDiffThreshold(v)),
            _FieldConfig(label: 'STM32 Running Min', value: _service.loadDisconnectedStm32RunningMin,
              defaultValue: ThresholdSettingsService.defaultLoadDisconnectedStm32RunningMin,
              onSave: (v) => _service.setLoadDisconnectedStm32RunningMin(v)),
            _FieldConfig(label: 'STM32 Running Max', value: _service.loadDisconnectedStm32RunningMax,
              defaultValue: ThresholdSettingsService.defaultLoadDisconnectedStm32RunningMax,
              onSave: (v) => _service.setLoadDisconnectedStm32RunningMax(v)),
          ],
          onReset: () async {
            await _service.setArduinoDiffThreshold(ThresholdSettingsService.defaultArduinoDiffThreshold);
            await _service.setLoadDisconnectedStm32RunningMin(ThresholdSettingsService.defaultLoadDisconnectedStm32RunningMin);
            await _service.setLoadDisconnectedStm32RunningMax(ThresholdSettingsService.defaultLoadDisconnectedStm32RunningMax);
            _showResetSnack();
          },
        ),
        // G-D 短路
        _buildEditableMultiCard(
          title: tr('rules_gd_short_title'),
          description: tr('rules_gd_short_desc'),
          color: Colors.purple,
          fields: [
            _FieldConfig(label: 'Arduino Running Min', value: _service.gdShortArduinoRunningMin,
              defaultValue: ThresholdSettingsService.defaultGdShortArduinoRunningMin,
              onSave: (v) => _service.setGdShortArduinoRunningMin(v)),
            _FieldConfig(label: 'Arduino Running Max', value: _service.gdShortArduinoRunningMax,
              defaultValue: ThresholdSettingsService.defaultGdShortArduinoRunningMax,
              onSave: (v) => _service.setGdShortArduinoRunningMax(v)),
            _FieldConfig(label: 'STM32 Running Min', value: _service.gdShortStm32RunningMin,
              defaultValue: ThresholdSettingsService.defaultGdShortStm32RunningMin,
              onSave: (v) => _service.setGdShortStm32RunningMin(v)),
            _FieldConfig(label: 'STM32 Running Max', value: _service.gdShortStm32RunningMax,
              defaultValue: ThresholdSettingsService.defaultGdShortStm32RunningMax,
              onSave: (v) => _service.setGdShortStm32RunningMax(v)),
          ],
          onReset: () async {
            await _service.setGdShortArduinoRunningMin(ThresholdSettingsService.defaultGdShortArduinoRunningMin);
            await _service.setGdShortArduinoRunningMax(ThresholdSettingsService.defaultGdShortArduinoRunningMax);
            await _service.setGdShortStm32RunningMin(ThresholdSettingsService.defaultGdShortStm32RunningMin);
            await _service.setGdShortStm32RunningMax(ThresholdSettingsService.defaultGdShortStm32RunningMax);
            _showResetSnack();
          },
        ),
        // D-S 短路
        _buildEditableMultiCard(
          title: tr('rules_ds_short_title'),
          description: tr('rules_ds_short_desc'),
          color: Colors.purple,
          fields: [
            _FieldConfig(label: 'Arduino Idle Min', value: _service.dsShortArduinoIdleMin,
              defaultValue: ThresholdSettingsService.defaultDsShortArduinoIdleMin,
              onSave: (v) => _service.setDsShortArduinoIdleMin(v)),
            _FieldConfig(label: 'Arduino Idle Max', value: _service.dsShortArduinoIdleMax,
              defaultValue: ThresholdSettingsService.defaultDsShortArduinoIdleMax,
              onSave: (v) => _service.setDsShortArduinoIdleMax(v)),
            _FieldConfig(label: 'STM32 Idle Min', value: _service.dsShortStm32IdleMin,
              defaultValue: ThresholdSettingsService.defaultDsShortStm32IdleMin,
              onSave: (v) => _service.setDsShortStm32IdleMin(v)),
            _FieldConfig(label: 'STM32 Idle Max', value: _service.dsShortStm32IdleMax,
              defaultValue: ThresholdSettingsService.defaultDsShortStm32IdleMax,
              onSave: (v) => _service.setDsShortStm32IdleMax(v)),
          ],
          onReset: () async {
            await _service.setDsShortArduinoIdleMin(ThresholdSettingsService.defaultDsShortArduinoIdleMin);
            await _service.setDsShortArduinoIdleMax(ThresholdSettingsService.defaultDsShortArduinoIdleMax);
            await _service.setDsShortStm32IdleMin(ThresholdSettingsService.defaultDsShortStm32IdleMin);
            await _service.setDsShortStm32IdleMax(ThresholdSettingsService.defaultDsShortStm32IdleMax);
            _showResetSnack();
          },
        ),
        // D 極接地 - 可編輯閾值
        _buildEditableSingleCard(
          title: tr('rules_d_grounded_title'),
          description: tr('rules_d_grounded_desc'),
          color: Colors.purple,
          label: tr('rules_d_grounded_label'),
          value: _service.arduinoVssThreshold,
          defaultValue: ThresholdSettingsService.defaultArduinoVssThreshold,
          onSave: (v) => _service.setArduinoVssThreshold(v),
          onReset: () async {
            await _service.setArduinoVssThreshold(ThresholdSettingsService.defaultArduinoVssThreshold);
            _showResetSnack();
          },
          extraRules: [
            tr('rules_d_grounded_feature'),
          ],
        ),
        // G 極接地 - 可編輯閾值
        _buildEditableMultiCard(
          title: tr('rules_g_grounded_title'),
          description: tr('rules_g_grounded_desc'),
          color: Colors.purple,
          fields: [
            _FieldConfig(label: 'Arduino Idle ≥', value: _service.arduinoIdleNormalMin,
              defaultValue: ThresholdSettingsService.defaultArduinoIdleNormalMin,
              onSave: (v) => _service.setArduinoIdleNormalMin(v)),
            _FieldConfig(label: 'STM32 Idle <', value: _service.loadDetectionIdleThreshold,
              defaultValue: ThresholdSettingsService.defaultLoadDetectionIdleThreshold,
              onSave: (v) => _service.setLoadDetectionIdleThreshold(v)),
            _FieldConfig(label: 'STM32 Running <', value: _service.loadDetectionRunningThreshold,
              defaultValue: ThresholdSettingsService.defaultLoadDetectionRunningThreshold,
              onSave: (v) => _service.setLoadDetectionRunningThreshold(v)),
          ],
          onReset: () async {
            await _service.setArduinoIdleNormalMin(ThresholdSettingsService.defaultArduinoIdleNormalMin);
            await _service.setLoadDetectionIdleThreshold(ThresholdSettingsService.defaultLoadDetectionIdleThreshold);
            await _service.setLoadDetectionRunningThreshold(ThresholdSettingsService.defaultLoadDetectionRunningThreshold);
            _showResetSnack();
          },
        ),
        // G-S 短路
        _buildEditableSingleCard(
          title: tr('rules_gs_short_title'),
          description: tr('rules_gs_short_desc'),
          color: Colors.purple,
          label: 'STM32 Running >',
          value: _service.gsShortRunningThreshold,
          defaultValue: ThresholdSettingsService.defaultGsShortRunningThreshold,
          onSave: (v) => _service.setGsShortRunningThreshold(v),
          onReset: () async {
            await _service.setGsShortRunningThreshold(ThresholdSettingsService.defaultGsShortRunningThreshold);
            _showResetSnack();
          },
        ),
        // 線材錯誤
        _buildEditableSingleCard(
          title: tr('rules_wire_error_title'),
          description: tr('rules_wire_error_desc'),
          color: Colors.brown,
          label: 'Arduino Diff <',
          value: _service.wireErrorDiffThreshold,
          defaultValue: ThresholdSettingsService.defaultWireErrorDiffThreshold,
          onSave: (v) => _service.setWireErrorDiffThreshold(v),
          onReset: () async {
            await _service.setWireErrorDiffThreshold(ThresholdSettingsService.defaultWireErrorDiffThreshold);
            _showResetSnack();
          },
        ),
      ],
    );
  }

  // ==================== 感測器區塊 ====================

  Widget _buildSensorSection() {
    return Column(
      children: [
        // Flow
        _buildEditableRangeCard(
          title: tr('rules_sensor_flow_title'),
          description: tr('rules_sensor_flow_desc'),
          color: Colors.cyan,
          minValue: _service.getSensorThreshold(DeviceType.stm32, 18).min,
          maxValue: _service.getSensorThreshold(DeviceType.stm32, 18).max,
          defaultMin: 0,
          defaultMax: 10000,
          onSave: (min, max) async {
            await _service.setSensorThreshold(DeviceType.arduino, 18, ThresholdRange(min: min, max: max));
            await _service.setSensorThreshold(DeviceType.stm32, 18, ThresholdRange(min: min, max: max));
          },
          onReset: () async {
            await _service.setSensorThreshold(DeviceType.arduino, 18, const ThresholdRange(min: 0, max: 10000));
            await _service.setSensorThreshold(DeviceType.stm32, 18, const ThresholdRange(min: 0, max: 10000));
            _showResetSnack();
          },
        ),
        // PressureCO2
        _buildSensorDualRangeCard(
          title: tr('rules_sensor_pressure_co2_title'),
          description: tr('rules_sensor_pressure_co2_desc'),
          color: Colors.cyan,
          sensorId: 19,
          defaultArduinoRange: const ThresholdRange(min: 190, max: 260),
          defaultStm32Range: const ThresholdRange(min: 930, max: 980),
        ),
        // PressureWater
        _buildSensorDualRangeCard(
          title: tr('rules_sensor_pressure_water_title'),
          description: tr('rules_sensor_pressure_water_desc'),
          color: Colors.cyan,
          sensorId: 20,
          defaultArduinoRange: const ThresholdRange(min: 190, max: 260),
          defaultStm32Range: const ThresholdRange(min: 930, max: 980),
        ),
        // MCUtemp
        _buildSensorDualRangeCard(
          title: tr('rules_sensor_mcu_temp_title'),
          description: tr('rules_sensor_mcu_temp_desc'),
          color: Colors.cyan,
          sensorId: 21,
          defaultArduinoRange: const ThresholdRange(min: -20, max: 100),
          defaultStm32Range: const ThresholdRange(min: -20, max: 100),
        ),
        // WATERtemp (STM32 only)
        _buildEditableRangeCard(
          title: tr('rules_sensor_water_temp_title'),
          description: tr('rules_sensor_water_temp_desc'),
          color: Colors.cyan,
          minValue: _service.getSensorThreshold(DeviceType.stm32, 22).min,
          maxValue: _service.getSensorThreshold(DeviceType.stm32, 22).max,
          defaultMin: -20,
          defaultMax: 100,
          onSave: (min, max) => _service.setSensorThreshold(DeviceType.stm32, 22, ThresholdRange(min: min, max: max)),
          onReset: () async {
            await _service.setSensorThreshold(DeviceType.stm32, 22, const ThresholdRange(min: -20, max: 100));
            _showResetSnack();
          },
        ),
        // BIBtemp (STM32 only)
        _buildEditableRangeCard(
          title: tr('rules_sensor_bib_temp_title'),
          description: tr('rules_sensor_bib_temp_desc'),
          color: Colors.cyan,
          minValue: _service.getSensorThreshold(DeviceType.stm32, 23).min,
          maxValue: _service.getSensorThreshold(DeviceType.stm32, 23).max,
          defaultMin: -20,
          defaultMax: 100,
          onSave: (min, max) => _service.setSensorThreshold(DeviceType.stm32, 23, ThresholdRange(min: min, max: max)),
          onReset: () async {
            await _service.setSensorThreshold(DeviceType.stm32, 23, const ThresholdRange(min: -20, max: 100));
            _showResetSnack();
          },
        ),
        // 溫度感測器異常值
        _buildEditableSingleCard(
          title: tr('rules_sensor_temp_error_title'),
          description: tr('rules_sensor_temp_error_desc'),
          color: Colors.red,
          label: tr('rules_sensor_temp_error_label'),
          value: _service.tempSensorErrorValue,
          defaultValue: ThresholdSettingsService.defaultTempSensorErrorValue,
          onSave: (v) => _service.setTempSensorErrorValue(v),
          onReset: () async {
            await _service.setTempSensorErrorValue(ThresholdSettingsService.defaultTempSensorErrorValue);
            _showResetSnack();
          },
        ),
      ],
    );
  }

  // ==================== 感測器雙範圍卡片（Arduino + STM32 分開）====================

  Widget _buildSensorDualRangeCard({
    required String title,
    required String description,
    required Color color,
    required int sensorId,
    required ThresholdRange defaultArduinoRange,
    required ThresholdRange defaultStm32Range,
  }) {
    final arduinoRange = _service.getSensorThreshold(DeviceType.arduino, sensorId);
    final stm32Range = _service.getSensorThreshold(DeviceType.stm32, sensorId);

    return _buildEditableMultiCard(
      title: title,
      description: description,
      color: color,
      fields: [
        _FieldConfig(label: 'Arduino Min', value: arduinoRange.min,
          defaultValue: defaultArduinoRange.min,
          onSave: (v) => _service.setSensorThreshold(DeviceType.arduino, sensorId,
            ThresholdRange(min: v, max: arduinoRange.max))),
        _FieldConfig(label: 'Arduino Max', value: arduinoRange.max,
          defaultValue: defaultArduinoRange.max,
          onSave: (v) => _service.setSensorThreshold(DeviceType.arduino, sensorId,
            ThresholdRange(min: arduinoRange.min, max: v))),
        _FieldConfig(label: 'STM32 Min', value: stm32Range.min,
          defaultValue: defaultStm32Range.min,
          onSave: (v) => _service.setSensorThreshold(DeviceType.stm32, sensorId,
            ThresholdRange(min: v, max: stm32Range.max))),
        _FieldConfig(label: 'STM32 Max', value: stm32Range.max,
          defaultValue: defaultStm32Range.max,
          onSave: (v) => _service.setSensorThreshold(DeviceType.stm32, sensorId,
            ThresholdRange(min: stm32Range.min, max: v))),
      ],
      onReset: () async {
        await _service.setSensorThreshold(DeviceType.arduino, sensorId, defaultArduinoRange);
        await _service.setSensorThreshold(DeviceType.stm32, sensorId, defaultStm32Range);
        _showResetSnack();
      },
    );
  }

  // ==================== 通用 Widget 構建 ====================

  /// 區塊標題
  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 唯讀規則卡片（不可編輯）
  Widget _buildReadOnlyCard({
    required String title,
    required String description,
    required List<String> rules,
    required Color color,
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                ...rules.map((rule) => _buildRuleBullet(rule, color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 可編輯範圍卡片（min ~ max）
  Widget _buildEditableRangeCard({
    required String title,
    required String description,
    required Color color,
    required int minValue,
    required int maxValue,
    required int defaultMin,
    required int defaultMax,
    required Future<void> Function(int min, int max) onSave,
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
        subtitle: Text(
          '$description  [$minValue ~ $maxValue]',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: tr('min_label'),
                        value: minValue,
                        defaultValue: defaultMin,
                        onChanged: (v) => onSave(v, maxValue),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('~', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: _NumberField(
                        label: tr('max_label'),
                        value: maxValue,
                        defaultValue: defaultMax,
                        onChanged: (v) => onSave(minValue, v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildResetButton(onReset),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 可編輯單一數值卡片
  Widget _buildEditableSingleCard({
    required String title,
    required String description,
    required Color color,
    required String label,
    required int value,
    required int defaultValue,
    required Future<void> Function(int) onSave,
    required VoidCallback onReset,
    List<String>? extraRules,
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
        subtitle: Text(
          '$description  [$label $value]',
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
                Row(
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: _NumberField(
                        label: tr('value_label'),
                        value: value,
                        defaultValue: defaultValue,
                        onChanged: onSave,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildResetButton(onReset),
                  ],
                ),
                if (extraRules != null) ...[
                  const SizedBox(height: 8),
                  ...extraRules.map((r) => _buildRuleBullet(r, color)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 可編輯多欄位卡片
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
                      SizedBox(
                        width: 160,
                        child: Text(f.label, style: const TextStyle(fontSize: 13)),
                      ),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildResetButton(onReset),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 規則項目（圓點）
  Widget _buildRuleBullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// 恢復原廠按鈕
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onReset();
            },
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel')),
          ),
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
