// 실제 영수증 사진으로 Gemini 인식 정확도를 잰다.
//
//   dart run tool/receipt_eval/eval.dart                      # 기본 모델
//   dart run tool/receipt_eval/eval.dart --model gemini-3-flash-preview --only jp_,cn_aeon
//
// 앱과 같은 프롬프트·스키마·변환 코드를 쓰고, Firebase AI Logic REST 엔드포인트를
// 웹 앱 API 키로 호출한다 (앱에서 firebase_ai가 하는 것과 같은 경로).
// 사진은 Wikimedia Commons의 자유 라이선스 이미지이며 cases.json에 출처가 있다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/receipt/data/receipt_prompt.dart';
import 'package:travelen/features/receipt/domain/receipt_extraction.dart';
import 'package:travelen/features/receipt/domain/receipt_validator.dart';

const _projectId = 'travelen-468bc';
final _dir = Directory('tool/receipt_eval');

Future<void> main(List<String> args) async {
  final models = <String>[];
  String? only;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--model') models.add(args[++i]);
    if (args[i] == '--only') only = args[++i];
  }
  if (models.isEmpty) models.add(receiptModels.first);

  final apiKey = _webApiKey();
  final appCheckToken = await _exchangeAppCheckDebugToken(apiKey);
  final cases = (jsonDecode(File('${_dir.path}/cases.json').readAsStringSync())
          as List)
      .cast<Map<String, Object?>>()
      .where((c) =>
          only == null ||
          only.split(',').any((p) => (c['id'] as String).startsWith(p)))
      .toList();

  for (final model in models) {
    stdout.writeln('\n=== $model (${cases.length} receipts) ===');
    final results = <Map<String, Object?>>[];
    // 무료 요금제 분당 호출 제한을 넘지 않도록 3개씩 나눠 보낸다.
    for (var i = 0; i < cases.length; i += 3) {
      final batch = cases.skip(i).take(3);
      results.addAll(await Future.wait(batch.map((c) => _runCase(c,
          model: model, apiKey: apiKey, appCheckToken: appCheckToken))));
    }
    _printSummary(results);
    File('${_dir.path}/results_$model.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(results));
  }
}

Future<Map<String, Object?>> _runCase(
  Map<String, Object?> c, {
  required String model,
  required String apiKey,
  required String appCheckToken,
}) async {
  final id = c['id'] as String;
  final image = await _image(id, c['commonsTitle'] as String);
  final stopwatch = Stopwatch()..start();
  Map<String, Object?> raw;
  try {
    raw = await _generate(model, apiKey, appCheckToken, image);
  } catch (e) {
    return {'id': id, 'error': e.toString()};
  }
  final ms = stopwatch.elapsedMilliseconds;
  final extraction = ReceiptExtraction.fromModelJson(raw);
  final receipt = extraction.receipt;
  final check = checkReceipt(receipt);

  final expectedCount = c['receiptCount'] as int;
  final expectedTotal = c['total'] as num?;
  final expectedItems = c['items'] as int?;
  final currency = Currency.of(c['currency'] as String);
  return {
    'id': id,
    'ms': ms,
    'multiExpected': expectedCount > 1,
    'multiOk': expectedCount > 1 ? extraction.receiptCount > 1 : null,
    'currencyOk': receipt.currency.code == currency.code,
    'totalOk': expectedTotal == null
        ? null
        : receipt.totalMinor == currency.toMinor(expectedTotal),
    'itemsOk': expectedItems == null ? null : receipt.items.length == expectedItems,
    'balanced': check.totalMatches,
    'gotCurrency': receipt.currency.code,
    'gotTotal': receipt.currency.toMajor(receipt.totalMinor),
    'gotItems': receipt.items.length,
    'gotReceiptCount': extraction.receiptCount,
    'difference': receipt.currency.toMajor(check.differenceMinor),
    'warnings': extraction.warnings,
    'raw': raw,
  };
}

Future<Map<String, Object?>> _generate(
    String model, String apiKey, String appCheckToken, List<int> image) async {
  final isGemini3 = model.startsWith('gemini-3');
  final body = jsonEncode({
    'systemInstruction': {
      'parts': [
        {'text': receiptSystemPrompt},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          {
            'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(image)},
          },
          {'text': receiptUserPrompt},
        ],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseJsonSchema': receiptJsonSchema,
      if (isGemini3) ...{
        'thinkingConfig': {'thinkingLevel': 'LOW'},
        'mediaResolution': 'MEDIA_RESOLUTION_HIGH',
      } else
        'temperature': 0,
    },
  });

  final uri = Uri.https('firebasevertexai.googleapis.com',
      '/v1beta/projects/$_projectId/models/$model:generateContent');
  for (var attempt = 0;; attempt++) {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers
        ..set('x-goog-api-key', apiKey)
        ..set('X-Firebase-AppCheck', appCheckToken)
        ..contentType = ContentType.json;
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 120));
      final text = await res.transform(utf8.decoder).join();
      // 일일 한도는 기다려도 풀리지 않으니 분당 한도일 때만 다시 시도한다.
      if (res.statusCode == 429 && !text.contains('PerDay') && attempt < 4) {
        await Future<void>.delayed(Duration(seconds: 15 * (attempt + 1)));
        continue;
      }
      if (res.statusCode != 200) {
        throw HttpException('${res.statusCode}: ${text.substring(0, text.length.clamp(0, 300))}');
      }
      final json = jsonDecode(text) as Map<String, Object?>;
      final parts = ((json['candidates'] as List).first as Map)['content']['parts'] as List;
      final out = parts
          .cast<Map>()
          .where((p) => p['thought'] != true)
          .map((p) => p['text'] ?? '')
          .join();
      return jsonDecode(out) as Map<String, Object?>;
    } finally {
      client.close();
    }
  }
}

