/// 돈 받을 계좌의 은행. [Bank.all]은 많이 쓰는 순서다 (송금 앱의 은행 목록처럼).
///
/// 아이콘은 은행 앱 아이콘을 쓰고, 앱 아이콘이 은행 로고와 많이 다르면 은행 심볼을 쓴다.
/// 아이콘이 없는 은행은 이름 첫 글자로 그린다.
class Bank {
  const Bank(this.label, this.name, {this.icon, this.aliases = const []});

  /// 고르는 화면에 쓰는 짧은 이름 ("국민").
  final String label;

  /// 계좌에 저장하고 복사할 때 쓰는 이름 ("KB국민은행").
  final String name;

  /// assets/banks/ 안의 파일 이름 (확장자 없이).
  final String? icon;

  /// 예전에 직접 적은 은행 이름을 알아보는 다른 이름.
  final List<String> aliases;

  String? get asset => icon == null ? null : 'assets/banks/$icon.png';

  static const all = [
    Bank('국민', 'KB국민은행', icon: 'kb', aliases: ['KB', 'KB국민', 'kookmin']),
    Bank('신한', '신한은행', icon: 'shinhan'),
    Bank('카카오뱅크', '카카오뱅크', icon: 'kakao', aliases: ['카카오', '카뱅', 'kakaobank']),
    Bank('농협', 'NH농협은행', icon: 'nh', aliases: ['NH', 'NH농협', '농협중앙회']),
    Bank('토스뱅크', '토스뱅크', icon: 'toss', aliases: ['토스', 'toss']),
    Bank('우리', '우리은행', icon: 'woori'),
    Bank('하나', '하나은행', icon: 'hana', aliases: ['KEB하나', '외환']),
    Bank('기업', 'IBK기업은행', icon: 'ibk', aliases: ['IBK']),
    Bank('케이뱅크', '케이뱅크', icon: 'kbank', aliases: ['K뱅크', 'kbank']),
    Bank('새마을금고', '새마을금고', icon: 'kfcc', aliases: ['새마을', 'MG', 'MG새마을금고']),
    Bank('우체국', '우체국', icon: 'epost', aliases: ['우정사업본부']),
    Bank('신협', '신협', icon: 'cu', aliases: ['신용협동조합']),
    Bank('SC제일', 'SC제일은행', icon: 'sc', aliases: ['SC', '제일', '스탠다드차타드']),
    Bank('iM뱅크', 'iM뱅크', icon: 'im', aliases: ['대구', 'DGB', 'DGB대구', '아이엠뱅크']),
    Bank('부산', '부산은행', icon: 'busan', aliases: ['BNK부산']),
    Bank('경남', '경남은행', icon: 'kn', aliases: ['BNK경남']),
    // 광주은행과 전북은행은 같은 JB금융그룹 심볼을 쓴다.
    Bank('광주', '광주은행', icon: 'jb'),
    Bank('전북', '전북은행', icon: 'jb', aliases: ['JB']),
    Bank('제주', '제주은행', icon: 'jeju'),
    Bank('수협', '수협은행', icon: 'suhyup', aliases: ['Sh', 'Sh수협']),
    Bank('지역농축협', '지역농축협', icon: 'nh', aliases: ['지역농협', '단위농협', '축협']),
    Bank('씨티', '한국씨티은행', icon: 'citi', aliases: ['시티', 'citi', '한국씨티']),
    Bank('산업', 'KDB산업은행', icon: 'kdb', aliases: ['KDB']),
    Bank('산림조합', '산림조합', icon: 'nfcf'),
    Bank('저축은행', '저축은행', icon: 'fsb', aliases: ['상호저축은행']),
    Bank('HSBC', 'HSBC은행', icon: 'hsbc'),
    Bank('도이치', '도이치은행', icon: 'db', aliases: ['Deutsche']),
    Bank('JP모간', 'JP모간체이스은행', icon: 'jpm', aliases: ['JP모건', 'JPMorgan']),
    Bank('BOA', '뱅크오브아메리카', icon: 'boa', aliases: ['Bank of America']),
    Bank('중국공상', '중국공상은행', icon: 'icbc', aliases: ['ICBC']),
    Bank('중국', '중국은행', aliases: ['Bank of China']),
    Bank('중국건설', '중국건설은행', aliases: ['CCB']),
    Bank('BNP파리바', 'BNP파리바은행', icon: 'bnp', aliases: ['BNP']),
  ];

  /// 저장된(또는 예전에 직접 적은) 은행 이름에 맞는 은행. 띄어쓰기, 대소문자, "은행"은 가리지 않는다.
  static Bank? find(String text) {
    final key = _key(text);
    if (key.isEmpty) return null;
    for (final bank in all) {
      if ([bank.label, bank.name, ...bank.aliases].any((n) => _key(n) == key)) {
        return bank;
      }
    }
    return null;
  }

  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.·]'), '').replaceAll('은행', '');
}
