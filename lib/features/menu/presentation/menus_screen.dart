import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/menu.dart';

/// 메뉴판으로 주문하기의 첫 화면. 이 여행에서 찍은 가게별 메뉴판과 새로 찍기.
class MenusScreen extends ConsumerWidget {
  const MenusScreen({super.key});

  Future<void> _capture(BuildContext context, WidgetRef ref,
      {required bool fromGallery}) async {
    final service = ref.read(receiptImageServiceProvider);
    try {
      final paths =
          fromGallery ? await service.pickFromGallery() : await service.scan();
      if (paths != null && context.mounted) {
        context.push('/menu-analyze', extra: paths);
      }
    } on PlatformException catch (e) {
      debugPrint('Menu capture failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(fromGallery
              ? '사진을 불러오지 못했어요.'
              : '카메라를 열지 못했어요. 권한을 확인하거나 앨범에서 선택해 주세요.')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Menu menu) async {
    final confirmed = await confirmDialog(context,
        title: '메뉴판을 지울까요?',
        body: '${menu.storeName.isEmpty ? '이 메뉴판' : menu.storeName}을 목록에서 지워요. 이미 기록한 지출은 그대로예요.',
        confirmLabel: '지우기',
        destructive: true);
    if (!confirmed || !context.mounted) return;
    final tripId = ref.read(currentTripProvider).value?.id;
    if (tripId == null) return;
    reportWriteErrors(
        context, ref.read(menuRepositoryProvider).delete(tripId, menu.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menus = ref.watch(menusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('메뉴판으로 주문')),
      body: switch (menus) {
        AsyncValue(value: final list?) when list.isNotEmpty => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('이 여행에서 찍은 메뉴판',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSub)),
              ),
              for (final menu in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MenuCard(
                    menu: menu,
                    onTap: () => context.push('/menu/${menu.id}', extra: menu),
                    onLongPress: () => _delete(context, ref, menu),
                  ),
                ),
            ],
          ),
        AsyncValue(value: _?) => const _EmptyView(),
        AsyncValue(hasError: true) => const Center(
            child: Text('메뉴판을 불러오지 못했어요',
                style: TextStyle(color: AppColors.textHint))),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => _capture(context, ref, fromGallery: false),
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('메뉴판 찍기'),
              ),
              TextButton(
                onPressed: () => _capture(context, ref, fromGallery: true),
                child: const Text('앨범에서 불러오기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard(
      {required this.menu, required this.onTap, required this.onLongPress});

  final Menu menu;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
              color: AppColors.primaryLight, shape: BoxShape.circle),
          child: const Icon(Icons.restaurant_menu_rounded,
              color: AppColors.primaryDeep),
        ),
        title: Text(menu.storeName.isEmpty ? '이름 없는 가게' : menu.storeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Text(
            '메뉴 ${menu.items.length}개 · ${menu.currency.nameKo} ${menu.currency.code}',
            style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textHint),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.restaurant_menu_rounded,
                  size: 44, color: AppColors.primaryDeep),
            ),
            const SizedBox(height: 20),
            const Text('메뉴판을 찍어 보세요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              '메뉴를 한국어로 바꿔 보여 주고,\n고른 메뉴의 합계를 미리 계산해 드려요.\n영수증이 없어도 그대로 기록할 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.textHint, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
