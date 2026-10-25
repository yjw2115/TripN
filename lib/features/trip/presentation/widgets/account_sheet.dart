import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../receipt/presentation/widgets/edit_sheets.dart';
import '../../domain/bank.dart';
import '../../domain/trip.dart';
import 'bank_picker.dart';
import 'trip_widgets.dart';

/// 정산 때 돈을 받을 계좌를 등록한다. 이름만 있는 동행자 것도 대신 넣을 수 있다.
Future<void> editAccount(
    BuildContext context, WidgetRef ref, String tripId, Member member) async {
  final result = await showAppSheet<({BankAccount? account})>(
    context,
    (context) => _AccountSheet(member: member),
  );
  if (result == null || !context.mounted) return;
  reportWriteErrors(context,
      ref.read(tripRepositoryProvider).setAccount(tripId, member.id, result.account));
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.member});

  final Member member;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  /// 고른 은행 이름. 예전에 직접 적은 이름이면 고르기 전까지 그대로 둔다.
  late String _bank = widget.member.account?.bank ?? '';
  late final _number =
      TextEditingController(text: widget.member.account?.number);
  late final _holder = TextEditingController(
      text: widget.member.account?.holder ?? widget.member.name);

  @override
  void dispose() {
    for (final c in [_number, _holder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBank() async {
    final picked = await showBankPicker(context, selected: _bank);
    if (picked != null) setState(() => _bank = picked);
  }

  Widget _field(String label, TextEditingController controller,
          {String hint = '',
          TextInputType? keyboard,
          List<TextInputFormatter>? formatters,
          bool autofocus = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              autofocus: autofocus,
              keyboardType: keyboard,
              inputFormatters: formatters,
              decoration: InputDecoration(hintText: hint),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final number = _number.text.trim();
    return SheetScaffold(
      title: '${widget.member.name}님 계좌',
      primaryLabel: '저장',
      onPrimary: number.isEmpty
          ? null
          : () => Navigator.pop(context, (
                account: BankAccount(
                  bank: _bank.trim(),
                  number: number,
                  holder: _holder.text.trim(),
                ),
              )),
      secondaryLabel: widget.member.account == null ? null : '지우기',
      onSecondary: () => Navigator.pop(context, (account: null)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              '정산할 때 보낼 사람이 복사해서 송금 앱에 붙여 넣어요. 이 여행의 동행자에게만 보여요.',
              style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.4),
            ),
          ),
          _BankField(bank: _bank, onTap: _pickBank),
          _field('계좌번호', _number,
              hint: '예) 3333-01-1234567',
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))]),
          _field('예금주', _holder),
        ],
      ),
    );
  }
}

/// 은행 칸. 누르면 은행 목록에서 고른다.
class _BankField extends StatelessWidget {
  const _BankField({required this.bank, required this.onTap});

  final String bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final known = Bank.find(bank);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('은행',
              style: TextStyle(fontSize: 13, color: AppColors.textHint)),
          const SizedBox(height: 6),
          Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    if (bank.isNotEmpty) ...[
                      BankIcon(bank, size: 32),
                      const SizedBox(width: 10),
                    ] else
                      const SizedBox(width: 4, height: 32),
                    Expanded(
                      child: Text(
                        bank.isEmpty ? '은행 선택' : (known?.name ?? bank),
                        style: TextStyle(
                            fontSize: 16,
                            color: bank.isEmpty
                                ? AppColors.textHint
                                : AppColors.text),
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded,
                        color: AppColors.textSub),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
