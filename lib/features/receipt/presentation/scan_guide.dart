import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/pressable.dart';

/// 처음 쓸 때 한 번, 화면을 어둡게 하고 스캔 버튼만 밝혀서 무엇을 하는 버튼인지 알려준다.
/// 밝힌 버튼을 누르면 바로 찍고, 다른 곳이나 "알겠어요"를 누르면 닫는다.
class ScanGuide extends StatefulWidget {
  const ScanGuide(
      {super.key,
      required this.targetKey,
      required this.onClose,
      required this.onScan});

  /// 밝힐 스캔 버튼.
  final GlobalKey targetKey;
  final VoidCallback onClose;
  final VoidCallback onScan;

  @override
  State<ScanGuide> createState() => _ScanGuideState();
}

class _ScanGuideState extends State<ScanGuide>
    with SingleTickerProviderStateMixin {
  /// 버튼 둘레의 고리가 천천히 퍼졌다 줄었다 한다.
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);
  Rect? _target;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 버튼 자리를 이 위젯 기준 좌표로 찾는다. 바가 아직 그려지지 않았으면 다음 프레임에 다시.
  void _locate() {
    if (!mounted) return;
    final box =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (box == null || me == null || !box.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
      return;
    }
    final topLeft = me.globalToLocal(box.localToGlobal(Offset.zero));
    setState(() => _target = topLeft & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final hole = target.inflate(6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Stack(
        children: [
          // 어두운 막. 아무 데나 누르면 닫는다.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _SpotlightPainter(hole: hole, pulse: _pulse.value),
                ),
              ),
            ),
          ),
          // 밝힌 버튼을 누르면 바로 찍는다.
          Positioned.fromRect(
            rect: hole,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onScan,
              child: Semantics(button: true, label: '영수증 찍기'),
            ),
          ),
          Positioned(
            right: 16,
            bottom: size.height - hole.top + 14,
            child: _Bubble(onClose: widget.onClose),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 32;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: width > 320 ? 320 : width,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle),
                      child: const Icon(AppIcons.receiptFill,
                          size: 18, color: AppColors.primaryDeep),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('여기를 눌러 영수증을 찍어요',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '어느 나라 영수증이든 품목과 금액을 자동으로 정리해 드려요. '
                  '길면 여러 장으로 나눠 찍어도 돼요.\n'
                  '앨범 사진이나 직접 입력은 지출 화면에서 할 수 있어요.',
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: AppColors.textSub),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Pressable(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('알겠어요',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onPrimary)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 버튼을 가리키는 꼬리
          Padding(
            padding: const EdgeInsets.only(right: 26),
            child: CustomPaint(
                size: const Size(18, 10), painter: _TailPainter()),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.pulse});

  final Rect hole;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addOval(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0xB3000000));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary.withValues(alpha: 1 - pulse * 0.7);
    canvas.drawOval(hole.inflate(4 + pulse * 10), ring);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.pulse != pulse;
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}
