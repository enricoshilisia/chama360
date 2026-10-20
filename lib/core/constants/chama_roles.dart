/// Mirrors the `role` check constraint on chama_members in the DB
/// (supabase/migrations/0001_init_schema.sql). Keep these in sync.
class ChamaRole {
  ChamaRole._();

  static const chairperson = 'chairperson';
  static const treasurer = 'treasurer';
  static const secretary = 'secretary';
  static const member = 'member';

  /// Who may manage the roster: members, logins, roles, archiving.
  /// Two people on purpose, so a chama can always appoint a new
  /// treasurer and can never lock itself out of its own books.
  static const admins = {chairperson, treasurer};

  /// Who may change money: contributions, loans, repayments, reversals,
  /// transfers, imports. One person, and the database agrees — see
  /// is_chama_treasurer() in 0018.
  static const moneyHandlers = {treasurer};

  /// Who may see the whole chama's figures, read-only. The secretary
  /// keeps the register in most chamas and could previously see no more
  /// than an ordinary member.
  static const officers = {chairperson, treasurer, secretary};

  static bool isAdmin(String role) => admins.contains(role);

  /// Gate every button that writes money on this, never on [isAdmin].
  /// A chairperson shown a "Record contribution" button the server then
  /// refuses looks like a broken app rather than a rule.
  static bool canHandleMoney(String role) => moneyHandlers.contains(role);

  /// Gate the full register, the reports and the loan book on this.
  static bool canViewAll(String role) => officers.contains(role);

  static String label(String role) {
    switch (role) {
      case chairperson:
        return 'Chairperson';
      case treasurer:
        return 'Treasurer';
      case secretary:
        return 'Secretary';
      default:
        return 'Member';
    }
  }
}
