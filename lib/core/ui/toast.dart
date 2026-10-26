import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

enum ToastKind { info, success, error }

/// 화면 아래에 잠깐 떴다 사라지는 알림 (머티리얼 스낵바 대신).
/// 한 번에 하나만 보이고, 새로 띄우면 이전 것은 바로 사라진다. 아래로 밀어서 닫을 수 있다.
///
/// 시트·대화상자 위에서도 보이게 가장 바깥 오버레이에 띄운다.
void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showToastOn(overlay, message,
      kind: kind, actionLabel: actionLabel, onAction: onAction);
}

/// 기다리는 동안 화면이 바뀌어도 띄울 수 있게, 미리 꺼내 둔 오버레이에 띄운다.
void showToastOn(
  OverlayState overlay,
  String message, {
  ToastKind kind = ToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (!overlay.mounted) return;
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      onClosed: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

OverlayEntry? _current;

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.kind,
    required this.actionLabel,
    required this.onAction,
    required this.onClosed,
  });

  final String message;
  final ToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClosed;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  )..forward();
  Timer? _timer;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    // 버튼이 있으면 누를 시간을 조금 더 준다.
    _timer = Timer(
        Duration(milliseconds: widget.actionLabel == null ? 2600 : 4000), _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 키보드가 떠 있으면 그 위, 아니면 아래 바·버튼과 겹치지 않을 높이.
    final bottom = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom + 16
        : media.viewPadding.bottom + 92;
    final (icon, iconColor) = switch (widget.kind) {
      ToastKind.success => (AppIcons.checkCircle, AppColors.primary),
      ToastKind.error => (AppIcons.warningFill, const Color(0xFFFF8A8A)),
      ToastKind.info => (AppIcons.infoFill, const Color(0xB3FFFFFF)),
    };
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: SafeArea(
        top: false,
        bottom: false,
        child: FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, (1 - curved.value) * 16 + _drag),
              child: child,
            ),
            child: GestureDetector(
              onVerticalDragUpdate: (d) =>
                  setState(() => _drag = (_drag + d.delta.dy).clamp(0, 80)),
              onVerticalDragEnd: (_) {
                if (_drag > 24) {
                  _close();
                } else {
                  setState(() => _drag = 0);
                }
              },
              child: Semantics(
                liveRegion: true,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: AppColors.text.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 24,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: iconColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.onAction?.call();
                            _close();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Text(
                              widget.actionLabel!,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
