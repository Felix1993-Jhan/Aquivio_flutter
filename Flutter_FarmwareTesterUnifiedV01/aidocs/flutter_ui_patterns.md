# Flutter UI 佈局模式指南

> 新專案防雷清單 — 常見佈局/畫面問題與標準解法

---

## 快速對照表

| # | 問題 | 解法 | 嚴重度 |
|---|------|------|--------|
| 1 | Widget 超出邊界 | `Expanded` / `Flexible` | 高 |
| 2 | ListView 在 Column 中爆炸 | `Flexible` + `shrinkWrap: true` | 高 |
| 3 | 文字溢出不截斷 | `TextOverflow.ellipsis` + `maxLines` | 中 |
| 4 | 內容需要捲動 | `SingleChildScrollView` 包 `Column` | 高 |
| 5 | 內容高度不確定 | `ConstrainedBox(maxHeight:)` | 中 |
| 6 | 響應式佈局 | `LayoutBuilder` 判斷寬度 | 中 |
| 7 | 按鈕組換行 | `Wrap(spacing:, runSpacing:)` | 中 |
| 8 | Dialog 高度爆炸 | `mainAxisSize: MainAxisSize.min` + `ConstrainedBox` | 中 |
| 9 | setState after dispose | 所有 async 回調加 `if (mounted)` | 高 |
| 10 | 資源未清理 | `dispose()` 中取消所有 Timer/Controller/Stream | 高 |
| 11 | Stack 子元素溢出 | `clipBehavior: Clip.antiAlias` | 低 |
| 12 | 圖片載入失敗白屏 | `errorBuilder` 提供備用顯示 | 低 |
| 13 | 桌面視窗縮太小 UI 壞 | `WindowOptions(minimumSize:)` | 高(桌面) |
| 14 | 點擊無視覺回饋 | 用 `InkWell` 不要用 `GestureDetector` | 低 |
| 15 | 空間留白用錯元件 | 純間距用 `SizedBox`，有裝飾用 `Container` | 低 |
| 16 | Padding 混亂不統一 | 統一 8pt 倍數系統 | 低 |
| 17 | 顏色硬編碼散落各處 | 集中到顏色常數類 | 中 |

---

## 詳細說明

### 1. Widget 超出邊界（RenderFlex Overflow）

**問題：** 子 Widget 總寬度/高度超過父容器，出現黃黑條紋溢出警告。

**解法：** 在 `Row` / `Column` 中用 `Expanded` 或 `Flexible` 包裹會伸縮的子元素。

```dart
// 錯誤 — Text 可能超出 Row 寬度
Row(
  children: [
    Icon(Icons.info),
    Text('這段文字可能會非常非常長超出螢幕邊界'),
  ],
)

// 正確 — Expanded 讓 Text 自動縮到剩餘空間
Row(
  children: [
    Icon(Icons.info),
    Expanded(child: Text('這段文字會自動縮到剩餘空間')),
  ],
)
```

**差異：**
- `Expanded` — 強制填滿剩餘空間（`flex` 控制比例）
- `Flexible` — 允許子元素小於分配空間（`fit: FlexFit.loose`）

---

### 2. ListView 在 Column 中爆炸

**問題：** `ListView` 需要無限高度，放在 `Column` 中會報錯 "Vertical viewport was given unbounded height"。

**解法：** 用 `Flexible` 包裹 + `shrinkWrap: true`。

```dart
// 錯誤 — 直接放會爆炸
Column(
  children: [
    Text('標題'),
    ListView.builder(itemCount: 100, itemBuilder: ...),
  ],
)

// 正確
Column(
  children: [
    Text('標題'),
    Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: 100,
        itemBuilder: (context, index) { ... },
      ),
    ),
  ],
)
```

**注意：** 不要用 `Expanded` 包 `ListView` 再放進另一個可捲動容器，會造成巢狀滾動衝突。

---

### 3. 文字溢出不截斷

**問題：** 長文字超出容器邊界，沒有自動截斷或省略號。

**解法：** 統一使用 `TextOverflow.ellipsis` + `maxLines`。

```dart
Text(
  '這是一段可能非常非常長的文字內容',
  overflow: TextOverflow.ellipsis,
  maxLines: 1,  // 單行截斷；需要多行可設 2 或 3
)
```

**補充：** 若文字在 `Row` 中，外層還需要 `Expanded` 或 `Flexible` 來給予寬度約束。

---

### 4. 內容需要捲動

**問題：** 內容超過容器高度時無法捲動。

**解法：** 用 `SingleChildScrollView` 包裹 `Column`。

