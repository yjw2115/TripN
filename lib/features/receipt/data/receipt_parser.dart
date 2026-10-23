import 'dart:typed_data';

import '../domain/receipt_extraction.dart';

/// 영수증 사진 한 장 (긴 영수증은 여러 장으로 나눠 찍을 수 있다).
class ReceiptImage {
  const ReceiptImage(this.bytes, {this.mimeType = 'image/jpeg'});

  final Uint8List bytes;
  final String mimeType;
}

/// 영수증 인식기. 지금은 Gemini를 쓰고, 나중에 온디바이스 OCR 구현으로 바꿔 끼운다.
abstract interface class ReceiptParser {
  Future<ReceiptExtraction> parse(List<ReceiptImage> images);
}

class ReceiptParseException implements Exception {
  const ReceiptParseException(this.message, {this.cause});

  /// 사용자에게 그대로 보여줄 한국어 메시지.
  final String message;
  final Object? cause;

  @override
  String toString() => 'ReceiptParseException: $message ($cause)';
}
