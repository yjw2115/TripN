import 'package:collection/collection.dart';

import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../expense/domain/expense.dart';
import '../../trip/domain/trip.dart';
import 'bet.dart';

/// [total]을 [weights] 비율로 나눈다. 나눈 값의 합은 언제나 [total]과 같다.
///
/// 몫의 소수점 아래는 버리고, 남는 1원은 버린 부분이 큰 사람부터 하나씩 준다.
/// 버린 부분이 같으면 [priority]에 먼저 나온 사람(결제자)이, 그다음은 [weights] 순서대로 받는다.
/// 무게가 모두 0이면 똑같이 나눈다.
Map<String, int> allocate(
  int total,
  Map<String, int> weights, {
  List<String> priority = const [],
}) {
  if (weights.isEmpty) return {};
  // 할인처럼 음수인 금액은 부호를 떼고 나눈 뒤 되돌린다 (Dart의 ~/와 %는 음수에서 짝이 맞지 않는다).
  if (total < 0) {
    return allocate(-total, weights, priority: priority)
        .map((id, v) => MapEntry(id, -v));
  }
  final positive = {
    for (final e in weights.entries) e.key: e.value > 0 ? e.value : 0,
  };
  final sum = positive.values.fold(0, (a, b) => a + b);
  final w = sum == 0 ? {for (final k in positive.keys) k: 1} : positive;
  final weightSum = sum == 0 ? w.length : sum;

  final result = <String, int>{};
  final remainders = <String, int>{};
  var given = 0;
  for (final e in w.entries) {
    final exact = total * e.value;
    result[e.key] = exact ~/ weightSum;
    remainders[e.key] = exact % weightSum;
    given += result[e.key]!;
  }
  final order = w.keys.toList();
  int rank(String id) {
    final i = priority.indexOf(id);
    return i < 0 ? priority.length + order.indexOf(id) : i;
  }

  final byRemainder = [...order]..sort((a, b) {
      final r = remainders[b]!.compareTo(remainders[a]!);
      return r != 0 ? r : rank(a).compareTo(rank(b));
    });
  for (var i = 0; i < total - given; i++) {
    final id = byRemainder[i % byRemainder.length];
    result[id] = result[id]! + 1;
  }
  return result;
}

/// 한 지출에서 각자 낼 몫 (원). 환율을 아직 못 정한 지출은 null.
///
/// 품목이 있으면 품목마다 그 품목을 함께 쓴 사람끼리 나누고, 그 비율대로 총액(세금·봉사료·
/// 팁·할인 포함)을 나눈다. 품목이 없으면 함께 쓴 사람끼리 똑같이 나눈다.
Map<String, int>? sharesOf(Expense expense, List<String> memberIds) {
  final total = expense.totalKrw;
  if (total == null) return null;
  final together =
      expense.participantIds.isEmpty ? memberIds : expense.participantIds;
  if (together.isEmpty) return {expense.payerId: total};
  final priority = [expense.payerId];

  final weights = {for (final id in together) id: 0};
  final items = expense.receipt?.items ?? const [];
  if (items.isEmpty) {
    weights.updateAll((_, _) => 1);
  } else {
    for (final item in items) {
      final who =
          item.participantIds.isEmpty ? together : item.participantIds;
      final split = allocate(item.netMinor, {for (final id in who) id: 1},
          priority: priority);
      split.forEach((id, minor) => weights[id] = (weights[id] ?? 0) + minor);
    }
  }
  return allocate(total, weights, priority: priority);
}

class MemberBalance {
  const MemberBalance({
    required this.member,
    required this.paid,
    required this.owed,
    this.bet = 0,
  });

  final Member member;

  /// 내가 결제한 금액.
  final int paid;

  /// 내 몫으로 쓴 금액.
  final int owed;

  /// 내기로 더 내는 돈 (걸린 사람은 양수, 덕을 본 사람은 음수).
  final int bet;

  /// 양수면 받을 돈, 음수면 보낼 돈.
  int get net => paid - owed - bet;
}

class Transfer {
  const Transfer({required this.from, required this.to, required this.amount});

  final Member from;
  final Member to;
  final int amount;
}

/// 정산에 반영한 내기.
class AppliedBet {
  const AppliedBet({
    required this.bet,
    required this.loser,
    required this.amount,
    this.expense,
  });

  final SettlementBet bet;
  final Member loser;

  /// 걸린 사람이 더 내는 돈 (다른 참여자가 덜 내는 돈의 합).
  final int amount;

  /// 한 턱 쏘기로 고른 지출.
  final Expense? expense;
}

/// 내기를 반영하지 못한 까닭. 그동안은 원래 정산을 보여준다.
enum BetSkip {
  /// 걸린 사람이 여행에서 빠졌다.
  loserGone,

