import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket 服務
/// 處理即時通訊，接收機器狀態更新和訂單通知

class WebSocketService {
  // WebSocket 連線位址
  static const String wsUrl = 'ws://localhost:1337/ws';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // 事件監聽器
  final List<Function(WebSocketEvent)> _listeners = [];

  // 連線狀態
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // 自動重連設定
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);

  /// 單例模式
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  /// 連線到 WebSocket 伺服器
  Future<void> connect() async {
    if (_isConnected) {
      return;
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _reconnectAttempts = 0;

      // 監聽訊息
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _notifyListeners(WebSocketEvent(
        type: 'connected',
        payload: {},
      ));
    } catch (e) {
      _isConnected = false;
      _handleReconnect();
    }
  }

  /// 斷開連線
  void disconnect() {
    _shouldReconnect = false;
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  /// 處理接收到的訊息
  void _onMessage(dynamic message) {
    try {
      final data = json.decode(message as String);
      final event = WebSocketEvent(
        type: data['type'] ?? 'unknown',
        payload: data['payload'] ?? data['data'] ?? {},
        timestamp: data['ts'] != null
            ? DateTime.tryParse(data['ts'])
            : DateTime.now(),
      );

      _notifyListeners(event);
    } catch (e) {
      // 解析失敗，忽略此訊息
    }
  }

  /// 處理錯誤
  void _onError(dynamic error) {
    _isConnected = false;
    _notifyListeners(WebSocketEvent(
      type: 'error',
      payload: {'message': error.toString()},
    ));
    _handleReconnect();
  }

  /// 處理連線結束
  void _onDone() {
    _isConnected = false;
    _notifyListeners(WebSocketEvent(
      type: 'disconnected',
      payload: {},
    ));
    _handleReconnect();
  }

  /// 處理自動重連
  void _handleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _notifyListeners(WebSocketEvent(
        type: 'reconnect_failed',
        payload: {'attempts': _reconnectAttempts},
      ));
      return;
    }

    _reconnectAttempts++;
    Future.delayed(reconnectDelay, () {
      if (_shouldReconnect && !_isConnected) {
        connect();
      }
    });
  }

  /// 新增事件監聽器
  void addListener(Function(WebSocketEvent) listener) {
    _listeners.add(listener);
  }

  /// 移除事件監聽器
  void removeListener(Function(WebSocketEvent) listener) {
    _listeners.remove(listener);
  }

  /// 通知所有監聽器
  void _notifyListeners(WebSocketEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }

  /// 發送訊息到伺服器
  void send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode(data));
    }
  }
}

/// WebSocket 事件資料模型
class WebSocketEvent {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime? timestamp;

  WebSocketEvent({
    required this.type,
    required this.payload,
    this.timestamp,
  });

  /// 事件類型常數
  static const String machineStatusUpdated = 'machine_status_updated';
  static const String orderCreated = 'order_created';
  static const String paymentCompleted = 'payment_completed';

  /// 取得事件描述
  String get description {
    switch (type) {
      case machineStatusUpdated:
        return '機器狀態已更新';
      case orderCreated:
        return '新訂單已建立';
      case paymentCompleted:
        return '支付已完成';
      case 'connected':
        return '已連線';
      case 'disconnected':
        return '已斷線';
      case 'error':
        return '連線錯誤';
      default:
        return type;
    }
  }
}
