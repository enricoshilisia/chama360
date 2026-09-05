/// Mirrors the `role` check constraint on chama_members in the DB
/// (supabase/migrations/0001_init_schema.sql). Keep these in sync.
class ChamaRole {
  ChamaRole._();

  static const chairperson = 'chairperson';
  static const treasurer = 'treasurer';
  static const secretary = 'secretary';
  static const member = 'member';

  static const admins = {chairperson, treasurer};

  static bool isAdmin(String role) => admins.contains(role);

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