  /// 한 턱 쏘기로 고른 지출이 지워졌다.
  expenseGone,

  /// 한 턱 쏘기로 고른 지출의 환율을 아직 못 정했다.
  expenseUnrated,
}

class Settlement {
  const Settlement({
    required this.totalKrw,
    required this.balances,
    required this.transfers,
    required this.unratedCount,
    this.bet,
    this.betSkip,
  });

  /// 환율을 정한 지출의 원화 합계.
  final int totalKrw;
  final List<MemberBalance> balances;

  /// 누가 누구에게 얼마. 송금 횟수가 적게 짝짓는다.
  final List<Transfer> transfers;

  /// 환율을 아직 못 정해서 계산에서 빠진 지출 수.
  final int unratedCount;

  /// 반영한 내기. 내기가 없거나 반영하지 못했으면 null.
  final AppliedBet? bet;

  /// 내기가 있는데 반영하지 못한 까닭.
  final BetSkip? betSkip;
}

/// 모두의 지출을 모아 각자 낸 돈과 쓴 돈을 맞추고, 보낼 돈을 정한다. 여행 중간에도 계산할 수 있다.
/// [bet]이 있으면 그 결과대로 걸린 사람이 더 낸다.
Settlement settle(List<Expense> expenses, List<Member> members,
    {SettlementBet? bet}) {
  final ids = [for (final m in members) m.id];
  final paid = {for (final id in ids) id: 0};
  final owed = {for (final id in ids) id: 0};
  var total = 0;
  var unrated = 0;
  for (final e in expenses) {
    final shares = sharesOf(e, ids);
    if (shares == null) {
      unrated++;
      continue;
    }
    total += e.totalKrw!;
    paid[e.payerId] = (paid[e.payerId] ?? 0) + e.totalKrw!;
    shares.forEach((id, krw) => owed[id] = (owed[id] ?? 0) + krw);
  }

  final outcome = bet == null
      ? null
      : _applyBet(bet, expenses, members, paid: paid, owed: owed);
  final delta = outcome?.delta ?? const <String, int>{};
  final balances = [
    for (final m in members)
      MemberBalance(
          member: m,
          paid: paid[m.id]!,
          owed: owed[m.id]!,
          bet: delta[m.id] ?? 0),
  ];
  return Settlement(
    totalKrw: total,
    balances: balances,
    transfers: _transfers(balances),
    unratedCount: unrated,
    bet: outcome?.applied,
    betSkip: outcome?.skip,
  );
}

typedef _BetOutcome = ({
  AppliedBet? applied,
  BetSkip? skip,
  Map<String, int> delta,
});

/// 내기로 각자 더 낼 돈([_BetOutcome.delta], 합은 0). 반영하지 못하면 그 까닭.
_BetOutcome _applyBet(
  SettlementBet bet,
  List<Expense> expenses,
  List<Member> members, {
  required Map<String, int> paid,
  required Map<String, int> owed,
}) {
  _BetOutcome skip(BetSkip why) => (applied: null, skip: why, delta: const {});

  final loser = members.firstWhereOrNull((m) => m.id == bet.loserId);
  if (loser == null) return skip(BetSkip.loserGone);
  final ids = [for (final m in members) m.id];
  // 여행에서 빠진 참여자는 건너뛴다.
  final others = {
    for (final id in bet.participantIds)
      if (id != loser.id && ids.contains(id)) id,
  };
  final delta = <String, int>{};
  Expense? expense;
  switch (bet.stake) {
    case ChangeStake(:final unit):
      for (final id in others) {
        final net = paid[id]! - owed[id]!;
        // 보낼 돈은 내리고 받을 돈은 올린다. 차이는 걸린 사람이 낸다.
        final rounded =
            net >= 0 ? (net + unit - 1) ~/ unit * unit : -(-net ~/ unit * unit);
        delta[id] = net - rounded;
      }
    case TreatStake(:final expenseId):
      expense = expenses.firstWhereOrNull((e) => e.id == expenseId);
      if (expense == null) return skip(BetSkip.expenseGone);
      final shares = sharesOf(expense, ids);
      if (shares == null) return skip(BetSkip.expenseUnrated);
      for (final id in others) {
        delta[id] = -(shares[id] ?? 0);
      }
  }
  final amount = -delta.values.fold(0, (a, b) => a + b);
  delta[loser.id] = amount;
  return (
    applied:
        AppliedBet(bet: bet, loser: loser, amount: amount, expense: expense),
    skip: null,
    delta: delta,
  );
}

/// 받침이 있으면 [withFinal], 없으면 [without]. 한글로 끝나지 않으면 "을(를)"처럼 둘 다.
String particle(String word, String withFinal, String without) {
  final last = word.trim().runes.lastOrNull;
  if (last == null || last < 0xAC00 || last > 0xD7A3) {
    return '$withFinal($without)';
  }
  return (last - 0xAC00) % 28 == 0 ? without : withFinal;
}

