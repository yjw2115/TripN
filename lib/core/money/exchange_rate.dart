import 'package:intl/intl.dart';

import 'currency.dart';

enum RateSource {
  /// 한국수출입은행 매매기준율.
  koreaexim,

  /// 수출입은행에 없는 통화(동·페소·대만 달러 등)라 여행에서 직접 정한 환율.
  manual,

  /// 원화 지출.
  krw;

  static RateSource fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => koreaexim);
}

/// 지출에 고정해 두는 원화 환율. 한 번 정하면 바꾸지 않아서 동행자 모두 같은 금액으로 정산한다.
class FixedRate {
  const FixedRate({required this.krwPerUnit, required this.source, this.date});

  static const krw = FixedRate(krwPerUnit: 1, source: RateSource.krw);

  /// 1달러, 1엔처럼 1단위당 원화.
  final double krwPerUnit;
  final RateSource source;

  /// 수출입은행 고시일 (yyyy-MM-dd). 직접 정한 환율과 원화 지출은 null.
  final String? date;

  /// 원 단위로 반올림한다. 0.0543(= 54.3원/1,000동)처럼 이진수로 딱 떨어지지 않는 환율은
  /// 65,000동이 3,529.4999…원이 되므로, 백만분의 1원에서 한 번 정리한 뒤 반올림한다.
  int toKrw(int minor, Currency currency) {
    final krw = currency.toMajor(minor) * krwPerUnit;
    return ((krw * 1e6).round() / 1e6).round();
  }

  Map<String, Object?> toMap() =>
      {'krwRate': krwPerUnit, 'rateSource': source.name, 'rateDate': date};

  /// 지출 문서에서 읽는다. 환율을 아직 못 정한 지출은 null.
  static FixedRate? fromMap(Map<String, Object?> map) {
    final rate = (map['krwRate'] as num?)?.toDouble();
    if (rate == null) return null;
    return FixedRate(
      krwPerUnit: rate,
      source: RateSource.fromName(map['rateSource'] as String?),
      date: map['rateDate'] as String?,
    );
  }
}

/// 수출입은행은 위안화를 역외 위안(CNH)으로 고시한다.
String koreaEximCode(Currency currency) =>
    currency.code == 'CNY' ? 'CNH' : currency.code;

/// 환율을 찾을 날짜 (yyyy-MM-dd). 고시는 서울 날짜라서, 서울보다 앞선 날짜는 서울 오늘로 본다.
String rateDateKey(DateTime paidAt, {DateTime? now}) {
  final seoulNow = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  final day = DateTime(paidAt.year, paidAt.month, paidAt.day);
  final today = DateTime(seoulNow.year, seoulNow.month, seoulNow.day);
  return DateFormat('yyyy-MM-dd').format(day.isAfter(today) ? today : day);
}

/// 환율을 보여주거나 물을 때 기준 단위. 1동처럼 너무 작으면 1,000동 = ?원으로 쓴다.
int rateReferenceUnits(Currency currency) => switch (currency.code) {
      'VND' => 1000,
      'JPY' || 'IDR' || 'MNT' || 'HUF' => 100,
      _ => 1,
    };

/// "100엔 = 925.12원", "1달러 = 1,385.5원".
String formatRate(FixedRate rate, Currency currency) {
  final units = rateReferenceUnits(currency);
  final krw = NumberFormat('#,##0.##', 'en_US').format(rate.krwPerUnit * units);
  return '${NumberFormat('#,##0', 'en_US').format(units)}${currency.nameKo} = $krw원';
}
