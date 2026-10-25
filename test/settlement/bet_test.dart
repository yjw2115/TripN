import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/settlement/domain/bet.dart';
import 'package:travelen/features/settlement/domain/settlement.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(id: 'j', name: '지민', uid: 'u1');
const _minsu = Member(id: 'm', name: '민수');
const _seoyeon = Member(id: 's', name: '서연');
const _members = [_jimin, _minsu, _seoyeon];

Expense _expense(
  String id,
  String title,
  String payer,
  int total,
  List<String> together, {
  Currency currency = Currency.krw,
}) => Expense(
  id: id,
  title: title,
  category: ExpenseCategory.food,
  currency: currency,
  totalMinor: total,
  paidAt: DateTime(2026, 10, 23),
  payerId: payer,
  createdBy: 'u1',
  participantIds: together,
);

// 지민 100,000원(셋) → 33,334 / 33,333 / 33,333
// 민수 25,500원(민수·서연) → 12,750 / 12,750
// 받을 돈: 지민 +66,666 / 민수 −20,583 / 서연 −46,083
final _expenses = [
  _expense('dinner', '저녁', 'j', 100000, ['j', 'm', 's']),
  _expense('sushi', '스시로', 'm', 25500, ['m', 's']),
];

SettlementBet _bet(
  BetStake stake,
  String loser, [
  List<String> players = const ['j', 'm', 's'],
]) => SettlementBet(
  game: BetGame.ddakji,
  stake: stake,
  loserId: loser,
  participantIds: players,
);

Map<String, int> _nets(Settlement s) => {
  for (final b in s.balances) b.member.id: b.net,
};

