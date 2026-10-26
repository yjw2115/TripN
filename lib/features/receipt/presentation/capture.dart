import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../domain/receipt.dart';
import 'receipt_review_screen.dart';
import '../../../core/ui/toast.dart';

/// 문서 스캐너로 찍거나 앨범에서 골라 분석 화면으로 넘긴다.
/// 플로팅 바의 스캔 버튼과 지출 탭의 "앨범에서 불러오기"가 쓴다.
Future<void> captureReceipt(BuildContext context, WidgetRef ref,
    {required bool fromGallery}) async {
  final service = ref.read(receiptImageServiceProvider);
  try {
    final paths =
        fromGallery ? await service.pickFromGallery() : await service.scan();
    if (paths != null && context.mounted) {
      context.push('/analyze', extra: paths);
    }
  } on PlatformException catch (e) {
    debugPrint('Capture failed: $e');
    if (!context.mounted) return;
    showToast(
        context,
        fromGallery
            ? '사진을 불러오지 못했어요.'
            : '카메라를 열지 못했어요. 권한을 확인하거나 앨범에서 선택해 주세요.',
        kind: ToastKind.error);
  }
}

/// 영수증 없이 빈 지출을 직접 적는다. 이 여행에서 가장 많이 쓴 화폐로 시작한다.
void enterExpenseManually(BuildContext context, WidgetRef ref) {
  final expenses = ref.read(expensesProvider).value ?? const [];
  final counts = <Currency, int>{};
  for (final e in expenses) {
    counts[e.currency] = (counts[e.currency] ?? 0) + 1;
  }
  final currency = maxBy(counts.entries, (e) => e.value)?.key ?? Currency.krw;
  context.push('/review',
      extra: ReviewArgs(
        receipt: Receipt(
          merchantName: '',
          currency: currency,
          items: const [],
          totalMinor: 0,
          paidAt: DateTime.now(),
        ),
        source: 'manual',
      ));
}
