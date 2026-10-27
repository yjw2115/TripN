import 'package:collection/collection.dart';

import '../../../core/money/currency.dart';
import '../../expense/domain/expense.dart';
import '../../receipt/domain/receipt.dart';
import '../../settlement/domain/settlement.dart';
import '../../trip/domain/trip.dart';

/// 분류 하나에 쓴 돈.
class CategorySpend {
  const CategorySpend({
    required this.category,
    required this.krw,
    required this.count,
    required this.percent,
  });

  final ExpenseCategory category;
  final int krw;

  /// 이 분류의 지출 건수.
  final int count;

  /// 전체에서 차지하는 비율 (정수). 모든 분류를 더하면 100이다.
  final int percent;
}

/// 하루에 쓴 돈. 분류별로 나눠 둔다.
class DaySpend {
  const DaySpend({required this.day, this.byCategory = const {}});

  final DateTime day;
  final Map<ExpenseCategory, int> byCategory;

  int get krw => byCategory.values.sum;

  /// 이날 가장 많이 쓴 분류. 쓴 돈이 없으면 null.
  ExpenseCategory? get topCategory =>
      maxBy(byCategory.entries, (MapEntry<ExpenseCategory, int> e) => e.value)
          ?.key;
}

/// 지출 한 건과 그중 통계에 넣은 금액 (여행 전체면 총액, 한 사람만 보면 그 사람 몫).
typedef ExpenseSpend = ({Expense expense, int krw});

/// 동행자 한 명이 결제한 돈과 자기 몫으로 쓴 돈.
class MemberSpend {
  const MemberSpend(
      {required this.member, required this.paid, required this.used});

  final Member member;
  final int paid;
  final int used;
}

/// 한 통화로 쓴 돈.
class CurrencySpend {
  const CurrencySpend({
    required this.currency,
    required this.minor,
    required this.krw,
    required this.percent,
  });

  final Currency currency;
  final int minor;
  final int krw;

  /// 원화로 본 전체 지출에서 차지하는 비율. 모든 통화를 더하면 100이다.
  final int percent;

  /// 이 통화로 쓴 지출의 평균 환율 (1단위당 원화).
  double get krwPerUnit => minor == 0 ? 0 : krw / currency.toMajor(minor);
}

class TripStats {
  const TripStats({
    required this.totalKrw,
    required this.unratedCount,
    required this.categories,
    required this.days,
    required this.spends,
    required this.members,
    required this.currencies,
  });

  /// 환율을 정한 지출의 원화 합계 (한 사람만 보면 그 사람 몫의 합계).
  final int totalKrw;

  /// 환율을 아직 못 정해서 빠진 지출 수.
  final int unratedCount;

  /// 많이 쓴 분류부터. 쓴 돈이 없는 분류는 없다.
  final List<CategorySpend> categories;

  /// 첫 지출한 날부터 마지막 지출한 날까지 하루씩 (쓰지 않은 날도 넣는다).
  /// 두 달이 넘게 벌어져 있으면 날짜를 잘못 넣은 지출이 섞인 것이라 쓴 날만 넣는다.
  final List<DaySpend> days;

  /// 통계에 넣은 지출. 큰 금액부터.
  final List<ExpenseSpend> spends;

  /// 동행자마다 결제한 돈과 쓴 돈. 한 사람만 볼 때도 여행 전체로 센다.
  final List<MemberSpend> members;

  /// 많이 쓴 통화부터. 한 사람만 볼 때는 비어 있다 (몫은 원화로만 나눈다).
  final List<CurrencySpend> currencies;

  int get count => spends.length;

  bool get isEmpty => spends.isEmpty;

  /// 지출한 기간의 하루 평균.
  int get perDay => days.isEmpty ? 0 : totalKrw ~/ days.length;

  /// 가장 많이 쓴 날. 같으면 앞선 날.
  DaySpend? get peakDay =>
      maxBy(days, (DaySpend d) => d.krw, compare: (a, b) => a.compareTo(b));
}

/// 쓴 날이 이보다 길게 벌어지면 사이의 빈 날을 채우지 않는다.
const _maxFilledDays = 62;

