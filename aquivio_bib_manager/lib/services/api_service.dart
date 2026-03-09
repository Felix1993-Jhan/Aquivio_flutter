import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/machine.dart';
import '../models/user.dart';

/// Strapi API 服務
/// 處理所有與後端 API 的通訊

class ApiService {
  // API 基礎網址（開發環境）
  static const String baseUrl = 'http://localhost:1337/api';

  // 安全儲存實例，用於儲存 JWT Token
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // 儲存 Token 的 Key
  static const String _tokenKey = 'jwt_token';
  static const String _userKey = 'user_data';

  // 記憶體中的 Token 快取
  String? _jwtToken;

  /// 單例模式
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // ==================== Token 管理 ====================

  /// 設定並儲存 JWT Token
  Future<void> setToken(String token) async {
    _jwtToken = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  /// 從安全儲存載入 Token
  Future<String?> loadToken() async {
    _jwtToken = await _secureStorage.read(key: _tokenKey);
    return _jwtToken;
  }

  /// 清除 Token（登出時使用）
  Future<void> clearToken() async {
    _jwtToken = null;
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userKey);
  }

  /// 檢查是否已登入
  Future<bool> isLoggedIn() async {
    final token = await loadToken();
    return token != null && token.isNotEmpty;
  }

  // ==================== HTTP 請求方法 ====================

  /// 建構請求標頭
  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (_jwtToken != null && _jwtToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    return headers;
  }

  /// 處理 API 錯誤回應
  Exception _handleError(http.Response response) {
    try {
      final body = json.decode(response.body);
      final error = body['error'];
      if (error != null) {
        final message = error['message'] ?? '未知錯誤';
        final status = error['status'] ?? response.statusCode;

        if (status == 401) {
          return UnauthorizedException(message);
        } else if (status == 403) {
          return ForbiddenException(message);
        } else if (status == 404) {
          return NotFoundException(message);
        }
        return ApiException(message, status);
      }
    } catch (_) {
      // JSON 解析失敗
    }

    return ApiException('請求失敗: ${response.statusCode}', response.statusCode);
  }

  /// 通用 GET 請求
  Future<dynamic> get(String endpoint, {Map<String, String>? params}) async {
    try {
      final uri =
          Uri.parse('$baseUrl$endpoint').replace(queryParameters: params);

      final response = await http.get(uri, headers: _buildHeaders());

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw _handleError(response);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('網路連線失敗: $e', 0);
    }
  }

  /// 通用 POST 請求
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: _buildHeaders(),
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw _handleError(response);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('網路連線失敗: $e', 0);
    }
  }

  /// 通用 PUT 請求
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: _buildHeaders(),
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw _handleError(response);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('網路連線失敗: $e', 0);
    }
  }

  // ==================== 認證 API ====================

  /// 登入
  /// 成功後自動儲存 JWT Token
  Future<AuthResponse> login(String identifier, String password) async {
    final response = await post('/auth/local', {
      'identifier': identifier,
      'password': password,
    });

    final authResponse = AuthResponse.fromJson(response);

    // 儲存 Token
    await setToken(authResponse.jwt);

    // 儲存使用者資料
    await _secureStorage.write(
      key: _userKey,
      value: json.encode(authResponse.user.toJson()),
    );

    return authResponse;
  }

  /// 獲取當前使用者資訊
  Future<User> getCurrentUser() async {
    final response = await get('/users/me');
    return User.fromJson(response);
  }

  /// 登出
  Future<void> logout() async {
    await clearToken();
  }

  // ==================== 機器 API ====================

  /// 獲取機器列表
  Future<List<Machine>> getMachines({String? locale}) async {
    final params = <String, String>{
      'populate': '*',
    };
    if (locale != null) {
      params['locale'] = locale;
    }

    final response = await get('/machines', params: params);

    // Strapi 回傳格式：{ data: [...] }
    final List<dynamic> dataList = response['data'] ?? [];
    return dataList.map((item) => Machine.fromJson(item)).toList();
  }

  /// 獲取機器核心資料
  Future<Machine> getMachineCore(String token, {String? locale}) async {
    final params = <String, String>{};
    if (locale != null) {
      params['locale'] = locale;
    }

    final response = await get(
      '/machines/$token/core',
      params: params.isNotEmpty ? params : null,
    );

    return Machine.fromJson(response);
  }

  /// 獲取機器成分列表
  Future<List<Ingredient>> getMachineIngredients(String token) async {
    final response = await get('/machines/$token/ingredients');

    // 回傳可能是 { data: [...] } 或直接是陣列
    final List<dynamic> dataList = response is List
        ? response
        : (response['data'] ?? response['ingredients'] ?? []);

    return dataList.map((item) => Ingredient.fromJson(item)).toList();
  }

  // ==================== 成分 API ====================

  /// 更新成分資訊
  Future<Ingredient> updateIngredient(
      int ingredientId, Map<String, dynamic> data) async {
    final response = await put('/ingredients/$ingredientId', {
      'data': data,
    });

    return Ingredient.fromJson(response['data'] ?? response);
  }

  /// 標記成分已更換（快速操作）
  /// 自動重設剩餘量並記錄更換時間
  Future<Ingredient> markIngredientReplaced(
    int ingredientId, {
    double? newAmount,
  }) async {
    final now = DateTime.now().toIso8601String();

    return await updateIngredient(ingredientId, {
      'status': 'active',
      'remainingAmount': newAmount,
      'lastReplacedAt': now,
    });
  }
}

// ==================== 自訂例外類別 ====================

/// API 基礎例外
class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

/// 未授權例外（401）
class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message, 401);
}

/// 禁止存取例外（403）
class ForbiddenException extends ApiException {
  ForbiddenException(String message) : super(message, 403);
}

/// 找不到資源例外（404）
class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message, 404);
}
