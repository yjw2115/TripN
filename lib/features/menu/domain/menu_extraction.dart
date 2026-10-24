import '../../../core/money/currency.dart';
import 'menu.dart';

/// 메뉴판 인식 결과. 인식기와 상관없이 같은 형태다.
class MenuExtraction {
  const MenuExtraction(
      {required this.isMenu, required this.menu, required this.warnings});

  /// 사진이 메뉴판이 아니면 false.
  final bool isMenu;

  /// 아직 저장 전이라 id가 빈 문자열이다.
  final Menu menu;

  /// 사용자에게 보여줄 참고 사항 (한국어).
  final List<String> warnings;

  /// LLM이 돌려준 JSON(스키마: `menuJsonSchema`)을 앱 모델로 바꾼다.
  factory MenuExtraction.fromModelJson(Map<String, Object?> json) {
    final currency = Currency.of(_str(json['currency'], fallback: 'KRW'));
    final country = _str(json['country_code']).toUpperCase();
    final items = <MenuItem>[];
    for (final s in (json['sections'] as List?) ?? const []) {
      final section = Map<String, Object?>.from(s as Map);
      final sectionName =
          _str(section['name_ko'], fallback: _str(section['name']));
      for (final i in (section['items'] as List?) ?? const []) {
        final m = Map<String, Object?>.from(i as Map);
        final name = _str(m['name']);
        final nameKo = _str(m['name_ko']);
        if (name.isEmpty && nameKo.isEmpty) continue;
        items.add(MenuItem(
          id: 'i${items.length}',
          name: name.isEmpty ? nameKo : name,
          nameKo: nameKo,
          descriptionKo: _str(m['description_ko']),
          section: sectionName,
          priceMinor: currency.toMinor(_num(m['price']).abs()),
        ));
      }
    }

    final (taxIncluded, taxRate) = _tax(
      _str(json['tax'], fallback: 'unknown'),
      _num(json['tax_rate_percent']).toDouble(),
      country,
    );
    return MenuExtraction(
      isMenu: json['is_menu'] as bool? ?? true,
      warnings: ((json['warnings'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      menu: Menu(
        id: '',
        storeName: _str(json['store_name']),
        currency: currency,
        countryCode: country,
        items: items,
        taxIncluded: taxIncluded,
        taxRatePercent: taxRate,
        serviceChargePercent:
            _num(json['service_charge_percent']).toDouble().clamp(0, 30),
      ),
    );
  }
}

/// 세금 표기가 없으면 그 나라의 관행을 따른다. 별도인데 세율을 모르면 0으로 두고
/// 사용자가 미리 보는 영수증에서 정하게 한다 (미국·캐나다는 도시마다 다르다).
(bool, double) _tax(String state, double rate, String country) {
  final safeRate = rate.clamp(0, 30).toDouble();
  switch (state) {
    case 'included':
      return (true, 0);
    case 'excluded':
      return (false, safeRate > 0 ? safeRate : (_standardExcludedRate[country] ?? 0));
    default:
      return _taxExcludedByDefault.contains(country)
          ? (false, safeRate)
          : (true, 0);
  }
}

/// 메뉴판에 따로 적혀 있지 않아도 세금을 계산대에서 더하는 나라.
const _taxExcludedByDefault = {'US', 'CA'};

/// "세금 별도"라고만 적혀 있을 때 쓸 표준 세율.
const _standardExcludedRate = {'JP': 10.0, 'TH': 7.0, 'SG': 9.0, 'MY': 6.0};

String _str(Object? v, {String fallback = ''}) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

num _num(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.replaceAll(',', '')) ?? 0;
  return 0;
}
