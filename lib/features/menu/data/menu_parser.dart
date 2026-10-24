import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../receipt/data/receipt_parser.dart';
import '../domain/menu_extraction.dart';
import 'menu_prompt.dart';

/// 메뉴판 인식기. 사진은 영수증과 같은 형태로 받는다 ([ReceiptImage]).
abstract interface class MenuParser {
  Future<MenuExtraction> parse(List<ReceiptImage> images);
}

class MenuParseException implements Exception {
  const MenuParseException(this.message, {this.cause});

  /// 사용자에게 그대로 보여줄 한국어 메시지.
  final String message;
  final Object? cause;

  @override
  String toString() => 'MenuParseException: $message ($cause)';
}

/// Firebase AI Logic(Gemini)로 메뉴판을 읽는다. 설정은 영수증 인식기([GeminiReceiptParser])와 같다.
class GeminiMenuParser implements MenuParser {
  GeminiMenuParser({List<String> models = menuModels})
      : _models = [for (final m in models) (name: m, model: _create(m))];

  final List<({String name, GenerativeModel model})> _models;

  static GenerativeModel _create(String model) {
    final isGemini3 = model.startsWith('gemini-3');
    return FirebaseAI.googleAI().generativeModel(
      model: model,
      systemInstruction: Content.system(menuSystemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseJsonSchema: menuJsonSchema,
        temperature: isGemini3 ? null : 0,
        thinkingConfig: isGemini3
            ? ThinkingConfig.withThinkingLevel(ThinkingLevel.low)
            : null,
        mediaResolution: isGemini3 ? MediaResolution.high : null,
      ),
    );
  }

  @override
  Future<MenuExtraction> parse(List<ReceiptImage> images) async {
    if (images.isEmpty) throw const MenuParseException('사진이 없어요.');
    final content = [
      Content.multi([
        for (final image in images) InlineDataPart(image.mimeType, image.bytes),
        TextPart(menuUserPrompt),
      ]),
    ];

    FirebaseAIException? lastError;
    for (final (:name, :model) in _models) {
      final GenerateContentResponse response;
      try {
        // 메뉴판은 영수증보다 글자가 많아서 넉넉히 기다린다.
        response = await model
            .generateContent(content)
            .timeout(const Duration(seconds: 90));
      } on FirebaseAIException catch (e) {
        debugPrint('Gemini $name failed: $e');
        lastError = e;
        continue;
      } on Exception catch (e) {
        throw MenuParseException('네트워크 상태를 확인하고 다시 시도해 주세요.', cause: e);
      }
      return _decode(response);
    }
    throw MenuParseException(
      lastError is QuotaExceeded
          ? '오늘 쓸 수 있는 인식 횟수를 다 썼어요. 나중에 다시 시도해 주세요.'
          : '메뉴판을 읽는 서버에 연결하지 못했어요.',
      cause: lastError,
    );
  }

  MenuExtraction _decode(GenerateContentResponse response) {
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw const MenuParseException('메뉴판 내용을 읽지 못했어요. 다시 찍어 주세요.');
    }
    try {
      return MenuExtraction.fromModelJson(
          jsonDecode(text) as Map<String, Object?>);
    } on FormatException catch (e) {
      throw MenuParseException('메뉴판 내용을 해석하지 못했어요. 다시 시도해 주세요.', cause: e);
    }
  }
}
