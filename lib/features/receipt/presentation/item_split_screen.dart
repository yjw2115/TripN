import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../settlement/domain/settlement.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/receipt.dart';
import 'widgets/count_stepper.dart';

/// 품목을 누가 가져갔고 나머지를 누가 함께 나누는지: "지민 2 · 민수 1 · 나머지 2개 함께".
/// 아무도 고르지 않았고 모두 함께 나누면 빈 문자열. [names]는 멤버 id → 이름 (보여줄 순서대로).
String splitSummary(ReceiptItem item, Map<String, String> names) {
  final sharers = [
    for (final e in names.entries)
      if (item.participantIds.contains(e.key)) e.value,
  ].join('·');
  if (item.takenBy.isEmpty) return sharers;
  final parts = [
    for (final e in names.entries)
      if (item.takenBy[e.key] case final n?)
        item.units == 1 ? e.value : '${e.value} $n',
  ];
  final shared = item.sharedUnits;
  if (shared > 0) {
    parts.add('나머지 $shared개 ${sharers.isEmpty ? '' : '$sharers '}함께');
  }
  return parts.join(' · ');
}

/// 한 번에 결제하고 각자 가져간 것을 고른다. 멤버를 고르고 그 사람이 산 품목과 개수를 담는다.
/// 아무도 고르지 않은 개수는 함께 나눈다. 바꿀 때마다 [onChanged]로 알려서 뒤로 가도 남는다.
class ItemSplitScreen extends StatefulWidget {
  const ItemSplitScreen({
    super.key,
    required this.receipt,
    required this.members,
    required this.onChanged,
    this.payerId,
    this.myId,
  });

  final Receipt receipt;

  /// 이 지출을 함께 쓴 멤버. 두 명 이상이다.
  final List<Member> members;
  final ValueChanged<List<ReceiptItem>> onChanged;

  /// 나누고 남는 자투리를 먼저 받는 결제자 (정산과 같게).
  final String? payerId;

  /// 내 멤버 id. 나부터 고른다.
  final String? myId;

  @override
  State<ItemSplitScreen> createState() => _ItemSplitScreenState();
}

class _ItemSplitScreenState extends State<ItemSplitScreen> {
  late List<ReceiptItem> _items = widget.receipt.items;
  late String _memberId = widget.members.any((m) => m.id == widget.myId)
      ? widget.myId!
      : widget.members.first.id;

  String _money(int minor) => formatMoney(minor, widget.receipt.currency);

  void _replace(ReceiptItem next) {
    final items = [for (final i in _items) i.id == next.id ? next : i];
    setState(() => _items = items);
    widget.onChanged(items);
  }

  /// 지금 고른 멤버가 [item]을 [count]개 가져간다.
  void _setCount(ReceiptItem item, int count) {
    final taken = {...item.takenBy};
    if (count > 0) {
      taken[_memberId] = count;
    } else {
      taken.remove(_memberId);
    }
    _replace(item.copyWith(takenBy: taken));
  }

  /// 한 개짜리는 눌러서 내 것으로 하고(다른 사람 것이었어도), 다시 누르면 함께 나누는 걸로 되돌린다.
  void _tap(ReceiptItem item) {
    final mine = item.takenBy[_memberId] ?? 0;
    if (item.units == 1) {
      HapticFeedback.selectionClick();
      _replace(item.copyWith(takenBy: mine > 0 ? const {} : {_memberId: 1}));
    } else if (item.sharedUnits > 0) {
      HapticFeedback.selectionClick();
      _setCount(item, mine + 1);
    }
  }

