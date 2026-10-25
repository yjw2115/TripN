import 'package:flutter/material.dart';

import '../../domain/bet.dart';
import 'ddakji_painter.dart';

/// 게임을 나타내는 작은 그림. 딱지는 직접 그리고, 파도타기는 오른쪽으로 헤엄치는 열대어.
class GameIcon extends StatelessWidget {
  const GameIcon(this.game, {super.key, this.size = 24});

  final BetGame game;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: switch (game) {
        BetGame.ddakji => Padding(
            padding: EdgeInsets.all(size * 0.1),
            child: Transform.rotate(
              angle: -0.15,
              child: CustomPaint(
                painter: DdakjiPainter.front(ddakjiPapers.first),
              ),
            ),
          ),
        BetGame.wave => Transform.flip(
            flipX: true,
            child: const FittedBox(
              child: Text('🐠', style: TextStyle(fontSize: 40)),
            ),
          ),
      },
    );
  }
}
