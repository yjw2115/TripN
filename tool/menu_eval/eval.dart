// 실제 메뉴판 사진으로 Gemini 메뉴판 인식을 확인한다.
//
//   dart run tool/menu_eval/eval.dart
//   dart run tool/menu_eval/eval.dart --model gemini-3.5-flash-lite --only jp_
//
// 앱과 같은 프롬프트·스키마·변환 코드를 쓰고, 호출 방식은 tool/receipt_eval/eval.dart와 같다
// (Firebase AI Logic REST + App Check 디버그 토큰). 사진은 Wikimedia Commons의 자유 라이선스 이미지다.
// 메뉴판은 정답 합계가 없어서 통화·나라·메뉴 수를 보고, 메뉴 이름과 가격은 사진과 눈으로 비교한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:travelen/core/money/money_format.dart';
import 'package:travelen/features/menu/data/menu_prompt.dart';
import 'package:travelen/features/menu/domain/menu_extraction.dart';

const _projectId = 'travelen-468bc';
final _dir = Directory('tool/menu_eval');

Future<void> main(List<String> args) async {
  var model = menuModels.first;
  String? only;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--model') model = args[++i];
    if (args[i] == '--only') only = args[++i];
  }
  final apiKey = _option('web', 'apiKey');
  final appCheckToken = await _exchangeAppCheckDebugToken(apiKey);
  final cases = (jsonDecode(File('${_dir.path}/cases.json').readAsStringSync())
          as List)
      .cast<Map<String, Object?>>()
      .where((c) =>
          only == null ||
          only.split(',').any((p) => (c['id'] as String).startsWith(p)))
      .toList();

  stdout.writeln('=== $model (${cases.length} menus) ===');
  final results = <Map<String, Object?>>[];
  for (final c in cases) {
    final id = c['id'] as String;
    try {
      final image = await _image(id, c['commonsTitle'] as String);
      final stopwatch = Stopwatch()..start();
      final (:raw, :usage) = await _generate(model, apiKey, appCheckToken, image);
      final e = MenuExtraction.fromModelJson(raw);
      final m = e.menu;
      final currencyOk = m.currency.code == c['currency'];
      final countryOk = m.countryCode == c['country'];
      stdout
        ..writeln('\n[$id] ${stopwatch.elapsedMilliseconds}ms  '
            'currency ${m.currency.code} ${currencyOk ? 'OK' : 'XX'}  '
            'country ${m.countryCode} ${countryOk ? 'OK' : 'XX'}  '
            'items ${m.items.length}  store "${m.storeName}"')
        ..writeln('  tax ${m.taxIncluded ? 'included' : 'excluded ${m.taxRatePercent}%'}'
            '  service ${m.serviceChargePercent}%  '
            'tokens in ${usage['promptTokenCount']} out ${usage['candidatesTokenCount']}');
      for (final item in m.items.take(8)) {
        stdout.writeln('  - [${item.section}] ${item.nameKo} (${item.name}) '
            '${formatMoney(item.priceMinor, m.currency)}'
            '${item.descriptionKo.isEmpty ? '' : ' · ${item.descriptionKo}'}');
      }
      if (m.items.length > 8) stdout.writeln('  … ${m.items.length - 8} more');
      for (final w in e.warnings) {
        stdout.writeln('  ! $w');
      }
      results.add({'id': id, 'currencyOk': currencyOk, 'countryOk': countryOk, 'raw': raw, 'usage': usage});
    } catch (err) {
      stdout.writeln('\n[$id] ERROR $err');
      results.add({'id': id, 'error': err.toString()});
    }
  }
  File('${_dir.path}/results_$model.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
}

Future<({Map<String, Object?> raw, Map<String, Object?> usage})> _generate(
    String model, String apiKey, String appCheckToken, List<int> image) async {
  final isGemini3 = model.startsWith('gemini-3');
  final body = jsonEncode({
    'systemInstruction': {
      'parts': [
        {'text': menuSystemPrompt},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          {
            'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(image)},
          },
          {'text': menuUserPrompt},
        ],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseJsonSchema': menuJsonSchema,
      if (isGemini3) ...{
        'thinkingConfig': {'thinkingLevel': 'LOW'},
        'mediaResolution': 'MEDIA_RESOLUTION_HIGH',
      } else
        'temperature': 0,
    },
  });
  final uri = Uri.https('firebasevertexai.googleapis.com',
      '/v1beta/projects/$_projectId/models/$model:generateContent');
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers
      ..set('x-goog-api-key', apiKey)
      ..set('X-Firebase-AppCheck', appCheckToken)
      ..contentType = ContentType.json;
    req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 180));
    final text = await res.transform(utf8.decoder).join();
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
    return (
      raw: jsonDecode(out) as Map<String, Object?>,
      usage: Map<String, Object?>.from(json['usageMetadata'] as Map? ?? {}),
    );
  } finally {
    client.close();
  }
}

/// 이미지가 없으면 Wikimedia Commons에서 1600px 축소본을 받아 둔다.
Future<List<int>> _image(String id, String commonsTitle) async {
  final file = File('${_dir.path}/images/$id.jpg');
  if (file.existsSync()) return file.readAsBytesSync();
  final client = HttpClient()..userAgent = 'travelen-menu-eval/0.1';
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

String _option(String platform, String field) {
  final source = File('lib/firebase_options.dart').readAsStringSync();
  final block = source.substring(source.indexOf('FirebaseOptions $platform'));
  return RegExp("$field: '([^']+)'").firstMatch(block)![1]!;
}

/// tool/receipt_eval/eval.dart와 같다: 콘솔에 등록한 App Check 디버그 토큰을 App Check 토큰으로 바꾼다.
Future<String> _exchangeAppCheckDebugToken(String apiKey) async {
  final debugToken = (jsonDecode(File('dart_defines.local.json').readAsStringSync())
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
      throw StateError('App Check 디버그 토큰 교환 실패 (${res.statusCode})\n$body');
    }
    return (jsonDecode(body) as Map)['token'] as String;
  } finally {
    client.close();
  }
}
