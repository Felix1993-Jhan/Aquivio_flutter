import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/machine.dart';
import '../services/api_service.dart';

/// 成分編輯對話框
/// 可修改剩餘量、狀態、最後更換時間

class IngredientEditDialog extends StatefulWidget {
  final Ingredient ingredient;
  final DateFormat dateFormat;

  const IngredientEditDialog({
    super.key,
    required this.ingredient,
    required this.dateFormat,
  });

  @override
  State<IngredientEditDialog> createState() => _IngredientEditDialogState();
}

class _IngredientEditDialogState extends State<IngredientEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  late TextEditingController _remainingAmountController;
  late String? _selectedStatus;
  late DateTime? _lastReplacedAt;

  bool _isLoading = false;

  // 狀態選項
  final List<Map<String, String>> _statusOptions = [
    {'value': 'active', 'label': '正常'},
    {'value': 'low', 'label': '即將耗盡'},
    {'value': 'empty', 'label': '已空'},
    {'value': 'replaced', 'label': '已更換'},
  ];

  @override
  void initState() {
    super.initState();
    _remainingAmountController = TextEditingController(
      text: widget.ingredient.remainingAmount?.toStringAsFixed(0) ?? '',
    );
    _selectedStatus = widget.ingredient.status;
    _lastReplacedAt = widget.ingredient.lastReplacedAt;
  }

  @override
  void dispose() {
    _remainingAmountController.dispose();
    super.dispose();
  }

  /// 選擇日期時間
  Future<void> _selectDateTime() async {
    // 選擇日期
    final date = await showDatePicker(
      context: context,
      initialDate: _lastReplacedAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'TW'),
    );

    if (date == null || !mounted) return;

    // 選擇時間
    final time = await showTimePicker(
      // ignore: use_build_context_synchronously
      context: context,
      initialTime: TimeOfDay.fromDateTime(_lastReplacedAt ?? DateTime.now()),
    );

    if (time == null) return;

    setState(() {
      _lastReplacedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  /// 設定為現在時間
  void _setToNow() {
    setState(() {
      _lastReplacedAt = DateTime.now();
    });
  }

  /// 儲存變更
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = <String, dynamic>{};

      // 剩餘量
      final amount = double.tryParse(_remainingAmountController.text);
      if (amount != null) {
        data['remainingAmount'] = amount;
      }

      // 狀態
      if (_selectedStatus != null) {
        data['status'] = _selectedStatus;
      }

      // 最後更換時間
      if (_lastReplacedAt != null) {
        data['lastReplacedAt'] = _lastReplacedAt!.toIso8601String();
      }

      // 呼叫 API 更新
      final updated =
          await _apiService.updateIngredient(widget.ingredient.id, data);

      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('儲存失敗：$e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 標題
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.edit,
                        color: colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '編輯成分',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            widget.ingredient.name,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 剩餘量輸入
                TextFormField(
                  controller: _remainingAmountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '剩餘量',
                    suffixText: widget.ingredient.unit ?? 'ml',
                    border: const OutlineInputBorder(),
                    helperText:
                        '容量：${widget.ingredient.capacity?.toStringAsFixed(0) ?? "未知"} ${widget.ingredient.unit ?? "ml"}',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '請輸入剩餘量';
                    }
                    final amount = double.tryParse(value);
                    if (amount == null) {
                      return '請輸入有效數字';
                    }
                    if (amount < 0) {
                      return '剩餘量不能為負數';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 狀態選擇
                DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
                  decoration: const InputDecoration(
                    labelText: '狀態',
                    border: OutlineInputBorder(),
                  ),
                  items: _statusOptions.map((option) {
                    return DropdownMenuItem<String>(
                      value: option['value'],
                      child: Text(option['label']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // 最後更換時間
                InkWell(
                  onTap: _selectDateTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '最後更換時間',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _lastReplacedAt != null
                              ? widget.dateFormat.format(_lastReplacedAt!)
                              : '點擊選擇',
                          style: TextStyle(
                            color: _lastReplacedAt != null
                                ? null
                                : colorScheme.outline,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _setToNow,
                              child: const Text('現在'),
                            ),
                            const Icon(Icons.calendar_today, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 操作按鈕
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isLoading ? null : _save,
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('儲存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
