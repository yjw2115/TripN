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

/// 입력창에 보여줄 숫자 (천 단위 구분 없이).
String formatMoneyPlain(int minor, Currency currency) {
  final major = currency.toMajor(minor);
  return currency.decimals == 0
      ? major.round().toString()
      : major.toStringAsFixed(currency.decimals);
}

/// 사용자가 입력한 "1,234.5" 같은 문자열을 최소 단위 정수로 바꾼다.
int? parseMoneyInput(String input, Currency currency) {
  final cleaned = input.replaceAll(',', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null) return null;
  return currency.toMinor(value);
}
