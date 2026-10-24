import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import '../domain/menu.dart';

/// Firestore 구조
///   trips/{tripId}/menus/{menuId}   storeName, currency, countryCode, taxIncluded, taxRatePercent,
///                                   serviceChargePercent, items[{id, name, nameKo, descriptionKo,
///                                   section, priceMinor}], createdBy, createdAt, updatedAt
///
/// 찍은 메뉴판을 여행 안에 가게별로 남겨서 같은 가게에서 다시 주문할 때 다시 찍지 않게 한다.
class MenuRepository {
  MenuRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _menus(String tripId) =>
      _db.collection('trips').doc(tripId).collection('menus');

  /// 최근에 찍은 것부터.
  Stream<List<Menu>> watchMenus(String tripId) =>
      _menus(tripId).snapshots().map((s) => s.docs
          .sorted((a, b) => _compareCreatedAt(b.data(), a.data()))
          .map((d) => Menu.fromMap(d.id, d.data()))
          .toList());

  Stream<Menu?> watchMenu(String tripId, String menuId) => _menus(tripId)
      .doc(menuId)
      .snapshots()
      .map((s) => s.exists ? Menu.fromMap(s.id, s.data()!) : null);

  /// 새 메뉴판의 id. 저장을 기다리지 않고 바로 메뉴 화면으로 넘어가려고 먼저 만든다.
  String newId(String tripId) => _menus(tripId).doc().id;

  /// 쓰기는 기기에 먼저 반영되니 화면은 기다리지 않아도 된다.
  Future<void> create(String tripId, Menu menu, {required String uid}) =>
      _menus(tripId).doc(menu.id).set({
        ...menu.toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// 가게 이름, 메뉴 이름·가격, 세금·봉사료를 고친다.
  Future<void> update(String tripId, Menu menu) =>
      _menus(tripId).doc(menu.id).update({
        ...menu.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete(String tripId, String menuId) =>
      _menus(tripId).doc(menuId).delete();

  static int _compareCreatedAt(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['createdAt'] as Timestamp?;
    final tb = b['createdAt'] as Timestamp?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  }
}
