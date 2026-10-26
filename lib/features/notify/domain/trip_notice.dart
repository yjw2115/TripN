/// 푸시 알림 종류. Functions(functions/notify.js)가 data.type에 같은 이름을 넣는다.
enum NoticeType {
  /// 동행자가 지출을 기록했다.
  expense,

  /// 동행자가 정산을 요청했다.
  settleRequest,

  /// 동행자가 지출을 정산 완료로 표시했다.
  settled,

  /// MY → 알림에서 이 기기로 보낸 테스트 알림. 여행과 상관없다.
  test;

  static NoticeType? fromName(String? name) =>
      values.where((t) => t.name == name).firstOrNull;
}

/// 받은 알림. 누르면 [tripId] 여행으로 바꾸고, 정산 알림이면 정산 화면을 연다.
/// 테스트 알림은 [tripId]가 비어 있다.
class TripNotice {
  const TripNotice(
      {required this.tripId, required this.type, this.title = '', this.body = ''});

  final String tripId;
  final NoticeType type;
  final String title;
  final String body;

  bool get opensSettlement =>
      type == NoticeType.settleRequest || type == NoticeType.settled;

  /// 이 앱이 보낸 알림이 아니면(여행이나 종류가 없으면) null.
  static TripNotice? fromData(Map<String, dynamic> data,
      {String? title, String? body}) {
    final tripId = data['tripId'];
    final type = NoticeType.fromName(data['type'] as String?);
    if (type == null) return null;
    if (type != NoticeType.test && (tripId is! String || tripId.isEmpty)) {
      return null;
    }
    return TripNotice(
        tripId: tripId is String ? tripId : '',
        type: type,
        title: title ?? '',
        body: body ?? '');
  }
}
