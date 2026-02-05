// ============================================================================
// AutoDetectionPage - 自動檢測流程頁面（BodyDoor 版）
// ============================================================================
// 功能：顯示 Arduino 的 19 個 ADC 通道數據 (ID 0-18)，判斷 Pass/Fail
// - 上方：COM 選擇和連接控制區（僅 Arduino）
// - 中間：硬體數據表（ID 0-18，僅 Idle 狀態）
// - 表格欄位：ID、名稱、Arduino 數值、狀態燈
// - 使用 ThresholdSettingsService 進行範圍驗證
// ============================================================================

import 'package:flutter/material.dart';
import '../services/data_storage_service.dart';
import '../services/localization_service.dart';
import '../services/threshold_settings_service.dart';
import 'data_storage_page.dart';

class AutoDetectionPage extends StatefulWidget {
  /// 數據儲存服務
  final DataStorageService dataStorage;

  /// 可用的 COM 埠列表
  final List<String> availablePorts;

  /// 已選擇的 Arduino COM 埠
  final String? selectedArduinoPort;

  /// Arduino 是否已連接
  final bool isArduinoConnected;

  /// Arduino COM 埠變更回調
  final void Function(String?) onArduinoPortChanged;

  /// Arduino 連接回調
  final VoidCallback onArduinoConnect;

  /// Arduino 斷開回調
  final VoidCallback onArduinoDisconnect;

  /// 刷新 COM 埠列表回調
  final VoidCallback onRefreshPorts;

  /// 自動檢測開始回調
  final VoidCallback? onStartAutoDetection;

  /// 是否正在自動檢測
  final bool isAutoDetecting;

  /// 自動檢測狀態文字
  final String? autoDetectionStatus;

  /// 自動檢測進度 (0.0 - 1.0)
  final double autoDetectionProgress;

  /// 當前正在讀取的項目 ID（用於高亮顯示）
  final int? currentReadingId;

  /// 當前正在讀取的區域類型（idle）
  final String? currentReadingSection;

  /// 顯示檢測結果對話框回調
  final VoidCallback? onShowResultDialog;

  /// 是否啟用慢速調試模式
  final bool isSlowDebugMode;

  /// 切換慢速調試模式回調
  final VoidCallback? onToggleSlowDebugMode;

  /// 當前調試訊息（慢速模式下顯示詳細資訊）
  final String? debugMessage;

  /// 調試歷史當前索引（1-based）
  final int debugHistoryIndex;

  /// 調試歷史總數
  final int debugHistoryTotal;

  /// 查看上一條調試訊息回調
  final VoidCallback? onDebugHistoryPrev;

  /// 查看下一條調試訊息回調
  final VoidCallback? onDebugHistoryNext;

  /// 調試模式是否暫停
  final bool isDebugPaused;

  /// 切換調試暫停狀態回調
  final VoidCallback? onToggleDebugPause;

  const AutoDetectionPage({
    super.key,
    required this.dataStorage,
    required this.availablePorts,
    required this.selectedArduinoPort,
    required this.isArduinoConnected,
    required this.onArduinoPortChanged,
    required this.onArduinoConnect,
    required this.onArduinoDisconnect,
    required this.onRefreshPorts,
    this.onStartAutoDetection,
    this.isAutoDetecting = false,
    this.autoDetectionStatus,
    this.autoDetectionProgress = 0.0,
    this.currentReadingId,
    this.currentReadingSection,
    this.onShowResultDialog,
    this.isSlowDebugMode = false,
    this.onToggleSlowDebugMode,
    this.debugMessage,
    this.debugHistoryIndex = 0,
    this.debugHistoryTotal = 0,
    this.onDebugHistoryPrev,
    this.onDebugHistoryNext,
    this.isDebugPaused = false,
    this.onToggleDebugPause,
  });

  @override
  State<AutoDetectionPage> createState() => _AutoDetectionPageState();
}

class _AutoDetectionPageState extends State<AutoDetectionPage> {
  final ScrollController _bodyScrollController = ScrollController();
  final ScrollController _doorScrollController = ScrollController();
  static const double _dataRowHeight = 40.0;

