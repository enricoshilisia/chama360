/// Validates the password or PIN a member sets after their first login.
///
/// Members can choose either — a 4 or 6 digit PIN (easier to remember and
/// type on a phone) or a longer password. Both get checked for the
/// obvious-guess patterns, because a PIN that guards someone's savings
/// record shouldn't be allowed to be 1234.
class CredentialValidator {
  CredentialValidator._();

  /// PINs that are guessed first, every time.
  static const _bannedPins = {
    '0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888', '9999',
    '1234', '2345', '3456', '4567', '5678', '6789', '7890', '0123',
    '4321', '5432', '6543', '7654', '8765', '9876', '3210',
    '1212', '2121', '1010', '0101', '6969', '1122', '2211',
    '000000', '111111', '222222', '333333', '444444', '555555',
    '666666', '777777', '888888', '999999',
    '123456', '234567', '345678', '456789', '654321', '765432',
    '987654', '012345', '121212', '112233', '123123', '696969',
  };

  static const _bannedPasswords = {
    'password', 'password1', 'password123', 'passw0rd', 'qwerty', 'qwerty123',
    'letmein', 'welcome', 'admin', 'admin123', 'iloveyou', 'monkey', 'dragon',
    'football', 'abc123', 'abcd1234', 'chama', 'chama123', 'chama360',
    'sacco', 'sacco123', 'money', 'kenya', 'nairobi', '12345678', '123456789',
  };

  /// Returns null when acceptable, or a message explaining what's wrong.
  /// Nullable input so it drops straight into a TextFormField validator.
  static String? validate(String? raw) {
    final value = raw ?? '';
    final trimmed = value.trim();

    if (trimmed.isEmpty) return 'Enter a password or PIN';
    if (trimmed != value) return 'Cannot start or end with a space';

    final isAllDigits = RegExp(r'^\d+$').hasMatch(trimmed);

    if (isAllDigits) {
      if (trimmed.length != 4 && trimmed.length != 6) {
        return 'A PIN must be exactly 4 or 6 digits';
      }
      if (_bannedPins.contains(trimmed)) {
        return 'That PIN is too easy to guess — pick another';
      }
      if (_isSequential(trimmed) || _isRepeated(trimmed)) {
        return 'That PIN is too easy to guess — pick another';
      }
      return null;
    }

    // Anything not purely numeric is treated as a password.
    if (trimmed.length < 8) {
      return 'A password needs at least 8 characters (or use a 4/6 digit PIN)';
    }
    if (_bannedPasswords.contains(trimmed.toLowerCase())) {
      return 'That password is too common — pick another';
    }
    if (_isRepeated(trimmed)) {
      return 'That password is too simple — pick another';
    }
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(trimmed);
    final hasOther = RegExp(r'[^A-Za-z]').hasMatch(trimmed);
    if (!hasLetter || !hasOther) {
      return 'Mix letters with numbers or symbols';
    }
    return null;
  }

  /// 1234, 6789, 9876 — runs of consecutive values in either direction.
  static bool _isSequential(String value) {
    if (value.length < 3) return false;
    var ascending = true;
    var descending = true;
    for (var i = 1; i < value.length; i++) {
      final diff = value.codeUnitAt(i) - value.codeUnitAt(i - 1);
      if (diff != 1) ascending = false;
      if (diff != -1) descending = false;
    }
    return ascending || descending;
  }

  /// 0000, aaaa — one character over and over.
  static bool _isRepeated(String value) {
    if (value.length < 2) return false;
    return value.split('').every((c) => c == value[0]);
  }

  /// Whether a given value would be treated as a PIN rather than a password
  /// — used to label the field for the member.
  static bool looksLikePin(String value) =>
      RegExp(r'^\d{4}$|^\d{6}$').hasMatch(value.trim());
}
