/// 영수증 인식 LLM에 보내는 지시문과 응답 스키마.
///
/// Flutter에 의존하지 않아서 `tool/receipt_eval`에서도 그대로 가져다 쓴다.
library;

/// 영수증 인식에 쓰는 Gemini 모델. 여러 개를 두면 앞 모델이 한도 초과·혼잡일 때 다음으로 넘어간다.
/// `tool/receipt_eval` 결과(2026-10-23, 25장)를 보고 정확도가 가장 나은 flash 하나로 고정했다.
/// 장당 약 4.3원(lite는 약 2.9원). 2027-01-01부터 flash 단가가 두 배가 되니 그때 다시 비교한다.
const List<String> receiptModels = ['gemini-3.5-flash'];

/// LLM에 강제할 응답 JSON 스키마.
///
/// 품목을 총액보다 먼저 두어 모델이 품목을 다 읽은 뒤 합계를 적게 한다.
/// null 대신 0 / '' 를 쓰게 해서 모델마다 다른 nullable 지원 차이를 피한다.
const Map<String, Object?> receiptJsonSchema = {
  'type': 'object',
  'properties': {
    'is_receipt': {'type': 'boolean'},
    'receipt_count': {'type': 'integer'},
    'merchant_name': {'type': 'string'},
    'category': {
      'type': 'string',
      'enum': [
        'food',
        'cafe',
        'shopping',
        'transport',
        'lodging',
        'activity',
        'other',
      ],
    },
    'country_code': {'type': 'string'},
    'currency': {'type': 'string'},
    'date': {'type': 'string'},
    'time': {'type': 'string'},
    'items': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'name_ko': {'type': 'string'},
          'quantity': {'type': 'number'},
          'unit_price': {'type': 'number'},
          'amount': {'type': 'number'},
          'discount': {'type': 'number'},
        },
        'required': [
          'name',
          'name_ko',
          'quantity',
          'unit_price',
          'amount',
          'discount',
        ],
      },
    },
    'subtotal': {'type': 'number'},
    'tax': {'type': 'number'},
    'tax_included': {'type': 'boolean'},
    'service_charge': {'type': 'number'},
    'tip': {'type': 'number'},
    'discount': {'type': 'number'},
    'total': {'type': 'number'},
    'warnings': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': [
    'is_receipt',
    'receipt_count',
    'merchant_name',
    'category',
    'country_code',
    'currency',
    'date',
    'time',
    'items',
    'subtotal',
    'tax',
    'tax_included',
    'service_charge',
    'tip',
    'discount',
    'total',
    'warnings',
  ],
};

