import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app_providers.dart';
import '../../../../core/money/currency.dart';
import '../../../../core/money/exchange_rate.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../receipt/presentation/widgets/edit_sheets.dart';
import 'trip_widgets.dart';
import '../../../../core/ui/toast.dart';

/// "54.3" 같은 원화 입력을 읽는다. 천 단위 쉼표는 무시한다.
double? parseKrwInput(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', ''));
  return value == null || value <= 0 ? null : value;
}

/// 수출입은행 고시가 없는 통화의 환율을 여행에 정한다. 동행자 모두 이 값을 쓴다.
Future<void> editManualRate(
    BuildContext context, WidgetRef ref, Currency currency) async {
  final trip = ref.read(currentTripProvider).value;
  if (trip == null) return;
  final units = rateReferenceUnits(currency);
  final current = trip.manualRates[currency.code];
  final controller = TextEditingController(
      text: current == null
          ? ''
          : NumberFormat('0.##', 'en_US').format(current * units));
  final unitLabel =
      '${NumberFormat('#,##0', 'en_US').format(units)}${currency.nameKo}';
  // krw가 null이면 지우기를 누른 것이다.
  final result = await showAppSheet<({double? krw})>(
    context,
    (context) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => SheetScaffold(
        title: '${currency.nameKo} 환율 정하기',
        primaryLabel: '저장',
        onPrimary: parseKrwInput(value.text) == null
            ? null
            : () => Navigator.pop(context, (krw: parseKrwInput(value.text))),
        secondaryLabel: current == null ? null : '지우기',
        onSecondary: () => Navigator.pop(context, (krw: null)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '수출입은행 고시 환율이 없는 통화예요. 환전한 금액이나 카드 명세서를 보고 정해 주세요. '
              '이 여행의 동행자 모두 같은 환율을 써요.',
              style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('$unitLabel =',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                    decoration:
                        const InputDecoration(hintText: '0', suffixText: '원'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  final krw = result.krw;
  final repo = ref.read(tripRepositoryProvider);
  if (krw == null) {
    reportWriteErrors(context, repo.deleteManualRate(trip.id, currency.code));
    showToast(context, '${currency.nameKo} 환율을 지웠어요. 이미 저장한 지출은 그대로예요.',
        kind: ToastKind.success);
    return;
  }
  reportWriteErrors(
      context, repo.setManualRate(trip.id, currency.code, krw / units));
}
