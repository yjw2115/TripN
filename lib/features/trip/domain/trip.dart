import 'dart:math';

import '../../settlement/domain/bet.dart';

/// 여행(모임). 동행자는 [Member] 문서로 따로 두고,
/// 여기에는 이 여행에 들어온 앱 사용자 uid만 모아 둔다 (보안 규칙과 "내 여행" 조회용).
class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberUids,
    this.inviteCode,
    this.manualRates = const {},
    this.settlementBet,
  });

  final String id;
  final String name;
  final String ownerId;
  final List<String> memberUids;

  /// 처음 초대할 때 만든다. 그 전에는 없다.
  final String? inviteCode;

  /// 수출입은행에 없는 통화(동·페소 등)에 쓸, 여행에서 직접 정한 환율. 통화 코드 → 1단위당 원화.
  final Map<String, double> manualRates;

  /// 미니게임으로 정한 정산 내기. 동행자 모두 같은 결과를 본다. 없으면 원래 정산.
  final SettlementBet? settlementBet;

  factory Trip.fromMap(String id, Map<String, Object?> map) => Trip(
        id: id,
        name: map['name'] as String? ?? '',
        ownerId: map['ownerId'] as String? ?? '',
        memberUids: (map['memberUids'] as List?)?.cast<String>() ?? const [],
        inviteCode: map['inviteCode'] as String?,
        manualRates: {
          for (final e in ((map['manualRates'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        settlementBet: SettlementBet.fromMap(map['settlementBet'] as Map?),
      );
}

/// 여행의 동행자. 지출의 결제자와 품목 참여자는 이 [id]를 가리킨다.
///
/// 앱을 쓰지 않는 사람은 이름만 있고 [uid]가 없다. 나중에 그 사람이 초대 코드로
/// 들어와 자기 이름을 고르면 [uid]가 채워지고, 그동안의 기록이 그대로 이어진다.
class Member {
  const Member({required this.id, required this.name, this.uid, this.account});

  final String id;
  final String name;
  final String? uid;

  /// 정산 때 돈을 받을 계좌. 여행 멤버끼리만 보인다.
  final BankAccount? account;

  bool get isGuest => uid == null;

  /// 동그란 아바타에 넣을 첫 글자.
  String get initial =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first);

  factory Member.fromMap(String id, Map<String, Object?> map) => Member(
        id: id,
        name: map['name'] as String? ?? '',
        uid: map['uid'] as String?,
        account: BankAccount.fromMap(map['account'] as Map?),
      );
}

class BankAccount {
  const BankAccount(
      {required this.bank, required this.number, required this.holder});

  final String bank;
  final String number;
  final String holder;

  /// "카카오뱅크 3333-01-1234567 김지민"
  String get display => [bank, number, holder].where((s) => s.isNotEmpty).join(' ');

  Map<String, Object?> toMap() =>
      {'bank': bank, 'number': number, 'holder': holder};

  static BankAccount? fromMap(Map? map) {
    final number = map?['number'] as String?;
    if (number == null || number.isEmpty) return null;
    return BankAccount(
      bank: map!['bank'] as String? ?? '',
      number: number,
      holder: map['holder'] as String? ?? '',
    );
  }
}

/// 이름을 정하기 전 내 멤버 이름.
const defaultMyName = '나';

/// 초대 코드로 막 들어와서 아직 누구인지 고르기 전의 이름.
const joiningMemberName = '새 동행자';

/// 여행·동행자 이름 최대 길이. firestore.rules의 validName과 같다.
const nameMaxLength = 30;

/// 헷갈리는 글자(0·O, 1·I·L)를 뺀 31자.
const _inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const inviteCodeLength = 6;

String generateInviteCode(Random random) => String.fromCharCodes([
      for (var i = 0; i < inviteCodeLength; i++)
        _inviteAlphabet.codeUnitAt(random.nextInt(_inviteAlphabet.length)),
    ]);

/// 사람이 친 코드를 정리한다. 형식이 맞지 않으면 null.
/// 메시지에서 복사해 오면 공백·하이픈이 섞이고, 소문자로 칠 수도 있다.
String? normalizeInviteCode(String input) {
  final code = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (code.length != inviteCodeLength) return null;
  for (final unit in code.codeUnits) {
    if (!_inviteAlphabet.codeUnits.contains(unit)) return null;
  }
  return code;
}

/// 초대 링크. 앱이 있으면 Universal Link·App Link로 앱의 /join/{code}가 열리고,
/// 없거나 카카오톡처럼 앱으로 넘겨주지 않는 브라우저면 hosting/join.html이 앱을 열거나 설치를 안내한다.
const inviteLinkBase = 'https://travelen-468bc.web.app/join/';

String inviteLink(String code) => '$inviteLinkBase$code';

/// 링크가 열리지 않을 때를 위해 코드도 마지막 줄에 따로 둔다 (길게 눌러 복사하기 쉽게).
String inviteMessage(String tripName, String code) =>
    "[여행N] '$tripName'에 초대해요.\n"
    '아래 링크를 누르면 여행N 앱에서 바로 참여할 수 있어요.\n'
    '${inviteLink(code)}\n'
    '\n'
    '링크가 열리지 않으면 앱에서 [초대 코드로 참여하기]에 이 코드를 입력해 주세요.\n'
    '$code';
