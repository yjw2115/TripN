import 'package:intl/intl.dart';

import 'currency.dart';

/// 최소 단위 정수 금액을 "12,500원", "¥980", "\$12.50" 형태로 보여준다.
String formatMoney(int minor, Currency currency, {bool withSymbol = true}) {
  final pattern = currency.decimals == 0
      ? '#,##0'
      : '#,##0.${'0' * currency.decimals}';
  final text = NumberFormat(pattern, 'en_US').format(currency.toMajor(minor));
  if (!withSymbol) return text;
  if (currency.code == 'KRW') return '$text원';
  return '${currency.symbol}$text';
}

/// 그래프처럼 좁은 곳에 쓸 짧은 원화: "9,800", "4.5만", "123만", "1.2억".
String formatWonCompact(int krw) {
  String trim(double v) =>
      v < 100 ? v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '') : '${v.round()}';
  if (krw.abs() < 10000) return NumberFormat('#,##0', 'en_US').format(krw);
  if (krw.abs() < 100000000) return '${trim(krw / 10000)}만';
  return '${trim(krw / 100000000)}억';
}

/// 입력창에 보여줄 숫자 (천 단위 구분 없이).
String formatMoneyPlain(int minor, Currency currency) {
  final major = currency.toMajor(minor);
  return currency.decimals == 0
      ? major.round().toString()
      : major.toStringAsFixed(currency.decimals);
}

/// 사용자가 영수증에 적힌 그대로 입력한 금액을 최소 단위 정수로 바꾼다.
///
/// 나라마다 구분 기호가 달라서 통화를 보고 판단한다.
/// - 소수점이 없는 통화(동·엔·원): "." 과 "," 은 모두 천 단위 구분이다. "130.000" → 130000
/// - 그 밖의 통화: 마지막 구분 기호 뒤가 소수 자릿수 이하이면 소수점으로 본다.
///   "52.77" → 52.77, "11,85" → 11.85, "1.234,56" → 1234.56, "1,234" → 1234
int? parseMoneyInput(String input, Currency currency) {
  final s = input.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty || !RegExp(r'^[0-9.,]+$').hasMatch(s)) return null;
  if (!s.contains(RegExp(r'[0-9]'))) return null;

  var integerPart = s;
  var fraction = '';
  final last = s.lastIndexOf(RegExp(r'[.,]'));
  if (currency.decimals > 0 && last >= 0) {
    final after = s.substring(last + 1);
    if (after.isNotEmpty && after.length <= currency.decimals) {
      integerPart = s.substring(0, last);
      fraction = after;
    } else if (after.isEmpty) {
      integerPart = s.substring(0, last); // "12." 처럼 소수점만 친 상태
    }
  }
  final digits = integerPart.replaceAll(RegExp(r'[.,]'), '');
  final major = digits.isEmpty ? 0 : int.parse(digits);
  final minorDigits = fraction.padRight(currency.decimals, '0');
  return major * currency.minorFactor +
      (minorDigits.isEmpty ? 0 : int.parse(minorDigits));
}
