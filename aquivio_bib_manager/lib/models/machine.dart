// 機器資料模型
// 用於表示 Aquivio 飲料機的基本資訊

class Machine {
  final int id;
  final String name;
  final String token;
  final String? status;
  final Organization? organization;
  final List<Ingredient> ingredients;

  Machine({
    required this.id,
    required this.name,
    required this.token,
    this.status,
    this.organization,
    this.ingredients = const [],
  });

  /// 從 JSON 建立 Machine 物件
  factory Machine.fromJson(Map<String, dynamic> json) {
    // 處理 Strapi 回傳格式（可能有 data 包裝或直接資料）
    final data = json['data'] ?? json;
    final attributes = data['attributes'] ?? data;

    return Machine(
      id: data['id'] ?? 0,
      name: attributes['name'] ?? '未知機器',
      token: attributes['token'] ?? '',
      status: attributes['status'],
      organization: attributes['organization'] != null
          ? Organization.fromJson(attributes['organization'])
          : null,
      ingredients: (attributes['ingredients'] as List<dynamic>?)
              ?.map((e) => Ingredient.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// 轉換為 JSON 格式
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'token': token,
      'status': status,
    };
  }
}

/// 組織資料模型
class Organization {
  final int id;
  final String? name;
  final String? language;

  Organization({
    required this.id,
    this.name,
    this.language,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final attributes = data['attributes'] ?? data;

    return Organization(
      id: data['id'] ?? 0,
      name: attributes['name'],
      language: attributes['language'],
    );
  }
}

/// 成分/原料包 (BIB) 資料模型
class Ingredient {
  final int id;
  final String name;
  final double? remainingAmount; // 剩餘量
  final String? status; // 狀態：active, low, empty, replaced
  final DateTime? lastReplacedAt; // 最後更換時間
  final String? unit; // 單位（ml, g 等）
  final double? capacity; // 容量

  Ingredient({
    required this.id,
    required this.name,
    this.remainingAmount,
    this.status,
    this.lastReplacedAt,
    this.unit,
    this.capacity,
  });

  /// 從 JSON 建立 Ingredient 物件
  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final attributes = data['attributes'] ?? data;

    return Ingredient(
      id: data['id'] ?? 0,
      name: attributes['name'] ?? '未知成分',
      remainingAmount: (attributes['remainingAmount'] as num?)?.toDouble(),
      status: attributes['status'],
      lastReplacedAt: attributes['lastReplacedAt'] != null
          ? DateTime.tryParse(attributes['lastReplacedAt'])
          : null,
      unit: attributes['unit'],
      capacity: (attributes['capacity'] as num?)?.toDouble(),
    );
  }

  /// 轉換為 JSON 格式（用於更新 API）
  Map<String, dynamic> toJson() {
    return {
      'remainingAmount': remainingAmount,
      'status': status,
      'lastReplacedAt': lastReplacedAt?.toIso8601String(),
    };
  }

  /// 建立修改後的副本
  Ingredient copyWith({
    int? id,
    String? name,
    double? remainingAmount,
    String? status,
    DateTime? lastReplacedAt,
    String? unit,
    double? capacity,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      status: status ?? this.status,
      lastReplacedAt: lastReplacedAt ?? this.lastReplacedAt,
      unit: unit ?? this.unit,
      capacity: capacity ?? this.capacity,
    );
  }

  /// 計算剩餘百分比
  double get remainingPercentage {
    if (capacity == null || capacity == 0 || remainingAmount == null) {
      return 0;
    }
    return (remainingAmount! / capacity!) * 100;
  }

  /// 取得狀態顯示文字
  String get statusText {
    switch (status) {
      case 'active':
        return '正常';
      case 'low':
        return '即將耗盡';
      case 'empty':
        return '已空';
      case 'replaced':
        return '已更換';
      default:
        return '未知';
    }
  }
}
