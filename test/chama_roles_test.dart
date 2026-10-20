import 'package:chama360/core/constants/chama_roles.dart';
import 'package:flutter_test/flutter_test.dart';

/// The UI gates must agree with the database, or someone is shown a
/// button the server then refuses — which reads as a broken app rather
/// than a rule. These mirror is_chama_treasurer, is_chama_admin and
/// is_chama_officer in 0018.
void main() {
  test('only the treasurer may change money', () {
    expect(ChamaRole.canHandleMoney(ChamaRole.treasurer), isTrue);
    for (final r in [ChamaRole.chairperson, ChamaRole.secretary, ChamaRole.member]) {
      expect(ChamaRole.canHandleMoney(r), isFalse, reason: '$r must not move money');
    }
  });

  test('chairperson and treasurer share the roster', () {
    expect(ChamaRole.isAdmin(ChamaRole.chairperson), isTrue);
    expect(ChamaRole.isAdmin(ChamaRole.treasurer), isTrue);
    expect(ChamaRole.isAdmin(ChamaRole.secretary), isFalse);
    expect(ChamaRole.isAdmin(ChamaRole.member), isFalse);
  });

  test('every officer sees the whole chama, a member sees only themselves', () {
    for (final r in [ChamaRole.chairperson, ChamaRole.treasurer, ChamaRole.secretary]) {
      expect(ChamaRole.canViewAll(r), isTrue, reason: '$r is an officer');
    }
    expect(ChamaRole.canViewAll(ChamaRole.member), isFalse);
  });

  test('anyone who can move money can also see it', () {
    for (final r in ChamaRole.moneyHandlers) {
      expect(ChamaRole.canViewAll(r), isTrue,
          reason: 'moving money you cannot see would be absurd');
    }
  });

  test('the roster can never be left with nobody to manage it', () {
    // Both roster roles exist independently of the money role, so losing
    // the treasurer cannot strand the chama.
    expect(ChamaRole.admins.length, greaterThan(1));
    expect(ChamaRole.admins.contains(ChamaRole.chairperson), isTrue);
  });

  test('an unknown role grants nothing', () {
    expect(ChamaRole.canHandleMoney('auditor'), isFalse);
    expect(ChamaRole.isAdmin('auditor'), isFalse);
    expect(ChamaRole.canViewAll('auditor'), isFalse);
  });
}
