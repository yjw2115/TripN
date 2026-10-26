import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../data/menu_parser.dart';
import 'menu_screen.dart';
import '../../../core/ui/controls.dart';

/// 메뉴판 사진을 Gemini로 보내고, 읽으면 여행에 저장한 뒤 메뉴 고르기로 넘어간다.
class MenuAnalyzeScreen extends ConsumerStatefulWidget {
  const MenuAnalyzeScreen({super.key, required this.imagePaths});

  final List<String> imagePaths;

  @override
  ConsumerState<MenuAnalyzeScreen> createState() => _MenuAnalyzeScreenState();
}

class _MenuAnalyzeScreenState extends ConsumerState<MenuAnalyzeScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() => _error = null);
    try {
      final images =
          await ref.read(receiptImageServiceProvider).prepare(widget.imagePaths);
      final result = await ref.read(menuParserProvider).parse(images);
      if (!mounted) return;
      if (!result.isMenu || result.menu.items.isEmpty) {
        setState(() => _error = result.isMenu
            ? '메뉴와 가격을 찾지 못했어요. 메뉴가 잘 보이게 다시 찍어 주세요.'
            : '메뉴판이 아닌 것 같아요. 메뉴판이 화면에 꽉 차게 다시 찍어 주세요.');
        return;
      }
      final user = await ref.read(currentUserProvider.future);
      final trip = await ref.read(currentTripProvider.future);
      if (!mounted) return;
      final repo = ref.read(menuRepositoryProvider);
      final menu = result.menu.copyWithId(repo.newId(trip.id));
      // 저장은 기다리지 않는다. 기기에 먼저 반영되니 메뉴 화면은 바로 보인다.
      reportWriteErrors(context, repo.create(trip.id, menu, uid: user.uid));
      context.pushReplacement('/menu/${menu.id}',
          extra: MenuScreenArgs(menu: menu, warnings: result.warnings));
    } on MenuParseException catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Menu analyze failed: $e');
      if (mounted) setState(() => _error = '알 수 없는 문제가 생겼어요. 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 210,
                  height: 280,
                  child: Image.file(File(widget.imagePaths.first),
                      fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 32),
              if (error == null) ...[
                const SizedBox(
                    width: 28,
                    height: 28,
                    child: AppSpinner(radius: 14)),
                const SizedBox(height: 20),
              ],
              Text(
                error == null ? '메뉴판을 읽고 있어요' : '메뉴판을 읽지 못했어요',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                error ?? '메뉴를 한국어로 바꾸고 가격을 정리하는 중이에요. 메뉴가 많으면 20초쯤 걸려요.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.textHint),
              ),
              const Spacer(flex: 2),
              if (error != null) ...[
                FilledButton(onPressed: _analyze, child: const Text('다시 시도')),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: () => context.pop(), child: const Text('다시 찍기')),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