/// "민수님이 잔돈을 몰아서 내요", "민수님이 '스시로'를 쏴요"
String betSummary(AppliedBet applied) {
  final name = applied.loser.name;
  switch (applied.bet.stake) {
    case ChangeStake():
      return '$name님이 잔돈을 몰아서 내요';
    case TreatStake():
      final title = applied.expense!.title;
      return "$name님이 '$title'${particle(title, '을', '를')} 쏴요";
  }
}

/// 가장 많이 보낼 사람과 가장 많이 받을 사람을 차례로 짝짓는다 (최대 인원 − 1번).
List<Transfer> _transfers(List<MemberBalance> balances) {
  final debtors = [
    for (final b in balances)
      if (b.net < 0) (member: b.member, left: -b.net),
  ]..sort((a, b) => b.left.compareTo(a.left));
  final creditors = [
    for (final b in balances)
      if (b.net > 0) (member: b.member, left: b.net),
  ]..sort((a, b) => b.left.compareTo(a.left));

  final transfers = <Transfer>[];
  var d = 0, c = 0;
  var debt = debtors.isEmpty ? 0 : debtors[0].left;
  var credit = creditors.isEmpty ? 0 : creditors[0].left;
  while (d < debtors.length && c < creditors.length) {
    final amount = debt < credit ? debt : credit;
    transfers.add(Transfer(
        from: debtors[d].member, to: creditors[c].member, amount: amount));
    debt -= amount;
    credit -= amount;
    if (debt == 0 && ++d < debtors.length) debt = debtors[d].left;
    if (credit == 0 && ++c < creditors.length) credit = creditors[c].left;
  }
  return transfers;
}

/// 정산 금액을 현지 화폐로도 보여줄 통화와 환율. 현지 돈으로 정산하는 일행을 위한 참고 금액이고,
/// 복사와 정산 요청 메시지는 원화로 한다.
class LocalCurrency {
  const LocalCurrency({required this.currency, required this.krwPerUnit});

  final Currency currency;

  /// 이 여행에서 이 통화로 쓴 지출의 평균 환율 (원화 합계 ÷ 현지 화폐 합계).
  final double krwPerUnit;

  int fromKrw(int krw) => currency.toMinor(krw / krwPerUnit);
}

/// 원화가 아닌 통화를 많이 쓴 순서로. 환율을 정한 지출만 센다.
List<LocalCurrency> localCurrenciesOf(List<Expense> expenses) {
  final krw = <Currency, int>{};
  final minor = <Currency, int>{};
  for (final e in expenses) {
    final total = e.totalKrw;
    if (e.currency == Currency.krw || total == null || e.totalMinor <= 0) continue;
    krw[e.currency] = (krw[e.currency] ?? 0) + total;
    minor[e.currency] = (minor[e.currency] ?? 0) + e.totalMinor;
  }
  final currencies = krw.keys.toList()
    ..sort((a, b) => krw[b]!.compareTo(krw[a]!));
  return [
    for (final c in currencies)
      LocalCurrency(currency: c, krwPerUnit: krw[c]! / c.toMajor(minor[c]!)),
  ];
}

String _won(int krw) => formatMoney(krw, Currency.krw);

/// 메신저로 보낼 정산 요청. 받을 사람의 계좌가 있으면 함께 적는다.
String settlementMessage(String tripName, Settlement settlement) {
  final lines = <String>[
    "[여행N] '$tripName' 정산",
    '총 지출 ${_won(settlement.totalKrw)} · ${settlement.balances.length}명',
    '',
  ];
  if (settlement.bet case final bet?) {
    lines.addAll([
      '🎲 ${bet.bet.game.label} 내기: ${betSummary(bet)} (+${_won(bet.amount)})',
      '',
    ]);
  }
  if (settlement.transfers.isEmpty) {
    lines.add('서로 보낼 돈이 없어요.');
  } else {
    for (final t in settlement.transfers) {
      lines.add('${t.from.name} → ${t.to.name} ${_won(t.amount)}');
    }
    final receivers = {for (final t in settlement.transfers) t.to.id: t.to};
    final accounts = [
      for (final m in receivers.values)
        if (m.account != null) '${m.name}: ${m.account!.display}',
    ];
    if (accounts.isNotEmpty) lines.addAll(['', '받을 계좌', ...accounts]);
  }
  if (settlement.unratedCount > 0) {
    lines.addAll(['', '환율을 아직 정하지 못한 지출 ${settlement.unratedCount}건은 빠져 있어요.']);
  }
  return lines.join('\n');
}