void main() {
  test('without a bet the settlement is unchanged', () {
    final result = settle(_expenses, _members);
    expect(_nets(result), {'j': 66666, 'm': -20583, 's': -46083});
    expect(result.bet, isNull);
    expect(result.betSkip, isNull);
  });

  group('change', () {
    test('the loser pays everyone else’s loose change', () {
      final result = settle(
        _expenses,
        _members,
        bet: _bet(const ChangeStake(1000), 's'),
      );
      // 지민은 받을 돈을 올리고(+334), 민수는 보낼 돈을 내린다(−583).
      expect(_nets(result), {'j': 67000, 'm': -20000, 's': -47000});
      expect(result.bet!.loser, _seoyeon);
      expect(result.bet!.amount, 917);
      expect([for (final b in result.balances) b.bet], [-334, -583, 917]);
      expect(
        [for (final t in result.transfers) (t.from.id, t.to.id, t.amount)],
        [('s', 'j', 47000), ('m', 'j', 20000)],
      );
    });

    test('a loser who is owed money just receives less', () {
      final result = settle(
        _expenses,
        _members,
        bet: _bet(const ChangeStake(1000), 'j'),
      );
      expect(_nets(result), {'j': 66000, 'm': -20000, 's': -46000});
      expect(result.bet!.amount, 666);
    });

    test('rounds to ten thousand won', () {
      final result = settle(
        _expenses,
        _members,
        bet: _bet(const ChangeStake(10000), 's'),
      );
      expect(_nets(result), {'j': 70000, 'm': -20000, 's': -50000});
    });

    test('only players move money; others keep their exact amount', () {
      final result = settle(
        _expenses,
        _members,
        bet: _bet(const ChangeStake(1000), 's', ['j', 's']),
      );
      expect(_nets(result), {'j': 67000, 'm': -20583, 's': -46417});
    });
  });

  group('treat', () {
    test('the loser pays the other players’ shares of one expense', () {
      final result = settle(
        _expenses,
        _members,
        bet: _bet(const TreatStake('sushi'), 'j'),
      );
      // 민수·서연의 스시로 몫 12,750원씩을 지민이 낸다.
      expect(_nets(result), {'j': 41166, 'm': -7833, 's': -33333});
      expect(result.bet!.amount, 25500);
      expect(result.bet!.expense!.title, '스시로');
    });

    test("the loser's own share stays theirs", () {
      final result = settle(
        _expenses,
        _members,
        bet: _bet(const TreatStake('sushi'), 's'),
      );
      expect(result.bet!.amount, 12750);
      expect(_nets(result), {'j': 66666, 'm': -7833, 's': -58833});
    });

    test('is skipped when the expense is gone or has no rate yet', () {
      expect(
        settle(
          _expenses,
          _members,
          bet: _bet(const TreatStake('deleted'), 's'),
        ).betSkip,
        BetSkip.expenseGone,
      );
      final unrated = _expense('ramen', '라멘', 'j', 3000, [
        'j',
        'm',
      ], currency: Currency.of('VND'));
      final result = settle(
        [..._expenses, unrated],
        _members,
        bet: _bet(const TreatStake('ramen'), 's'),
      );
      expect(result.betSkip, BetSkip.expenseUnrated);
      expect(result.bet, isNull);
      expect(_nets(result), {'j': 66666, 'm': -20583, 's': -46083});
    });
  });

  test('a treat on an expense outside this settlement is skipped', () {
    final result = settle(
      _expenses,
      _members,
      bet: _bet(const TreatStake('sushi'), 's'),
      only: {for (final e in _expenses) if (e.id != 'sushi') e.id},
    );
    expect(result.betSkip, BetSkip.expenseLeftOut);
    expect(result.bet, isNull);
  });

  test('is skipped when the loser left the trip', () {
    final result = settle(
      _expenses,
      _members,
      bet: _bet(const ChangeStake(1000), 'gone'),
    );
    expect(result.betSkip, BetSkip.loserGone);
    expect(_nets(result), {'j': 66666, 'm': -20583, 's': -46083});
  });

  test('items still split by who ate them before the treat moves shares', () {
    final receipt = Expense(
      id: 'r',
      title: '이자카야',
      category: ExpenseCategory.food,
      currency: Currency.krw,
      totalMinor: 30000,
      paidAt: DateTime(2026, 10, 23),
      payerId: 'j',
      createdBy: 'u1',
      participantIds: const ['j', 'm', 's'],
      receipt: const Receipt(
        merchantName: '이자카야',
        currency: Currency.krw,
        items: [
          ReceiptItem(
            id: 'a',
            name: '사케',
            amountMinor: 12000,
            participantIds: ['m'],
          ),
          ReceiptItem(id: 'b', name: '꼬치', amountMinor: 18000),
        ],
        totalMinor: 30000,
      ),
    );
    final result = settle(
      [receipt],
      _members,
      bet: _bet(const TreatStake('r'), 's'),
    );
    // 지민 몫 6,000원(꼬치 1/3)과 민수 몫 18,000원(사케 + 꼬치 1/3)을 서연이 낸다.
    expect([for (final b in result.balances) b.bet], [-6000, -18000, 24000]);
  });

  test('round-trips through Firestore and ignores unknown games', () {
    for (final bet in [
      _bet(const ChangeStake(10000), 'm'),
      SettlementBet(
        game: BetGame.wave,
        stake: const TreatStake('sushi'),
        loserId: 's',
        participantIds: const ['j', 's'],
      ),
    ]) {
      final back = SettlementBet.fromMap(bet.toMap())!;
      expect(back.game, bet.game);
      expect(back.stake, bet.stake);
      expect(back.loserId, bet.loserId);
      expect(back.participantIds, bet.participantIds);
    }
    expect(
      SettlementBet.fromMap({
        'game': 'ladder',
        'stake': 'change',
        'unit': 1000,
        'loserId': 'm',
        'participantIds': ['m'],
      }),
      isNull,
    );
    expect(SettlementBet.fromMap(null), isNull);
  });

  test('the request message says who lost and how much more they pay', () {
    final result = settle(
      _expenses,
      _members,
      bet: _bet(const TreatStake('sushi'), 's'),
    );
    expect(
      settlementMessage('도쿄 여행', result),
      "[여행N] '도쿄 여행' 정산\n"
      '총 지출 125,500원 · 3명\n'
      '\n'
      "🎲 딱지 뒤집기 내기: 서연님이 '스시로'를 쏴요 (+12,750원)\n"
      '\n'
      '서연 → 지민 58,833원\n'
      '민수 → 지민 7,833원',
    );
  });

  test('picks the object particle from the last syllable', () {
    expect(particle('스시로', '을', '를'), '를');
    expect(particle('저녁', '을', '를'), '을');
    expect(particle('Starbucks', '을', '를'), '을(를)');
  });
}
