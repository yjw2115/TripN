import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'receipt_parser.dart';

/// 영수증 사진을 얻고(문서 스캐너 / 앨범) 업로드하기 좋은 크기로 줄인다.
///
/// 테두리 검출과 원근 보정은 OS 문서 스캐너가 한다
/// (Android: ML Kit Document Scanner, iOS: VisionKit).
class ReceiptImageService {
  /// 긴 영수증은 여러 장으로 나눠 찍을 수 있게 한다.
  static const maxPages = 3;

  /// 짧은 변 기준 이 정도면 작은 글씨도 충분히 읽힌다.
  static const _targetShortSide = 1600;

  /// 문서 스캐너를 연다. 사용자가 취소하면 null.
  Future<List<String>?> scan() async {
    final result = await FlutterDocScanner().getScannedDocumentAsImages(
      page: maxPages,
      imageFormat: ImageFormat.jpeg,
      quality: 0.9,
    );
    final paths = result?.images.map(_toFilePath).toList();
    return (paths == null || paths.isEmpty) ? null : paths;
  }

  /// 앨범에서 고른다. 스캐너를 거치지 않으므로 원근 보정은 되지 않는다.
  Future<List<String>?> pickFromGallery() async {
    final files = await ImagePicker().pickMultiImage(limit: maxPages);
    return files.isEmpty ? null : files.map((f) => f.path).toList();
  }

  Future<List<ReceiptImage>> prepare(List<String> paths) =>
      Future.wait(paths.map(_prepareOne));

  Future<ReceiptImage> _prepareOne(String path) async {
    try {
      final bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: _targetShortSide,
        minHeight: _targetShortSide,
        quality: 85,
      );
      if (bytes != null && bytes.isNotEmpty) return ReceiptImage(bytes);
    } catch (e) {
      debugPrint('Image compression failed, sending original: $e');
    }
    return ReceiptImage(await File(path).readAsBytes());
  }

  static String _toFilePath(String uriOrPath) {
    final uri = Uri.tryParse(uriOrPath);
    return (uri != null && uri.scheme == 'file') ? uri.toFilePath() : uriOrPath;
  }
}