/// 여행의 지출을 분류·날짜·동행자·통화별로 모은다. 미리 정산을 마친 지출도 넣는다.
/// [memberId]가 있으면 그 사람 몫만 센다 (정산에서 각자 몫을 나누는 것과 같은 계산).
/// 환율을 아직 못 정한 지출은 원화로 더할 수 없어서 뺀다.
TripStats tripStats(List<Expense> expenses, List<Member> members,
    {String? memberId}) {
  final ids = [for (final m in members) m.id];
  final paid = {for (final id in ids) id: 0};
  final used = {for (final id in ids) id: 0};
  final spends = <ExpenseSpend>[];
  final minorByCurrency = <Currency, int>{};
  final krwByCurrency = <Currency, int>{};
  var unrated = 0;
  for (final e in expenses) {
    final shares = sharesOf(e, ids);
    if (shares == null) {
      unrated++;
      continue;
    }
    final total = e.totalKrw!;
    if (paid.containsKey(e.payerId)) paid[e.payerId] = paid[e.payerId]! + total;
    shares.forEach((id, krw) {
      if (used.containsKey(id)) used[id] = used[id]! + krw;
    });
    final krw = memberId == null ? total : shares[memberId] ?? 0;
    if (krw <= 0) continue;
    spends.add((expense: e, krw: krw));
    if (memberId == null) {
      minorByCurrency[e.currency] =
          (minorByCurrency[e.currency] ?? 0) + e.totalMinor;
      krwByCurrency[e.currency] = (krwByCurrency[e.currency] ?? 0) + krw;
    }
  }
  spends.sort((a, b) => b.krw.compareTo(a.krw));
  final totalKrw = spends.fold(0, (sum, s) => sum + s.krw);

  final krwByCategory = <ExpenseCategory, int>{};
  final countByCategory = <ExpenseCategory, int>{};
  for (final s in spends) {
    final c = s.expense.category;
    krwByCategory[c] = (krwByCategory[c] ?? 0) + s.krw;
    countByCategory[c] = (countByCategory[c] ?? 0) + 1;
  }
  final categoryPercent = _percents(krwByCategory);
  final categories = [
    for (final c in krwByCategory.keys)
      CategorySpend(
          category: c,
          krw: krwByCategory[c]!,
          count: countByCategory[c]!,
          percent: categoryPercent[c]!),
  ]..sort((a, b) {
      final byKrw = b.krw.compareTo(a.krw);
      return byKrw != 0 ? byKrw : a.category.index.compareTo(b.category.index);
    });

  final currencyPercent = _percents(krwByCurrency);
  final currencies = [
    for (final c in krwByCurrency.keys)
      CurrencySpend(
          currency: c,
          minor: minorByCurrency[c]!,
          krw: krwByCurrency[c]!,
          percent: currencyPercent[c]!),
  ]..sort((a, b) => b.krw.compareTo(a.krw));

  return TripStats(
    totalKrw: totalKrw,
    unratedCount: unrated,
    categories: categories,
    days: _days(spends),
    spends: spends,
    members: [
      for (final m in members)
        MemberSpend(member: m, paid: paid[m.id]!, used: used[m.id]!),
    ],
    currencies: currencies,
  );
}

/// 금액을 정수 퍼센트로. 합이 정확히 100이 되게 [allocate]로 나눈다.
Map<K, int> _percents<K>(Map<K, int> amounts) {
  final keys = amounts.keys.toList();
  final split = allocate(100, {
    for (final (i, k) in keys.indexed) '$i': amounts[k]!,
  });
  return {for (final (i, k) in keys.indexed) k: split['$i']!};
}

List<DaySpend> _days(List<ExpenseSpend> spends) {
  final byDay = <DateTime, Map<ExpenseCategory, int>>{};
  for (final s in spends) {
    final at = s.expense.paidAt;
    final day = byDay.putIfAbsent(DateTime(at.year, at.month, at.day), () => {});
    day[s.expense.category] = (day[s.expense.category] ?? 0) + s.krw;
  }
  if (byDay.isEmpty) return const [];
  final sorted = byDay.keys.sorted((a, b) => a.compareTo(b));
  final first = sorted.first;
  final last = sorted.last;
  // 서머타임이 바뀌는 날이 끼면 자정끼리의 차이가 23시간이라 UTC로 센다.
  final span = DateTime.utc(last.year, last.month, last.day)
      .difference(DateTime.utc(first.year, first.month, first.day))
      .inDays;
  if (span >= _maxFilledDays) {
    return [for (final d in sorted) DaySpend(day: d, byCategory: byDay[d]!)];
  }
  // 하루씩 더할 때 Duration 대신 날짜로 더한다 (서머타임이 있는 곳에서도 자정에 맞게).
  return [
    for (var i = 0; i <= span; i++)
      if (DateTime(first.year, first.month, first.day + i) case final d)
        DaySpend(day: d, byCategory: byDay[d] ?? const {}),
  ];
}
