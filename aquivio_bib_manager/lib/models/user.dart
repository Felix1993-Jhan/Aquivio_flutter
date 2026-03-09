// 使用者資料模型
// 用於儲存登入後的使用者資訊

class User {
  final int id;
  final String username;
  final String email;
  final String? name;
  final int? organizationId;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.name,
    this.organizationId,
  });

  /// 從登入回應 JSON 建立 User 物件
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      name: json['name'],
      organizationId: json['organization']?['id'],
    );
  }

  /// 轉換為 JSON 格式
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'name': name,
      'organizationId': organizationId,
    };
  }
}

/// 登入回應資料模型
class AuthResponse {
  final String jwt;
  final User user;

  AuthResponse({
    required this.jwt,
    required this.user,
  });

  /// 從 API 回應建立 AuthResponse
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      jwt: json['jwt'] ?? '',
      user: User.fromJson(json['user'] ?? {}),
    );
  }
}