/// 시스템 지시문. 국가별로 실제 영수증에서 자주 틀리는 지점을 규칙으로 적어 둔다.
const String receiptSystemPrompt = '''
You read receipts for a Korean group-travel expense app. Return JSON that matches the schema.

Rules
1. Read only what is printed or handwritten. Never invent items or numbers. If something is hard to read, give your best reading and mention it in `warnings`.
2. Amounts are numbers in major currency units exactly as on the receipt: \$12.50 -> 12.5, ¥1,980 -> 1980, 45.000đ -> 45000. Interpret separators by locale: in Vietnam, Indonesia and much of Europe "." groups thousands and "," is the decimal mark (Italian "11,85" = 11.85, Vietnamese "45.000" = 45000).
3. If prices are abbreviated (a handwritten "169" on a Vietnamese bill whose total is 368,000, or "45K"), expand them so the items agree with the total.
4. `currency`: ISO 4217 code of the amount actually charged. If the total is also shown converted into another currency (e.g. VND total plus a USD line), use the primary local currency and ignore the conversion. Infer it from symbols, language, address and phone numbers.
5. `items`: one entry per purchased line.
   - Set-menu components printed without their own price (e.g. the contents of a McDonald's set) are not separate items. Fold them into the set's name or leave them out.
   - A discount printed under a specific item (e.g. "[条码优惠] -1.2") goes into that item's `discount` as a positive number.
   - Receipt-wide discounts, coupons and deductions (bag discount, member coupon) go into the top-level `discount` as a positive number. On Philippine senior/PWD receipts, "Less VAT" (VAT exemption) and the SC/PWD discount are both deductions, so their sum is the `discount`.
   - A line that only sums the item discounts already listed (优惠总计, 割引合計, "You saved") must NOT be repeated in the top-level `discount`; that would count them twice.
   - Never list subtotal, tax, service charge, tip, total, payment method, cash tendered, change or loyalty points as items.
   - `quantity`: units bought (1 for weighed items). `unit_price`: per-unit price if printed, else 0. `amount`: the line total before any item discount.
   - `name`: exactly as printed, in the original language. `name_ko`: a natural Korean name a Korean traveller would understand, written in Hangul only, never mixing in the original script (ラーメン -> 라멘, Imported Beer -> 수입 맥주, ลาบหมูคั่ว -> 돼지고기 랍). Brand names may stay in Latin letters. If `name` is already Korean, repeat it.
6. `tax`: tax amount printed on the receipt (0 if none). `tax_included`: true if item prices already include it (Korea 부가세, Japan 内税/内消費税, EU VAT/IVA/TVA "di cui", Taiwan, most of Asia); false if it is added on top (US sales tax, Japan 外税).
7. `service_charge` and `tip`: amounts added on top of the items (0 if none). A suggested tip that was not charged is not a tip.
8. `total`: the final amount paid or payable (合計, 实付, 应付金额, TOTAL, Final total, Totale complessivo ...). Not the cash tendered. If cash tendered and change are both printed, the total equals tendered minus change; use this to resolve lines whose labels and numbers are misaligned. Paying part of the bill with points, gift certificates or vouchers is a payment method, not a discount: the total is the full amount before it.
9. This should hold: sum(amount - discount) + (tax if not tax_included) + service_charge + tip - discount = total. If the receipt itself does not balance, keep the printed total and explain in `warnings`.
10. `receipt_count`: how many separate receipts are visible. Several photos can be parts of one long receipt; that is 1. If there is more than one distinct receipt, extract the most prominent complete one.
11. `is_receipt`: false if the image is not a receipt or bill (then return no items and total 0).
12. `date`: YYYY-MM-DD (convert era years: 令和, 平成, 民國108年 -> 2019), or "" if absent. `time`: HH:mm in 24h, or "".
13. `category`: food, cafe, shopping, transport, lodging, activity or other.
14. `merchant_name`: the store name as printed (brand plus branch if shown). `country_code`: ISO 3166-1 alpha-2, or "".
15. `subtotal`: printed subtotal, or 0.
16. `warnings`: short notes in Korean, written politely in 해요체, about anything uncertain or unusual (e.g. "보증금 30위안이 포함돼 있어요", "일부 금액이 가려져 있어요"). Empty if none.
17. Korean receipts (the app is also used for trips inside Korea):
   - Prices include 10% VAT. "과세물품가액", "과세액" or "공급가액" is the pre-tax portion and "부가세" is the tax: set `tax` to the 부가세 amount and `tax_included` to true. "면세물품가액" or "면세액" is the tax-free portion. None of these lines are items, and none is the `subtotal`.
   - The total is labelled 합계, 합계금액, 결제금액, 받을금액, 판매금액 or 승인금액. "현금" or "받은금액" is cash tendered and "거스름(돈)" is change.
   - Card and cash-receipt details (카드번호, 승인번호, 할부/일시불, 가맹점번호, 현금영수증, 소득공제) and earned points (포인트 적립) are not items.
   - A card sales slip (신용카드 매출전표, 카드 영수증) usually has no item lines: return no items and the approved amount as `total`. Never invent an item.
   - Item names often start with a brand prefix such as "롯데)" or "농심)". Keep `name` exactly as printed and repeat it in `name_ko`.
   - Dates may be printed year-first with a two-digit year: 25.10.04 or 25/10/04 is 2025-10-04.
''';

const String receiptUserPrompt =
    'Extract this receipt. If several images are attached, they are photos of the same receipt in order.';