```dart
// 搭配 Flexible 使用（在父 Column 中）
Flexible(
  child: SingleChildScrollView(
    child: Column(
      children: [
        // 多個子 Widget...
      ],
    ),
  ),
)

// 搭配 ScrollController（需要控制捲動位置時）
final _scrollController = ScrollController();

SingleChildScrollView(
  controller: _scrollController,
  child: Column(children: [...]),
)

// 記得在 dispose 中清理
@override
void dispose() {
  _scrollController.dispose();
  super.dispose();
}
```

---

### 5. 內容高度不確定

**問題：** 不知道內容會有多高，寫死高度不彈性，不寫又可能撐爆。

**解法：** 用 `ConstrainedBox` 設定最大高度。

```dart
ConstrainedBox(
  constraints: BoxConstraints(maxHeight: 200),
  child: SingleChildScrollView(
    child: Column(children: [...]),
  ),
)
```

**常見應用場景：**
- Dialog 內容區：`maxHeight: 500~600`
- 展開式詳情區：`maxHeight: 180~200`
- 設定頁面列表：`maxHeight: 500`

---

### 6. 響應式佈局

**問題：** 視窗大小變化時 UI 不自適應。

**解法：** 用 `LayoutBuilder` 實作三級響應式設計（而非 `MediaQuery`，因為 `LayoutBuilder` 反映的是父容器的實際約束）。

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final width = constraints.maxWidth;
    final isVertical = width < 500;
    final isCompact = width < 900;

    if (isVertical) {
      // 窄螢幕：垂直堆疊
      return Column(children: [...]);
    }

    // 寬螢幕：水平排列（isCompact 時可減少間距或隱藏次要元素）
    return Row(children: [...]);
  },
)
```

**三級斷點建議：**
| 寬度 | 佈局 |
|------|------|
| `< 500px` | 垂直堆疊 |
| `500~900px` | 緊湊水平 |
| `> 900px` | 完整水平 |

---

### 7. 按鈕組換行

**問題：** 多個按鈕放在 `Row` 中超出寬度溢出。

**解法：** 用 `Wrap` 自動換行。

```dart
Wrap(
  spacing: 4,       // 水平間距
  runSpacing: 4,    // 換行後垂直間距
  children: [
    ElevatedButton(onPressed: ..., child: Text('按鈕 1')),
    ElevatedButton(onPressed: ..., child: Text('按鈕 2')),
    ElevatedButton(onPressed: ..., child: Text('按鈕 3')),
    // 放多少都不會溢出，自動換行
  ],
)
```

---

### 8. Dialog 高度爆炸

**問題：** `AlertDialog` 內容太多時撐到超出螢幕。

**解法：** `mainAxisSize: MainAxisSize.min` 讓高度自適應，搭配 `ConstrainedBox` 限制最大高度。

```dart
AlertDialog(
  title: Text('標題'),
  content: SizedBox(
    width: 500,  // 固定寬度
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,  // 關鍵：不撐滿
        children: [
          Text('說明文字'),
          Flexible(
            child: SingleChildScrollView(
              child: Column(children: [...]),
            ),
          ),
        ],
      ),
    ),
  ),
)
```

---

### 9. setState after dispose

**問題：** 非同步操作完成時 Widget 已銷毀，呼叫 `setState` 報錯。

**解法：** 所有非同步回調中檢查 `mounted`。

```dart
// 標準做法
Future<void> _loadData() async {
  final result = await fetchSomething();
  if (mounted) {
    setState(() {
      _data = result;
    });
  }
}

// Timer 回調
Timer.periodic(Duration(seconds: 1), (timer) {
  if (!mounted) {
    timer.cancel();
    return;
  }
  setState(() { ... });
});
```

---

### 10. 資源未清理（記憶體洩漏）

**問題：** Timer、Controller、Stream 等未在 `dispose` 中清理，導致記憶體洩漏。

**解法：** 在 `dispose()` 中完整清理所有長生命週期物件。

```dart
class _MyPageState extends State<MyPage> {
  Timer? _heartbeatTimer;
  Timer? _readTimer;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  StreamSubscription? _subscription;

