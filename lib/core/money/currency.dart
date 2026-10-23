/// 통화 메타데이터.
///
/// 금액은 앱 전체에서 "최소 단위 정수"(minor units)로 다룬다.
/// 예) USD 12.50 → 1250, JPY 980 → 980, VND 45,000 → 45000.
/// [decimals]는 ISO 4217 공식값이 아니라 실제 영수증에서 쓰는 자릿수다
/// (예: TWD·IDR은 공식 2자리지만 실제로는 소수점을 쓰지 않는다).
class Currency {
  const Currency(this.code, this.decimals, this.symbol, this.nameKo);

  final String code;
  final int decimals;
  final String symbol;
  final String nameKo;

  int get minorFactor {
    var f = 1;
    for (var i = 0; i < decimals; i++) {
      f *= 10;
    }
    return f;
  }

  /// 영수증에 찍힌 금액(주 단위, 예: 12.5)을 최소 단위 정수로 바꾼다.
  int toMinor(num major) => (major * minorFactor).round();

  double toMajor(int minor) => minor / minorFactor;

  static const krw = Currency('KRW', 0, '₩', '원');

  static const List<Currency> all = [
    krw,
    Currency('JPY', 0, '¥', '엔'),
    Currency('USD', 2, '\$', '달러'),
    Currency('EUR', 2, '€', '유로'),
    Currency('CNY', 2, '¥', '위안'),
    Currency('VND', 0, '₫', '동'),
    Currency('THB', 2, '฿', '바트'),
    Currency('PHP', 2, '₱', '페소'),
    Currency('TWD', 0, 'NT\$', '대만 달러'),
    Currency('HKD', 2, 'HK\$', '홍콩 달러'),
    Currency('SGD', 2, 'S\$', '싱가포르 달러'),
    Currency('MYR', 2, 'RM', '링깃'),
    Currency('IDR', 0, 'Rp', '루피아'),
    Currency('GBP', 2, '£', '파운드'),
    Currency('CHF', 2, 'CHF', '스위스 프랑'),
    Currency('AUD', 2, 'A\$', '호주 달러'),
    Currency('CAD', 2, 'C\$', '캐나다 달러'),
    Currency('NZD', 2, 'NZ\$', '뉴질랜드 달러'),
    Currency('MOP', 2, 'MOP\$', '파타카'),
    Currency('MNT', 0, '₮', '투그릭'),
    Currency('TRY', 2, '₺', '리라'),
    Currency('CZK', 2, 'Kč', '코루나'),
    Currency('HUF', 0, 'Ft', '포린트'),
    Currency('AED', 2, 'AED', '디르함'),
  ];

  static final Map<String, Currency> _byCode = {for (final c in all) c.code: c};

  /// 목록에 없는 통화도 2자리 소수로 가정해 처리한다.
  static Currency of(String code) {
    final upper = code.trim().toUpperCase();
    return _byCode[upper] ?? Currency(upper, 2, upper, upper);
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
