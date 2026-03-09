import 'package:flutter/material.dart';
import '../models/machine.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'login_page.dart';
import 'machine_detail_page.dart';

/// 機器列表頁面
/// 顯示所有飲料機，支援下拉刷新

class MachineListPage extends StatefulWidget {
  const MachineListPage({super.key});

  @override
  State<MachineListPage> createState() => _MachineListPageState();
}

class _MachineListPageState extends State<MachineListPage> {
  final _apiService = ApiService();
  final _wsService = WebSocketService();

  List<Machine> _machines = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMachines();
    _setupWebSocket();
  }

  @override
  void dispose() {
    _wsService.removeListener(_onWebSocketEvent);
    super.dispose();
  }

  /// 設定 WebSocket 監聽
  void _setupWebSocket() {
    _wsService.addListener(_onWebSocketEvent);
    _wsService.connect();
  }

  /// WebSocket 事件處理
  void _onWebSocketEvent(WebSocketEvent event) {
    if (event.type == WebSocketEvent.machineStatusUpdated) {
      // 機器狀態更新時重新載入列表
      _loadMachines();
      _showNotification('機器狀態已更新');
    } else if (event.type == WebSocketEvent.orderCreated) {
      _showNotification('新訂單已建立');
    }
  }

  /// 顯示通知
  void _showNotification(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 載入機器列表
  Future<void> _loadMachines() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final machines = await _apiService.getMachines(locale: 'zh-Hant');

      if (mounted) {
        setState(() {
          _machines = machines;
          _isLoading = false;
        });
      }
    } on UnauthorizedException catch (_) {
      // Token 過期或無效，導回登入頁
      _handleUnauthorized();
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

  /// 處理未授權（登出）
  Future<void> _handleUnauthorized() async {
    await _apiService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  /// 登出
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認登出'),
        content: const Text('確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _wsService.disconnect();
      await _handleUnauthorized();
    }
  }

  /// 導航到機器詳情頁
  void _navigateToDetail(Machine machine) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MachineDetailPage(machine: machine),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('飲料機列表'),
        actions: [
          // WebSocket 連線狀態指示
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _wsService.isConnected ? Icons.wifi : Icons.wifi_off,
              color: _wsService.isConnected ? Colors.green : Colors.grey,
              size: 20,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadMachines,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      );
    }

    if (_machines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_drink_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '尚無飲料機資料',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMachines,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _machines.length,
        itemBuilder: (context, index) {
          return _MachineCard(
            machine: _machines[index],
            onTap: () => _navigateToDetail(_machines[index]),
          );
        },
      ),
    );
  }
}

/// 機器卡片元件
class _MachineCard extends StatelessWidget {
  final Machine machine;
  final VoidCallback onTap;

  const _MachineCard({
    required this.machine,
    required this.onTap,
  });

  /// 取得狀態顏色
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'maintenance':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// 取得狀態文字
  String _getStatusText(String? status) {
    switch (status) {
      case 'active':
        return '運作中';
      case 'inactive':
        return '停用';
      case 'maintenance':
        return '維護中';
      case 'error':
        return '異常';
      default:
        return '未知';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(machine.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 機器圖示
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_drink,
                  color: colorScheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // 機器資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      machine.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Token: ${machine.token}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),

              // 狀態標籤
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStatusText(machine.status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