  @override
  void dispose() {
    // Timer
    _heartbeatTimer?.cancel();
    _readTimer?.cancel();
    // Controller
    _scrollController.dispose();
    _fadeController.dispose();
    // Stream
    _subscription?.cancel();
    super.dispose();
  }
}
```

**清理清單：**
| 類型 | 清理方式 |
|------|---------|
| `Timer` | `.cancel()` |
| `ScrollController` | `.dispose()` |
| `AnimationController` | `.dispose()` |
| `TextEditingController` | `.dispose()` |
| `FocusNode` | `.dispose()` |
| `StreamSubscription` | `.cancel()` |
| `ValueNotifier` | `.dispose()` |

---

### 11. Stack 子元素溢出

**問題：** `Positioned` 子元素超出 `Stack` 邊界，圓角處出現溢出。

**解法：** 在父容器設定 `clipBehavior`。

```dart
Card(
  clipBehavior: Clip.antiAlias,  // 裁剪超出圓角的內容
  child: Stack(
    children: [
      // 主內容
      Column(children: [...]),
      // 浮動按鈕
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          onPressed: ...,
          child: Icon(Icons.check),
        ),
      ),
    ],
  ),
)
```

---

### 12. 圖片載入失敗白屏

**問題：** 圖片路徑錯誤或檔案遺失時顯示空白。

**解法：** 使用 `errorBuilder` 提供備用顯示。

```dart
Image.asset(
  'assets/images/logo.png',
  fit: BoxFit.contain,  // 正確縮放，不變形
  errorBuilder: (context, error, stackTrace) {
    return const Icon(
      Icons.broken_image,
      size: 100,
      color: Colors.grey,
    );
  },
)
```

**BoxFit 選擇：**
| 值 | 效果 |
|---|------|
| `contain` | 完整顯示，可能留白 |
| `cover` | 填滿容器，可能裁切 |
| `fill` | 拉伸填滿，可能變形 |
| `fitWidth` | 寬度填滿 |
| `fitHeight` | 高度填滿 |

---

### 13. 桌面視窗縮太小 UI 壞掉

**問題：** 使用者把視窗縮到很小，整個 UI 排版崩潰。

**解法：** 設定視窗最小尺寸（需要 `window_manager` 套件）。

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(800, 600),    // 最小尺寸，不能再縮
    size: Size(1200, 800),           // 初始尺寸
    center: true,
    title: '應用程式標題',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}
```

---

### 14. 點擊無視覺回饋

**問題：** 用 `GestureDetector` 處理點擊，使用者看不到任何回饋。

**解法：** 需要視覺回饋時用 `InkWell`。

```dart
// 有波紋回饋（推薦用於 UI 元素）
InkWell(
  onTap: () { ... },
  borderRadius: BorderRadius.circular(8),
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text('按鈕文字'),
  ),
)

// 無視覺回饋（用於純手勢偵測，如拖曳、滑動）
GestureDetector(
  onTap: () { ... },
  onPanUpdate: (details) { ... },
  child: ...,
)
```

---

### 15. 空間留白用錯元件

**問題：** 用 `Container()` 只為了留白，浪費效能。

**解法：** 純間距用 `SizedBox`，需要裝飾才用 `Container`。

```dart
// 純留白 → SizedBox（更輕量）
Column(
  children: [
    Text('上面的文字'),
    const SizedBox(height: 16),   // 垂直間距
    Text('下面的文字'),
  ],
)

Row(
  children: [
    Icon(Icons.info),
    const SizedBox(width: 8),     // 水平間距
    Text('說明'),
  ],
)

// 需要背景/邊框/圓角 → Container
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.grey.shade300),
  ),
  child: Text('有裝飾的容器'),
)
```

---

### 16. Padding 混亂不統一

**問題：** 每個地方的 padding 隨意寫，視覺不一致。

**解法：** 統一使用 8pt 倍數系統。

```dart
// 標準間距體系
const EdgeInsets.all(4)                                    // 極小
const EdgeInsets.all(8)                                    // 小
const EdgeInsets.all(12)                                   // 標準
const EdgeInsets.all(16)                                   // 舒適
const EdgeInsets.all(24)                                   // 大

// 常用組合
const EdgeInsets.symmetric(horizontal: 12, vertical: 4)    // 按鈕內距
const EdgeInsets.symmetric(horizontal: 16, vertical: 8)    // 卡片內距
const EdgeInsets.symmetric(horizontal: 8, vertical: 4)     // 緊湊列表項
```

**建議：** 可定義常數避免到處寫魔術數字：

```dart
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}
```

---

### 17. 顏色硬編碼散落各處

**問題：** 顏色值散落在各檔案中，改配色要改幾十個地方。

**解法：** 集中定義顏色常數類。

```dart
// 定義一次，全專案使用
class AppColors {
  static const Color primary = Color(0xFF50C878);
  static const Color primaryLight = Color(0xFFE8F5E9);
  static const Color primaryDark = Color(0xFF2E7D32);
  static const Color background = Color(0xFFF1F8E9);
  static const Color header = Color(0xFF81C784);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);
}

// 使用
Container(color: AppColors.primary)
Text('錯誤', style: TextStyle(color: AppColors.error))
```

**進階：** 若需要支援深色模式，可整合到 `ThemeData` 中：

```dart
MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
  ),
)
```
