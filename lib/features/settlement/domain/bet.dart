/// 정산에 재미로 거는 내기. 미니게임으로 걸린 사람을 뽑고, 그 사람이 [SettlementBet.stake]만큼 더 낸다.
///
/// 여행 문서의 `settlementBet`에 하나만 둔다. 동행자 모두 같은 정산을 보고,
/// 지우면 원래 정산으로 돌아간다. 계산은 `settle`이 지금 지출로 그때그때 한다.
enum BetGame {
  ddakji('딱지 뒤집기', '차례로 한 장씩 뒤집어요. 빨간 딱지가 나오면 걸려요.'),
  wave('파도타기', '물고기 한 마리씩 맡아요. 가장 늦게 도착하면 걸려요.');

  const BetGame(this.label, this.howTo);

  final String label;
  final String howTo;

  static BetGame? fromName(String? name) =>
      values.where((g) => g.name == name).firstOrNull;
}

sealed class BetStake {
  const BetStake();
}

/// 잔돈 몰아주기: 참여한 사람의 보낼 돈은 [unit] 단위로 내리고 받을 돈은 올려서,
/// 남는 잔돈을 걸린 사람이 낸다.
class ChangeStake extends BetStake {
  const ChangeStake(this.unit);

  final int unit;

  /// "천 원", "만 원"
  String get unitLabel => switch (unit) {
    1000 => '천 원',
    10000 => '만 원',
    _ => '$unit원',
  };

  @override
  bool operator ==(Object other) => other is ChangeStake && other.unit == unit;

  @override
  int get hashCode => unit.hashCode;
}

/// 한 턱 쏘기: 지출 하나에서 참여한 사람들의 몫을 걸린 사람이 대신 낸다.
class TreatStake extends BetStake {
  const TreatStake(this.expenseId);

  final String expenseId;

  @override
  bool operator ==(Object other) =>
      other is TreatStake && other.expenseId == expenseId;

  @override
  int get hashCode => expenseId.hashCode;
}

class SettlementBet {
  const SettlementBet({
    required this.game,
    required this.stake,
    required this.loserId,
    required this.participantIds,
  });

  final BetGame game;
  final BetStake stake;

  /// 게임에서 걸린 멤버 id.
  final String loserId;

  /// 게임에 참여한 멤버 id. 이 사람들 사이에서만 돈이 옮겨 간다.
  final List<String> participantIds;

  Map<String, Object?> toMap() => {
    'game': game.name,
    ...switch (stake) {
      ChangeStake(:final unit) => {'stake': 'change', 'unit': unit},
      TreatStake(:final expenseId) => {
        'stake': 'treat',
        'expenseId': expenseId,
      },
    },
    'loserId': loserId,
    'participantIds': participantIds,
  };

  /// 모르는 게임·내기(새 버전에서 만든 것)나 깨진 값이면 null. 그러면 원래 정산을 보여준다.
  static SettlementBet? fromMap(Map? map) {
    if (map == null) return null;
    final game = BetGame.fromName(map['game'] as String?);
    final loserId = map['loserId'];
    final participants = map['participantIds'];
    if (game == null || loserId is! String || participants is! List) {
      return null;
    }
    final BetStake? stake = switch (map['stake']) {
      'change' => switch (map['unit']) {
        final num unit when unit > 0 => ChangeStake(unit.toInt()),
        _ => null,
      },
      'treat' => switch (map['expenseId']) {
        final String id => TreatStake(id),
        _ => null,
      },
      _ => null,
    };
    if (stake == null) return null;
    return SettlementBet(
      game: game,
      stake: stake,
      loserId: loserId,
      participantIds: participants.whereType<String>().toList(),
    );
  }
}
