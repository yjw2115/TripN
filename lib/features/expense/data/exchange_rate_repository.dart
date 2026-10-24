import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';

/// 그날 쓸 수출입은행 환율표. 비영업일이면 [effectiveDate]가 직전 영업일이다.
class OfficialRates {
  const OfficialRates({required this.effectiveDate, required this.krwPer});

  final String effectiveDate;

  /// 통화 코드 → 1단위당 원화.
  final Map<String, double> krwPer;

  factory OfficialRates.fromMap(Map<String, Object?> map) => OfficialRates(
        effectiveDate: map['effectiveDate'] as String,
        krwPer: {
          for (final e in (map['krwPer'] as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );
}

/// Firestore 구조
///   rates/{yyyy-MM-dd}   effectiveDate, krwPer{통화: 원}, source, fetchedAt
///     Cloud Functions(exchangeRates)만 쓴다. 앱은 읽기만 하고, 없을 때 함수를 부른다.
class ExchangeRateRepository {
  /// [callRates]는 exchangeRates 함수를 부른다 (테스트에서는 바꿔 끼운다).
  ExchangeRateRepository(this._db, this._callRates);

  final FirebaseFirestore _db;
  final Future<Map<String, Object?>> Function(String date) _callRates;

  Future<OfficialRates> officialRates(String date) async {
    final snap = await _db.collection('rates').doc(date).get();
    return OfficialRates.fromMap(snap.data() ?? await _callRates(date));
  }

  /// 지출에 고정할 환율.
  ///
  /// 수출입은행에 있는 통화는 그 고시 환율, 없는 통화는 여행에서 정한 환율([manualRates]).
  /// 둘 다 없으면 null (직접 정해야 한다). 환율표를 못 받으면 예외를 던지는데,
  /// 여행에서 정한 환율이 있으면 그것으로 대신한다.
  Future<FixedRate?> rateFor(
    Currency currency,
    DateTime paidAt, {
    Map<String, double> manualRates = const {},
  }) async {
    if (currency == Currency.krw) return FixedRate.krw;
    final manual = manualRates[currency.code];
    final FixedRate? manualRate = manual == null
        ? null
        : FixedRate(krwPerUnit: manual, source: RateSource.manual);
    final OfficialRates rates;
    try {
      rates = await officialRates(rateDateKey(paidAt));
    } catch (_) {
      if (manualRate != null) return manualRate;
      rethrow;
    }
    final official = rates.krwPer[koreaEximCode(currency)];
    if (official == null) return manualRate;
    return FixedRate(
      krwPerUnit: official,
      source: RateSource.koreaexim,
      date: rates.effectiveDate,
    );
  }
}
