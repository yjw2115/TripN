import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/theme/app_theme.dart';
import '../data/receipt_parser.dart';
import '../domain/receipt.dart';
import 'receipt_review_screen.dart';

/// 사진을 Gemini로 보내고 결과가 오면 확인 화면으로 넘어간다.
class ReceiptAnalyzeScreen extends ConsumerStatefulWidget {
  const ReceiptAnalyzeScreen({super.key, required this.imagePaths});

  final List<String> imagePaths;

  @override
  ConsumerState<ReceiptAnalyzeScreen> createState() =>
      _ReceiptAnalyzeScreenState();
}

class _ReceiptAnalyzeScreenState extends ConsumerState<ReceiptAnalyzeScreen>
    with SingleTickerProviderStateMixin {
  late final _scanLine = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  String? _error;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _scanLine.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() => _error = null);
    try {
      final images =
          await ref.read(receiptImageServiceProvider).prepare(widget.imagePaths);
      final result = await ref.read(receiptParserProvider).parse(images);
      if (!mounted) return;
      if (!result.isReceipt) {
        setState(() => _error = '영수증이 아닌 것 같아요. 영수증이 화면에 꽉 차게 다시 찍어 주세요.');
        return;
      }
      context.pushReplacement('/review',
          extra: ReviewArgs(
            receipt: result.receipt,
            warnings: result.warnings,
            receiptCount: result.receiptCount,
            imagePaths: widget.imagePaths,
          ));
    } on ReceiptParseException catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Receipt analyze failed: $e');
      if (mounted) setState(() => _error = '알 수 없는 문제가 생겼어요. 다시 시도해 주세요.');
    }
  }

  void _enterManually() {
    context.pushReplacement('/review',
        extra: ReviewArgs(
          receipt: Receipt(
            merchantName: '',
            currency: Currency.krw,
            items: const [],
            totalMinor: 0,
            paidAt: DateTime.now(),
          ),
          imagePaths: widget.imagePaths,
        ));
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
              _ReceiptPreview(
                  path: widget.imagePaths.first,
                  scanLine: error == null ? _scanLine : null),
              const SizedBox(height: 32),
              Text(
                error == null ? '영수증을 읽고 있어요' : '영수증을 읽지 못했어요',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                error == null
                    ? '품목과 금액을 정리하는 중이에요. 보통 10초 안에 끝나요.'
                    : '$error\n직접 입력할 수도 있어요.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.textHint),
              ),
              const Spacer(flex: 2),
              if (error != null) ...[
                FilledButton(onPressed: _analyze, child: const Text('다시 시도')),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: _enterManually, child: const Text('직접 입력하기')),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.path, required this.scanLine});

  final String path;
  final Animation<double>? scanLine;

  @override
  Widget build(BuildContext context) {
    const height = 280.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 210,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(path), fit: BoxFit.cover),
            if (scanLine != null)
              AnimatedBuilder(
                animation: scanLine!,
                builder: (context, _) => Align(
                  alignment: Alignment(0, scanLine!.value * 2 - 1),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.6),
                          blurRadius: 16,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