  Future<void> _reset() async {
    final confirmed = await confirmDialog(context,
        title: '처음부터 다시 고를까요?',
        body: '고른 걸 모두 지우고 모든 품목을 함께 나눠요.',
        confirmLabel: '다시 고르기');
    if (!confirmed) return;
    final items = [for (final i in _items) i.copyWith(takenBy: const {})];
    setState(() => _items = items);
    widget.onChanged(items);
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final member = members.firstWhere((m) => m.id == _memberId);
    final priority = [?widget.payerId];
    final shares = allocate(
        widget.receipt.totalMinor,
        itemWeights(_items, [for (final m in members) m.id],
            priority: priority),
        priority: priority);
    final names = {for (final m in members) m.id: m.name};
    final sharedCount = _items.where((i) => i.sharedUnits > 0).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('각자 몫 고르기'),
        actions: [
          if (_items.any((i) => i.takenBy.isNotEmpty))
            TextButton(onPressed: _reset, child: const Text('다시 고르기')),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final m in members)
                  _MemberTab(
                    member: m,
                    amount: _money(shares[m.id] ?? 0),
                    selected: m.id == _memberId,
                    onTap: () => setState(() => _memberId = m.id),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              // 이름을 아직 안 정한 나는 '나'라서 "나님"이 되지 않게 한다.
              '${member.id == widget.myId ? '내' : '${member.name}님'} 몫을 골라 주세요. '
              '아무도 고르지 않은 건 함께 나눠요.',
              style: const TextStyle(fontSize: 14, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return _SplitItemRow(
                  item: item,
                  member: member,
                  taker: members.firstWhereOrNull(
                      (m) => item.takenBy.containsKey(m.id)),
                  summary: splitSummary(item, names),
                  money: _money,
                  onTap: () => _tap(item),
                  onCount: (count) => _setCount(item, count),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sharedCount == 0
                    ? '모든 품목을 각자 골랐어요'
                    : '함께 나누는 품목 $sharedCount개',
                style: const TextStyle(fontSize: 13, color: AppColors.textHint),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('완료'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 위쪽 멤버 고르기. 지금까지 고른 걸로 계산한 그 사람 몫(세금·할인 포함)을 함께 보여준다.
class _MemberTab extends StatelessWidget {
  const _MemberTab({
    required this.member,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final Member member;
  final String amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: selected
          ? const BorderSide(color: AppColors.primaryDeep, width: 1.5)
          : BorderSide.none,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Material(
        color: selected ? AppColors.surface : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            width: 80,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MemberAvatar(member, size: 36),
                const SizedBox(height: 4),
                Text(member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(amount,
                        style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? AppColors.primaryDeep
                                : AppColors.textHint)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitItemRow extends StatelessWidget {
  const _SplitItemRow({
    required this.item,
    required this.member,
    required this.taker,
    required this.summary,
    required this.money,
    required this.onTap,
    required this.onCount,
  });

  final ReceiptItem item;

  /// 지금 고르는 멤버.
  final Member member;

  /// 한 개짜리 품목을 가져간 사람.
  final Member? taker;
  final String summary;
  final String Function(int) money;
  final VoidCallback onTap;
  final ValueChanged<int> onCount;

  @override
  Widget build(BuildContext context) {
    final mine = item.takenBy[member.id] ?? 0;
    final detail = [
      if (item.name.isNotEmpty && item.name != item.displayName) item.name,
      if (item.units > 1) '${item.units}개',
      money(item.netMinor),
    ].join(' · ');
    return Material(
      color: mine > 0 ? AppColors.primaryLight : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName.isEmpty ? '이름 없음' : item.displayName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textHint)),
                    ),
                    if (summary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(summary,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.primaryDeep)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (item.units > 1)
                CountStepper(
                  count: mine,
                  max: mine + item.sharedUnits,
                  onChanged: onCount,
                  name: member.name,
                )
              else
                IconButton(
                  tooltip: mine > 0
                      ? '${member.name} 몫에서 빼기'
                      : '${member.name} 몫으로 고르기',
                  onPressed: onTap,
                  icon: mine > 0
                      ? const Icon(Icons.check_circle_rounded,
                          size: 30, color: AppColors.primaryDeep)
                      : taker != null
                          ? MemberAvatar(taker!, size: 30)
                          : const Icon(Icons.circle_outlined,
                              size: 30, color: AppColors.textHint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
