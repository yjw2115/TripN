import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../domain/receipt_extraction.dart';
import 'receipt_parser.dart';
import 'receipt_prompt.dart';

/// Firebase AI Logic(Gemini Developer API)로 영수증을 읽는다.
///
/// API 키는 앱에 들어가지 않고 Firebase 프로젝트 설정과 App Check로 보호된다.
/// 앞 모델이 한도 초과나 혼잡으로 실패하면 [models]의 다음 모델로 다시 시도한다.
class GeminiReceiptParser implements ReceiptParser {
  GeminiReceiptParser({List<String> models = receiptModels})
      : _models = [for (final m in models) (name: m, model: _create(m))];

  final List<({String name, GenerativeModel model})> _models;

  static GenerativeModel _create(String model) =>
      FirebaseAI.googleAI().generativeModel(
        model: model,
        systemInstruction: Content.system(receiptSystemPrompt),
        generationConfig: _configFor(model),
      );

  /// `tool/receipt_eval/eval.dart`의 REST 요청과 같은 설정을 유지한다.
  static GenerationConfig _configFor(String model) {
    final isGemini3 = model.startsWith('gemini-3');
    return GenerationConfig(
      responseMimeType: 'application/json',
      responseJsonSchema: receiptJsonSchema,
      // Gemini 3는 기본 temperature(1.0)를 권장한다.
      temperature: isGemini3 ? null : 0,
      thinkingConfig: isGemini3
          ? ThinkingConfig.withThinkingLevel(ThinkingLevel.low)
          : null,
      mediaResolution: isGemini3 ? MediaResolution.high : null,
    );
  }

  @override
  Future<ReceiptExtraction> parse(List<ReceiptImage> images) async {
    if (images.isEmpty) {
      throw const ReceiptParseException('사진이 없어요.');
    }
    final content = [
      Content.multi([
        for (final image in images) InlineDataPart(image.mimeType, image.bytes),
        TextPart(receiptUserPrompt),
      ]),
    ];

    FirebaseAIException? lastError;
    for (final (:name, :model) in _models) {
      final GenerateContentResponse response;
      try {
        response = await model
            .generateContent(content)
            .timeout(const Duration(seconds: 60));
      } on FirebaseAIException catch (e) {
        // 한도 초과, 혼잡, 모델 종료 등은 다음 모델로 넘어간다.
        debugPrint('Gemini $name failed: $e');
        lastError = e;
        continue;
      } on Exception catch (e) {
        throw ReceiptParseException('네트워크 상태를 확인하고 다시 시도해 주세요.', cause: e);
      }
      return _decode(response);
    }
    throw ReceiptParseException(
      lastError is QuotaExceeded
          ? '오늘 쓸 수 있는 인식 횟수를 다 썼어요. 직접 입력하거나 나중에 다시 시도해 주세요.'
          : '영수증을 읽는 서버에 연결하지 못했어요.',
      cause: lastError,
    );
  }

  ReceiptExtraction _decode(GenerateContentResponse response) {
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw const ReceiptParseException('영수증 내용을 읽지 못했어요. 다시 찍어 주세요.');
    }
    try {
      final json = jsonDecode(text) as Map<String, Object?>;
      return ReceiptExtraction.fromModelJson(json);
    } on FormatException catch (e) {
      throw ReceiptParseException('영수증 내용을 해석하지 못했어요. 다시 시도해 주세요.', cause: e);
    }
  }
}
