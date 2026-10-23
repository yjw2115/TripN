import 'receipt.dart';

/// 인식 결과를 검산한 결과. 화면에서 경고 배너와 품목 표시에 쓴다.
class ReceiptCheck {
  const ReceiptCheck({
    required this.differenceMinor,
    required this.toleranceMinor,
    required this.mismatchedItemIds,
  });

  /// 총액 − (품목 + 세금 + 봉사료 + 팁 − 할인). 양수면 품목 쪽이 모자란다.
  final int differenceMinor;
  final int toleranceMinor;

  /// 수량 × 단가가 금액과 맞지 않는 품목.
  final Set<String> mismatchedItemIds;

  bool get totalMatches => differenceMinor.abs() <= toleranceMinor;

  bool get isClean => totalMatches && mismatchedItemIds.isEmpty;
}

/// 품목 합계와 총액이 맞는지 검산한다.
///
/// 반올림 오차를 고려해 줄 수만큼의 최소 단위(예: 0.01달러 × n)까지는 허용한다.
ReceiptCheck checkReceipt(Receipt receipt) {
  final tolerance = receipt.items.length + 1;
  return ReceiptCheck(
    differenceMinor: receipt.totalMinor - receipt.computedTotalMinor,
    toleranceMinor: tolerance,
    mismatchedItemIds: {
      for (final item in receipt.items)
        if (item.hasLineMismatch) item.id,
    },
  );
}
