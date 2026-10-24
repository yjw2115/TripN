/// 메뉴판 인식 LLM에 보내는 지시문과 응답 스키마.
///
/// Flutter에 의존하지 않아서 `tool/menu_eval`에서도 그대로 가져다 쓴다.
library;

/// 영수증과 같은 모델을 쓴다 (`receiptModels`).
const List<String> menuModels = ['gemini-3.5-flash'];

/// 세금 표기. 메뉴판에 아무 말이 없으면 unknown이고, 앱이 나라에 맞춰 정한다.
const menuTaxStates = ['included', 'excluded', 'unknown'];

const Map<String, Object?> menuJsonSchema = {
  'type': 'object',
  'properties': {
    'is_menu': {'type': 'boolean'},
    'store_name': {'type': 'string'},
    'country_code': {'type': 'string'},
    'currency': {'type': 'string'},
    'tax': {
      'type': 'string',
      'enum': menuTaxStates,
    },
    'tax_rate_percent': {'type': 'number'},
    'service_charge_percent': {'type': 'number'},
    'sections': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'name_ko': {'type': 'string'},
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'name_ko': {'type': 'string'},
                'description_ko': {'type': 'string'},
                'price': {'type': 'number'},
              },
              'required': ['name', 'name_ko', 'description_ko', 'price'],
            },
          },
        },
        'required': ['name', 'name_ko', 'items'],
      },
    },
    'warnings': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': [
    'is_menu',
    'store_name',
    'country_code',
    'currency',
    'tax',
    'tax_rate_percent',
    'service_charge_percent',
    'sections',
    'warnings',
  ],
};

const String menuSystemPrompt = '''
You read restaurant and cafe menus for a Korean travel app. Travellers photograph a menu abroad, read it in Korean, pick dishes, and see the expected bill before paying. Return JSON that matches the schema.

Rules
1. Read only dishes and prices that are on the menu. Never invent dishes or prices. If something is hard to read, give your best reading and mention it in `warnings`.
2. `price` is a number in major currency units exactly as printed: \$12.50 -> 12.5, ¥1,280 -> 1280, 45.000đ -> 45000, "45K" -> 45000, "120.-" -> 120. Interpret separators by locale (in Vietnam, Indonesia and much of Europe "." groups thousands and "," is the decimal mark).
3. Keep the menu's order. Group dishes into `sections` as the menu does (e.g. Ramen, Sides, Drinks). If the menu has no sections, use one section with name "".
4. One entry per orderable choice:
   - If a dish has several prices (sizes S/M/L, hot/iced, glass/bottle, 1 piece/3 pieces, or a range like "600-800-1,000" for portion sizes), make one item per price and put the choice in both names: "Latte (Iced)", `name_ko` "카페라테 (아이스)"; for an unlabelled range use 소/중/대 in `name_ko`. Never collapse several prices into the lowest one.
   - Set meals and courses are one item at the set price; do not list their contents as separate items.
   - Add-ons and toppings with their own price ("+100 extra egg", "Add cheese \$2") are items too, in a section named for them (name_ko "추가 옵션"), with `name_ko` like "계란 추가".
   - If the price is not given (market price, 時価, "MP", ask staff), use 0 and say so in `warnings`.
   - If both a pre-tax and a tax-included price are printed (¥1,280 (税込¥1,408)), use the tax-included price and set `tax` to "included".
5. `name`: exactly as printed, in the original language. `name_ko`: a natural Korean name a Korean traveller would understand, in Hangul only (ラーメン -> 라멘, Pad Kra Pao Moo -> 돼지고기 팟끄라파오, Bánh mì thịt -> 반미 (고기)). Every word must be translated or transliterated into Hangul: never leave Thai, Japanese kana, Chinese characters or other scripts in `name_ko` (ต้มยำแห้ง -> 드라이 똠얌, ไข่เจียวปู -> 게살 오믈렛). Brand names may stay in Latin letters. If `name` is already Korean, repeat it.
6. `description_ko`: one short Korean line (under 30 characters, 해요체 not needed) that tells a Korean what the dish is: main ingredients, style, spiciness. Use the menu's own description when there is one; otherwise use general knowledge of the dish. Use "" for obvious things (콜라, 물) and for add-ons.
7. Section `name`: as printed; section `name_ko`: Korean.
8. `currency`: ISO 4217 code of the menu prices. Infer from symbols, language, address and the country. `country_code`: ISO 3166-1 alpha-2 of the restaurant, or "".
9. `tax`: "included" if the prices already include tax (税込, "prices include VAT", 부가세 포함, and by default in Korea, Japan when unmarked, Taiwan, Hong Kong, China, Europe, Australia); "excluded" if tax is added at the bill (税抜, 本体価格, "+tax", "prices exclude VAT", "++", "subject to VAT", and by default in the US and Canada); "unknown" if you cannot tell. `tax_rate_percent`: the rate if printed or standard for the place and you are sure (Japan 10, Thailand 7, Vietnam 8 or 10 as printed, Singapore 9), else 0. US and Canadian sales tax depends on the city: use 0 unless printed.
10. `service_charge_percent`: the service charge added to the bill only if it is printed on this menu ("10% service charge", "另加一成服務費", "++" in Thailand/Singapore/Malaysia means 10% service plus tax), else 0. Do not add one from general knowledge of the restaurant or country; if you believe one is usual there, say so in `warnings` instead. A suggested tip is not a service charge.
11. `store_name`: the restaurant name if shown (brand plus branch), else "".
12. `is_menu`: false if the image is not a menu or price list (then return no sections). A drinks board, a price list on a wall or a food-stall sign counts as a menu.
13. `warnings`: short notes in Korean, ending every sentence in 해요체 (-요, never -습니다), about anything uncertain or useful before paying (e.g. "일부 가격이 가려져 있어요", "자릿세가 따로 붙는다고 적혀 있어요"). Empty if none.
14. Korean menus (the app is also used for trips inside Korea):
   - `currency` KRW, `country_code` KR, `tax` "included" (메뉴 가격은 부가세 포함).
   - Prices are often abbreviated: cafes write 4.5 or 4,5 for 4,500원, restaurants write 12, 12.0 or 12천 for 12,000원. Expand them to full won; a price under 100 on a Korean menu is in thousands of won.
   - 싯가/시가 (market price) -> 0 with a warning.
   - `name_ko` repeats `name`. `description_ko` is "" unless the dish is unusual or regional enough that many Koreans would not know it.
   - 1인분/2인분, 소/중/대, 한 마리/반 마리 are separate items. Notes like "2인분 이상 주문 가능" or "공기밥 별도" go into `warnings`.
''';

const String menuUserPrompt =
    'Read this menu. If several images are attached, they are pages of the same menu in order.';
