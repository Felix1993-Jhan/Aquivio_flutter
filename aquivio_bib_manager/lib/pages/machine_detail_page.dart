import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/machine.dart';
import '../services/api_service.dart';
import '../widgets/ingredient_edit_dialog.dart';

/// 機器詳情頁面
/// 顯示機器資訊和成分列表，可編輯成分

class MachineDetailPage extends StatefulWidget {
  final Machine machine;

  const MachineDetailPage({
    super.key,
    required this.machine,
  });

  @override
  State<MachineDetailPage> createState() => _MachineDetailPageState();
}

class _MachineDetailPageState extends State<MachineDetailPage> {
  final _apiService = ApiService();

  List<Ingredient> _ingredients = [];
  bool _isLoading = true;
  String? _errorMessage;

  // 日期格式化器
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  /// 載入成分列表
  Future<void> _loadIngredients() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final ingredients =
          await _apiService.getMachineIngredients(widget.machine.token);

      if (mounted) {
        setState(() {
          _ingredients = ingredients;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '載入失敗：$e';
          _isLoading = false;
        });
      }
    }
  }

  /// 開啟成分編輯對話框
  Future<void> _openIngredientEditor(Ingredient ingredient) async {
    final result = await showDialog<Ingredient>(
      context: context,
      builder: (context) => IngredientEditDialog(
        ingredient: ingredient,
        dateFormat: _dateFormat,
      ),
    );

    if (result != null) {
      // 更新本地列表
      setState(() {
        final index = _ingredients.indexWhere((i) => i.id == result.id);
        if (index >= 0) {
          _ingredients[index] = result;
        }
      });

      _showSuccess('成分資訊已更新');
    }
  }

  /// 快速標記成分已更換
  Future<void> _quickReplace(Ingredient ingredient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認更換'),
        content: Text('確定要標記「${ingredient.name}」已更換嗎？\n'
            '將重設剩餘量並記錄更換時間。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認更換'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final updated = await _apiService.markIngredientReplaced(
        ingredient.id,
        newAmount: ingredient.capacity,
      );

      // 更新本地列表
      setState(() {
        final index = _ingredients.indexWhere((i) => i.id == ingredient.id);
        if (index >= 0) {
          _ingredients[index] = updated;
        }
      });

      _showSuccess('已標記「${ingredient.name}」已更換');
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('更新失敗：$e');
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.machine.name),
      ),
      body: RefreshIndicator(
        onRefresh: _loadIngredients,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return CustomScrollView(
      slivers: [
        // 機器資訊卡片
        SliverToBoxAdapter(
          child: _MachineInfoCard(
            machine: widget.machine,
          ),
        ),

        // 成分列表標題
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  '成分列表 (BIB)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (!_isLoading)
                  Text(
                    '共 ${_ingredients.length} 項',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),

        // 成分列表
        _buildIngredientList(),
      ],
    );
  }

  Widget _buildIngredientList() {
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadIngredients,
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }

    if (_ingredients.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text('尚無成分資料'),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final ingredient = _ingredients[index];
            return _IngredientCard(
              ingredient: ingredient,
              dateFormat: _dateFormat,
              onEdit: () => _openIngredientEditor(ingredient),
              onQuickReplace: () => _quickReplace(ingredient),
            );
          },
          childCount: _ingredients.length,
        ),
      ),
    );
  }
}

/// 機器資訊卡片
class _MachineInfoCard extends StatelessWidget {
  final Machine machine;

  const _MachineInfoCard({required this.machine});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.local_drink,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        'Token: ${machine.token}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (machine.organization != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.business,
                label: '所屬組織',
                value: machine.organization!.name ?? '未知',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 資訊列
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// 成分卡片
class _IngredientCard extends StatelessWidget {
  final Ingredient ingredient;
  final DateFormat dateFormat;
  final VoidCallback onEdit;
  final VoidCallback onQuickReplace;

  const _IngredientCard({
    required this.ingredient,
    required this.dateFormat,
    required this.onEdit,
    required this.onQuickReplace,
  });

  /// 取得狀態顏色
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'low':
        return Colors.orange;
      case 'empty':
        return Colors.red;
      case 'replaced':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(ingredient.status);
    final percentage = ingredient.remainingPercentage;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題列
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ingredient.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  // 狀態標籤
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      ingredient.statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 剩餘量進度條
              if (ingredient.capacity != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          minHeight: 8,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            percentage > 30
                                ? Colors.green
                                : percentage > 10
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // 詳細資訊
              Row(
                children: [
                  Icon(Icons.water_drop_outlined,
                      size: 14, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '剩餘：${ingredient.remainingAmount?.toStringAsFixed(0) ?? "N/A"} ${ingredient.unit ?? "ml"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  if (ingredient.lastReplacedAt != null) ...[
                    Icon(Icons.schedule, size: 14, color: colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '更換：${dateFormat.format(ingredient.lastReplacedAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // 操作按鈕
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('編輯'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onQuickReplace,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('已更換'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