  @override
  void dispose() {
    _bodyScrollController.dispose();
    _doorScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AutoDetectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentReadingId != oldWidget.currentReadingId ||
        widget.currentReadingSection != oldWidget.currentReadingSection) {
      _scrollToCurrentItem();
    }
  }

  void _scrollToCurrentItem() {
    final id = widget.currentReadingId;
    final section = widget.currentReadingSection;
    if (id == null || section == null) return;

    if (DisplayNames.isBody(id)) {
      final index = DisplayNames.bodyIds.indexOf(id);
      if (index >= 0) {
        _animateScrollTo(_bodyScrollController, index * _dataRowHeight, _dataRowHeight);
      }
    } else if (DisplayNames.isDoor(id)) {
      final index = DisplayNames.doorIds.indexOf(id);
      if (index >= 0) {
        _animateScrollTo(_doorScrollController, index * _dataRowHeight, _dataRowHeight);
      }
    }
  }

  void _animateScrollTo(ScrollController controller, double offset, double itemHeight) {
    if (!controller.hasClients) return;
    final currentOffset = controller.offset;
    final viewportHeight = controller.position.viewportDimension;
    final itemTop = offset;
    final itemBottom = offset + itemHeight;
    final marginTop = viewportHeight * 0.25;
    final marginBottom = viewportHeight * 0.25;
    final isComfortablyVisible = itemTop >= (currentOffset + marginTop) &&
        itemBottom <= (currentOffset + viewportHeight - marginBottom);
    if (isComfortablyVisible) return;
    final centerOffset = offset - (viewportHeight / 2) + (itemHeight / 2);
    final maxOffset = controller.position.maxScrollExtent;
    final targetOffset = centerOffset.clamp(0.0, maxOffset);
    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService().currentLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: widget.dataStorage.dataUpdateNotifier,
          builder: (context, _, __) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.dataStorage.runningStateNotifier,
              builder: (context, _, __) {
                return Stack(
                  children: [
                    Column(
                      children: [
                        _buildConnectionControlBar(),
                        if (widget.isAutoDetecting) _buildAutoDetectionProgress(),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            child: Card(
                              elevation: 4,
                              shadowColor: Colors.blueGrey.shade400,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.blueGrey.shade400, width: 2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _buildDataSection(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onShowResultDialog != null)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _buildFloatingResultButton(),
                      ),
                    if (widget.onToggleSlowDebugMode != null)
                      Positioned(
                        right: 16,
                        bottom: 76,
                        child: _buildSlowDebugButton(),
                      ),
                    if (widget.isSlowDebugMode &&
                        widget.debugMessage != null &&
                        widget.debugMessage!.isNotEmpty)
                      Positioned(
                        left: 16,
                        right: 80,
                        bottom: 16,
                        child: _buildDebugMessagePanel(),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingResultButton() {
    return Material(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: widget.onShowResultDialog,
        customBorder: const CircleBorder(),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade400, Colors.blue.shade700],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
          ),
          child: const Icon(Icons.assignment, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildSlowDebugButton() {
    return Material(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: widget.onToggleSlowDebugMode,
        customBorder: const CircleBorder(),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isSlowDebugMode
                  ? [Colors.orange.shade400, Colors.orange.shade700]
                  : [Colors.grey.shade400, Colors.grey.shade600],
            ),
            border: Border.all(
              color: widget.isSlowDebugMode
                  ? Colors.yellow.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Icon(
            widget.isSlowDebugMode ? Icons.slow_motion_video : Icons.speed,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildDebugMessagePanel() {
    final canGoPrev = widget.debugHistoryIndex > 1;
    final canGoNext = widget.debugHistoryIndex < widget.debugHistoryTotal;
    final parsedData = _parseDebugMessage(widget.debugMessage);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.orange, size: 16),
              const SizedBox(width: 6),
              Text(
                tr('debug_mode'),
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              if (widget.debugHistoryTotal > 0) ...[
                IconButton(
                  onPressed: canGoPrev ? widget.onDebugHistoryPrev : null,
                  icon: Icon(Icons.arrow_upward, color: canGoPrev ? Colors.white : Colors.grey, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: tr('prev_record'),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${widget.debugHistoryIndex} / ${widget.debugHistoryTotal}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: canGoNext ? widget.onDebugHistoryNext : null,
                  icon: Icon(Icons.arrow_downward, color: canGoNext ? Colors.white : Colors.grey, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: tr('next_record'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onToggleDebugPause,
                  icon: Icon(
                    widget.isDebugPaused ? Icons.play_arrow : Icons.pause,
                    color: widget.isDebugPaused ? Colors.green : Colors.white,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: widget.isDebugPaused ? tr('debug_resume') : tr('debug_pause'),
                  style: IconButton.styleFrom(
                    backgroundColor: widget.isDebugPaused
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (parsedData != null) ...[
            _buildDebugHeader(parsedData),
            const SizedBox(height: 8),
            _buildDebugTestCards(parsedData),
          ] else ...[
            Text(
              widget.debugMessage ?? '',
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  _DebugParsedData? _parseDebugMessage(String? message) {
    if (message == null || message.isEmpty) return null;
    final lines = message.split('\n');
    if (lines.length < 2) return null;

    String? channelName;
    int? channelId;

    for (final line in lines) {
      final idMatch = RegExp(r'\[ID(\d+)\]\s*(.+)').firstMatch(line);
      final idMatchZh = RegExp(r'【ID(\d+)】\s*(.+)').firstMatch(line);
      if (idMatch != null) {
        channelId = int.tryParse(idMatch.group(1) ?? '');
        channelName = idMatch.group(2)?.trim();
      } else if (idMatchZh != null) {
        channelId = int.tryParse(idMatchZh.group(1) ?? '');
        channelName = idMatchZh.group(2)?.trim();
      }
    }

    if (channelName == null || channelId == null) return null;

    final testResults = <_DebugTestResult>[];
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.contains('Arduino')) {
        final arduinoMatch = RegExp(
          r'Arduino[:\s]+(?:Base|基準)\s*(\S+)\s*→\s*(?:New|新值)\s*(\S+)\s*(?:Diff|差)[:\s]*(\d+)\s*(.*)',
        ).firstMatch(trimmedLine);
        if (arduinoMatch != null) {
          final result = _DebugTestResult(
            index: testResults.length + 1,
            pinName: channelName,
            pinId: channelId,
          );
          result.arduinoBase = arduinoMatch.group(1);
          result.arduinoNew = arduinoMatch.group(2);
          result.arduinoDiff = arduinoMatch.group(3);
          final status = arduinoMatch.group(4) ?? '';
          result.arduinoIsNormal =
              status.contains('Normal') || status.contains('正常') || status.contains('✓');
          testResults.add(result);
        }
      }
      if (testResults.isNotEmpty) {
        final thresholdMatch = RegExp(r'Threshold:\s*(\d+)').firstMatch(line);
        final thresholdMatchZh = RegExp(r'閾值:\s*(\d+)').firstMatch(line);
        if (thresholdMatch != null) {
          testResults.last.threshold = thresholdMatch.group(1);
        } else if (thresholdMatchZh != null) {
          testResults.last.threshold = thresholdMatchZh.group(1);
        }
      }
    }

    if (testResults.isEmpty) return null;
    return _DebugParsedData(
      channelName: channelName,
      channelId: channelId,
      testResults: testResults,
    );
  }

  Widget _buildDebugHeader(_DebugParsedData data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            '[ID${data.channelId}] ${data.channelName}',
            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugTestCards(_DebugParsedData data) {
    final results = data.testResults;
    final rowCount = (results.length / 2).ceil();
    return Column(
      children: List.generate(rowCount, (rowIndex) {
        final leftIndex = rowIndex * 2;
        final rightIndex = leftIndex + 1;
        return Padding(
          padding: EdgeInsets.only(bottom: rowIndex < rowCount - 1 ? 8 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildSingleTestCard(results[leftIndex])),
              const SizedBox(width: 8),
              Expanded(
                child: rightIndex < results.length
                    ? _buildSingleTestCard(results[rightIndex])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSingleTestCard(_DebugTestResult result) {
    final isNormal = result.arduinoIsNormal;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isNormal
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isNormal ? Colors.green : Colors.red, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '[${result.index}]',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${result.pinName} (ID${result.pinId})',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                isNormal ? Icons.check_circle : Icons.error,
                color: isNormal ? Colors.green : Colors.red,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(
                width: 48,
                child: Text(
                  'Arduino',
                  style: TextStyle(color: Color(0xFF50C878), fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  '${result.arduinoBase ?? "N/A"} -> ${result.arduinoNew ?? "N/A"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text('D${result.arduinoDiff ?? "0"}', style: const TextStyle(color: Colors.white54, fontSize: 9)),
              const SizedBox(width: 4),
              Text(
                isNormal ? '√' : 'X',
                style: TextStyle(
                  color: isNormal ? Colors.green : Colors.red,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Threshold: ${result.threshold ?? "N/A"}',
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionControlBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isVertical = width < 500;
        final isCompact = width < 900;

        if (isVertical) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDeviceConnectionPanelVertical(
                isConnected: widget.isArduinoConnected,
                selectedPort: widget.selectedArduinoPort,
                onPortChanged: widget.onArduinoPortChanged,
                onConnect: widget.onArduinoConnect,
                onDisconnect: widget.onArduinoDisconnect,
              ),
              _buildMetallicButton(
                isCompact: false,
                isAutoDetecting: widget.isAutoDetecting,
                onPressed: () => widget.onStartAutoDetection?.call(),
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Card(
                    elevation: 3,
                    shadowColor: EmeraldColors.primary.withValues(alpha: 0.5),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: EmeraldColors.primary, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildDeviceConnectionPanel(
                      deviceName: tr('arduino_control'),
                      deviceIcon: Icons.memory,
                      isConnected: widget.isArduinoConnected,
                      selectedPort: widget.selectedArduinoPort,
                      primaryColor: EmeraldColors.primary,
                      secondaryColor: EmeraldColors.light,
                      onPortChanged: widget.onArduinoPortChanged,
                      onConnect: widget.onArduinoConnect,
                      onDisconnect: widget.onArduinoDisconnect,
                      isCompact: isCompact,
                    ),
                  ),
                ),
                _buildMetallicButton(
                  isCompact: isCompact,
                  isAutoDetecting: widget.isAutoDetecting,
                  onPressed: () => widget.onStartAutoDetection?.call(),
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetallicButton({
    required bool isCompact,
    required bool isAutoDetecting,
    required VoidCallback onPressed,
  }) {
    const glassLight = Color(0xFFF5F5F5);
    const glassMid = Color(0xFFE8E8E8);
    const glassDark = Color(0xFFD0D0D0);
    const borderColor = Color(0xFFBDBDBD);
    const textColor = Color(0xFF424242);
    const disabledText = Color(0xFF9E9E9E);

    if (isCompact) {
      return Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [glassLight, glassMid, glassDark],
              stops: [0.0, 0.5, 1.0],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isAutoDetecting ? null : onPressed,
              borderRadius: BorderRadius.circular(20),
              child: Center(
                child: Icon(
                  isAutoDetecting ? Icons.hourglass_empty : Icons.play_arrow,
                  color: isAutoDetecting ? disabledText : textColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [glassLight, glassMid, glassDark],
            stops: [0.0, 0.6, 1.0],
          ),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAutoDetecting ? null : onPressed,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAutoDetecting ? Icons.hourglass_empty : Icons.play_arrow,
                    color: isAutoDetecting ? disabledText : textColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isAutoDetecting ? tr('auto_detection_running') : tr('auto_detection_start'),
                    style: TextStyle(
                      color: isAutoDetecting ? disabledText : textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceConnectionPanel({
    required String deviceName,
    required IconData deviceIcon,
    required bool isConnected,
    required String? selectedPort,
    required Color primaryColor,
    required Color secondaryColor,
    required void Function(String?) onPortChanged,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
    required bool isCompact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(deviceIcon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(deviceName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              Icon(isConnected ? Icons.link : Icons.link_off, color: Colors.white, size: 14),
            ],
          ),
        ),
        Container(
          color: secondaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isCompact ? 70 : 80,
                height: 28,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.availablePorts.contains(selectedPort) ? selectedPort : null,
                    hint: Text('COM', style: TextStyle(fontSize: isCompact ? 10 : 11)),
                    isExpanded: true,
                    isDense: true,
                    style: TextStyle(fontSize: isCompact ? 10 : 11, color: Colors.black),
                    iconSize: 16,
                    items: widget.availablePorts.map((port) {
                      return DropdownMenuItem(value: port, child: Text(port, style: TextStyle(fontSize: isCompact ? 10 : 11)));
                    }).toList(),
                    onChanged: isConnected ? null : onPortChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: isConnected ? onDisconnect : onConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? Colors.red : Colors.white,
                    foregroundColor: isConnected ? Colors.white : Colors.black87,
                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isConnected ? tr('disconnect') : tr('connect'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isCompact ? 10 : 11),
                  ),
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isConnected ? tr('connected') : tr('not_connected'),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceConnectionPanelVertical({
    required bool isConnected,
    required String? selectedPort,
    required void Function(String?) onPortChanged,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    return Container(
      color: EmeraldColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.memory, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          const Text('Arduino', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(width: 2),
          Icon(isConnected ? Icons.link : Icons.link_off, color: Colors.white, size: 10),
          const Spacer(),
          Container(
            width: 70,
            height: 26,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.availablePorts.contains(selectedPort) ? selectedPort : null,
                hint: const Text('COM', style: TextStyle(fontSize: 9)),
                isExpanded: true,
                isDense: true,
                style: const TextStyle(fontSize: 9, color: Colors.black),
                iconSize: 14,
                items: widget.availablePorts.map((port) {
                  return DropdownMenuItem(value: port, child: Text(port, style: const TextStyle(fontSize: 9)));
                }).toList(),
                onChanged: isConnected ? null : onPortChanged,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 26,
            child: ElevatedButton(
              onPressed: isConnected ? onDisconnect : onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? Colors.red : Colors.white,
                foregroundColor: isConnected ? Colors.white : EmeraldColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                isConnected ? tr('disconnect') : tr('connect'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoDetectionProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: widget.autoDetectionProgress > 0 ? widget.autoDetectionProgress : null,
            backgroundColor: Colors.blue.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
          const SizedBox(height: 6),
          Text(
            widget.autoDetectionStatus ?? '',
            style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 檢查當前數據是否觸發 3.3V 異常
  bool _check33vAnomaly() {
    return DisplayNames.check33vAnomaly((id) {
      final data = widget.dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
  }

  Widget _build33vWarningBanner() {
    if (!_check33vAnomaly()) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.red.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_33v_anomaly'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _checkBody12vAnomaly() {
    return DisplayNames.checkBody12vAnomaly((id) {
      final data = widget.dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
  }

  bool _checkDoor24vAnomaly() {
    return DisplayNames.checkDoor24vAnomaly((id) {
      final data = widget.dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
  }

  bool _checkDoor12vAnomaly() {
    return DisplayNames.checkDoor12vAnomaly((id) {
      final data = widget.dataStorage.getArduinoFirstIdleData(id);
      return data?.value;
    });
  }

  Widget _buildBody12vWarningBanner() {
    if (!_checkBody12vAnomaly()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.deepOrange.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_body12v_anomaly'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoor24vWarningBanner() {
    if (!_checkDoor24vAnomaly()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.purple.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_door24v_anomaly'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoor12vWarningBanner() {
    if (!_checkDoor12vAnomaly()) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.indigo.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('power_door12v_anomaly'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection() {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          _build33vWarningBanner(),
          _buildBody12vWarningBanner(),
          _buildDoor24vWarningBanner(),
          _buildDoor12vWarningBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Body 區 (ID 0-11)，分 12V / 3.3V 子組
                Expanded(
                  child: _buildGroupColumn(
                    title: 'Body',
                    color: Colors.teal,
                    ids: DisplayNames.bodyIds,
                    scrollController: _bodyScrollController,
                    subGroups: [
                      {'label': '12V', 'color': Colors.teal.shade300, 'ids': DisplayNames.body12vIds},
                      {'label': '3.3V', 'color': Colors.orange.shade400, 'ids': DisplayNames.body33vIds},
                    ],
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade400),
                // Door 區 (ID 12-18)
                Expanded(
                  child: _buildGroupColumn(
                    title: 'Door',
                    color: Colors.indigo,
                    ids: DisplayNames.doorIds,
                    scrollController: _doorScrollController,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupColumn({
    required String title,
    required Color color,
    required List<int> ids,
    required ScrollController scrollController,
    List<Map<String, dynamic>>? subGroups,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: color),
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildTableHeader(),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: subGroups != null
                  ? _buildSubGroupedRows(subGroups)
                  : ids.map((id) => _buildDataRow(id)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  /// 建構帶子分組標頭的資料列
  List<Widget> _buildSubGroupedRows(List<Map<String, dynamic>> subGroups) {
    final rows = <Widget>[];
    for (final group in subGroups) {
      final label = group['label'] as String;
      final color = group['color'] as Color;
      final ids = group['ids'] as List<int>;
      rows.add(_buildSubGroupHeader(label, color));
      rows.addAll(ids.map((id) => _buildDataRow(id)));
    }
    return rows;
  }

  /// 子分組標頭
  Widget _buildSubGroupHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.3)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 36,
            child: Text('ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 3,
            child: Text(tr('column_name'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tr('column_arduino'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF2E7D32)),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 28, child: Text('', textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildDataRow(int id) {
    final name = DisplayNames.getName(id);
    final thresholdService = ThresholdSettingsService();

    final arduinoData = widget.dataStorage.getArduinoFirstIdleData(id);
    final arduinoValue = arduinoData?.value;

    bool arduinoInRange = true;
    if (arduinoValue != null) {
      arduinoInRange = thresholdService.validateHardwareValue(
          DeviceType.arduino, StateType.idle, id, arduinoValue);
    }

    final isError = !arduinoInRange;
    final hasData = arduinoValue != null;
    final isCurrentlyReading =
        widget.currentReadingId == id && widget.currentReadingSection == 'idle';

    Color? backgroundColor;
    if (isCurrentlyReading) {
      backgroundColor = Colors.yellow.shade200;
    }

    return Container(
      constraints: BoxConstraints(minHeight: _dataRowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$id',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isCurrentlyReading ? Colors.orange.shade800 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: isCurrentlyReading
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                  : EdgeInsets.zero,
              decoration: isCurrentlyReading
                  ? BoxDecoration(color: Colors.orange.shade300, borderRadius: BorderRadius.circular(4))
                  : null,
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: isCurrentlyReading ? Colors.white : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              arduinoValue != null ? '$arduinoValue' : '--',
              style: TextStyle(
                fontSize: 10,
                fontWeight: (arduinoValue != null && !arduinoInRange) ? FontWeight.bold : FontWeight.normal,
                color: arduinoValue != null
                    ? (arduinoInRange ? EmeraldColors.dark : Colors.red)
                    : Colors.grey,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 28,
            child: Center(
              child: hasData
                  ? Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isError ? Colors.red : Colors.green,
                        boxShadow: [
                          BoxShadow(
                            color: (isError ? Colors.red : Colors.green).withValues(alpha: 0.5),
                            blurRadius: 3,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                      child: Icon(isError ? Icons.close : Icons.check, color: Colors.white, size: 12),
                    )
                  : Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade400),
                      child: const Icon(Icons.remove, color: Colors.white, size: 12),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Debug 解析用資料類別
// ============================================================================

class _DebugParsedData {
  final String channelName;
  final int channelId;
  final List<_DebugTestResult> testResults;

  _DebugParsedData({
    required this.channelName,
    required this.channelId,
    required this.testResults,
  });
}

class _DebugTestResult {
  final int index;
  final String pinName;
  final int pinId;

  String? arduinoBase;
  String? arduinoNew;
  String? arduinoDiff;
  bool arduinoIsNormal = true;
  String? threshold;

  _DebugTestResult({
    required this.index,
    required this.pinName,
    required this.pinId,
  });
}
