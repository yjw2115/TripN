import 'package:phosphor_flutter/phosphor_flutter.dart';

/// 앱 아이콘. 머티리얼 아이콘 대신 Phosphor를 쓴다. 화면에서는 이 이름만 쓴다.
///
/// - 작은 기호(화살표·더하기·체크·닫기)는 Bold: 얇은 선은 작은 크기에서 흐려 보인다.
/// - 나머지는 Regular, 고른 상태와 지출 분류는 Fill.
abstract final class AppIcons {
  // 기호
  static const chevronRight = PhosphorIconsBold.caretRight;
  static const chevronLeft = PhosphorIconsBold.caretLeft;
  static const chevronDown = PhosphorIconsBold.caretDown;
  static const arrowRight = PhosphorIconsBold.arrowRight;
  static const plus = PhosphorIconsBold.plus;
  static const minus = PhosphorIconsBold.minus;
  static const check = PhosphorIconsBold.check;
  static const close = PhosphorIconsBold.x;

  // 상태
  static const checkCircle = PhosphorIconsFill.checkCircle;
  static const checkCircleLine = PhosphorIconsRegular.checkCircle;
  static const circle = PhosphorIconsRegular.circle;
  static const radioOn = PhosphorIconsFill.radioButton;
  static const warning = PhosphorIconsRegular.warningCircle;
  static const warningFill = PhosphorIconsFill.warningCircle;
  static const info = PhosphorIconsRegular.info;
  static const infoFill = PhosphorIconsFill.info;
  static const offline = PhosphorIconsRegular.cloudSlash;
  static const hourglass = PhosphorIconsRegular.hourglass;
  static const hidden = PhosphorIconsRegular.eyeSlash;

  // 동작
  static const edit = PhosphorIconsRegular.pencilSimple;
  static const note = PhosphorIconsRegular.notePencil;
  static const trash = PhosphorIconsRegular.trash;
  static const copy = PhosphorIconsRegular.copy;
  static const share = PhosphorIconsRegular.export;
  static const send = PhosphorIconsRegular.paperPlaneTilt;
  static const undo = PhosphorIconsRegular.arrowCounterClockwise;
  static const retry = PhosphorIconsRegular.arrowClockwise;
  static const adjust = PhosphorIconsRegular.slidersHorizontal;
  static const transfer = PhosphorIconsBold.arrowsLeftRight;
  static const scan = PhosphorIconsBold.scan;

  // 사물
  static const receipt = PhosphorIconsRegular.receipt;
  static const receiptFill = PhosphorIconsFill.receipt;
  static const menu = PhosphorIconsRegular.forkKnife;
  static const menuBook = PhosphorIconsRegular.bookOpenText;
  static const album = PhosphorIconsRegular.images;
  static const image = PhosphorIconsRegular.image;
  static const trip = PhosphorIconsRegular.suitcaseRolling;
  static const tripFill = PhosphorIconsFill.suitcaseRolling;
  static const user = PhosphorIconsRegular.user;
  static const userFill = PhosphorIconsFill.user;
  static const userPlus = PhosphorIconsRegular.userPlus;
  static const users = PhosphorIconsRegular.users;
  static const bank = PhosphorIconsRegular.bank;
  static const money = PhosphorIconsRegular.money;
  static const clock = PhosphorIconsRegular.clock;
  static const calendar = PhosphorIconsRegular.calendarBlank;
  static const key = PhosphorIconsRegular.key;
  static const bell = PhosphorIconsRegular.bell;
  static const bellRinging = PhosphorIconsRegular.bellRinging;
  static const document = PhosphorIconsRegular.fileText;
  static const bag = PhosphorIconsRegular.shoppingBag;
  static const stats = PhosphorIconsRegular.chartPieSlice;
  static const statsFill = PhosphorIconsFill.chartPieSlice;
  static const chartBar = PhosphorIconsRegular.chartBar;
  static const crown = PhosphorIconsFill.crownSimple;
  static const coins = PhosphorIconsRegular.coins;

  // 지출 분류 (CategoryBadge)
  static const food = PhosphorIconsFill.forkKnife;
  static const cafe = PhosphorIconsFill.coffee;
  static const shopping = PhosphorIconsFill.shoppingBag;
  static const transport = PhosphorIconsFill.bus;
  static const lodging = PhosphorIconsFill.bed;
  static const activity = PhosphorIconsFill.ticket;
}