/// 이미지가 없으면 Wikimedia Commons에서 1600px 축소본을 받아 둔다.
Future<List<int>> _image(String id, String commonsTitle) async {
  final file = File('${_dir.path}/images/$id.jpg');
  if (file.existsSync()) return file.readAsBytesSync();
  final client = HttpClient()..userAgent = 'travelen-receipt-eval/0.1';
  try {
    final api = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'titles': commonsTitle,
      'prop': 'imageinfo',
      'iiprop': 'url',
      'iiurlwidth': '1600',
      'format': 'json',
    });
    final info = jsonDecode(await (await (await client.getUrl(api)).close())
        .transform(utf8.decoder)
        .join()) as Map;
    final page = (info['query']['pages'] as Map).values.first as Map;
    final ii = (page['imageinfo'] as List).first as Map;
    final url = Uri.parse((ii['thumburl'] ?? ii['url']) as String);
    final bytes = await (await (await client.getUrl(url)).close())
        .fold<List<int>>([], (a, b) => a..addAll(b));
    file
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return bytes;
  } finally {
    client.close();
  }
}

String _webApiKey() => _option('web', 'apiKey');

String _option(String platform, String field) {
  final source = File('lib/firebase_options.dart').readAsStringSync();
  final block = source.substring(source.indexOf('FirebaseOptions $platform'));
  return RegExp("$field: '([^']+)'").firstMatch(block)![1]!;
}

/// AI Logic에 App Check가 적용돼 있어서, 콘솔에 등록한 디버그 토큰을
/// App Check 토큰으로 바꿔 쓴다 (앱의 디버그 provider가 하는 것과 같다).
Future<String> _exchangeAppCheckDebugToken(String apiKey) async {
  final defines = File('dart_defines.local.json');
  if (!defines.existsSync()) {
    throw StateError('dart_defines.local.json 이 없어요. README의 실행 절을 보세요.');
  }
  final debugToken = (jsonDecode(defines.readAsStringSync())
      as Map)['APP_CHECK_DEBUG_TOKEN'] as String;
  final appId = _option('ios', 'appId');
  final projectNumber = appId.split(':')[1];
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.https(
        'firebaseappcheck.googleapis.com',
        '/v1/projects/$projectNumber/apps/$appId:exchangeDebugToken',
        {'key': apiKey}));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({'debugToken': debugToken})));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw StateError('App Check 디버그 토큰 교환 실패 (${res.statusCode}). '
          '콘솔 App Check > 앱 > iOS 앱 > 디버그 토큰 관리에 등록됐는지 확인하세요.\n$body');
    }
    return (jsonDecode(body) as Map)['token'] as String;
  } finally {
    client.close();
  }
}

void _printSummary(List<Map<String, Object?>> results) {
  String mark(Object? v) => v == null ? '  -' : (v == true ? ' OK' : ' XX');
  stdout.writeln('${'id'.padRight(26)} cur  total items bal  multi   ms  got');
  for (final r in results) {
    if (r['error'] != null) {
      stdout.writeln('${(r['id'] as String).padRight(26)} ERROR ${r['error']}');
      continue;
    }
    stdout.writeln('${(r['id'] as String).padRight(26)}'
        '${mark(r['currencyOk'])}  ${mark(r['totalOk'])}  ${mark(r['itemsOk'])}'
        ' ${mark(r['balanced'])} ${mark(r['multiOk'])} ${r['ms'].toString().padLeft(6)}'
        '  ${r['gotCurrency']} ${r['gotTotal']} (${r['gotItems']} items, diff ${r['difference']})');
  }
  int count(String key) => results.where((r) => r[key] == true).length;
  int total(String key) => results.where((r) => r[key] != null).length;
  final ok = results.where((r) => r['error'] == null).toList();
  final avgMs = ok.isEmpty
      ? 0
      : ok.map((r) => r['ms'] as int).reduce((a, b) => a + b) ~/ ok.length;
  stdout.writeln('currency ${count('currencyOk')}/${total('currencyOk')}, '
      'total ${count('totalOk')}/${total('totalOk')}, '
      'items ${count('itemsOk')}/${total('itemsOk')}, '
      'balanced ${count('balanced')}/${total('balanced')}, '
      'multi ${count('multiOk')}/${total('multiOk')}, avg ${avgMs}ms');
}
