import 'package:flutter/material.dart';

import '../../domain/bet.dart';
import 'ddakji_painter.dart';
import 'roulette_game.dart';

/// 게임을 나타내는 작은 그림. 딱지와 룰렛은 직접 그리고, 파도타기는 오른쪽으로 헤엄치는 열대어.
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
        BetGame.roulette => Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: const RouletteRimPainter(glow: 0, bulbs: 8),
              ),
              Transform.rotate(
                angle: -0.3,
                child: CustomPaint(
                  size: Size.square(size),
                  painter: const RouletteWheelPainter(count: 6),
                ),
              ),
              Positioned(
                top: 0,
                child: CustomPaint(
                  size: Size(size * 0.24, size * 0.26),
                  painter: const RoulettePointerPainter(),
                ),
              ),
            ],
          ),
      },
    );
  }
}
