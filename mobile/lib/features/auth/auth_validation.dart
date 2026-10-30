/// Local form checks aligned with the approved registration contract.
abstract final class AuthValidation {
  static String? displayName(String? value) {
    return value == null || value.trim().isEmpty
        ? 'Adınızı ve soyadınızı girin.'
        : null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'E-posta adresinizi girin.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Geçerli bir e-posta adresi girin.';
    }
    return null;
  }

  static String? password(String? value) {
    // Passwords must never be trimmed or silently changed.
    return value == null || value.isEmpty ? 'Şifrenizi girin.' : null;
  }

  static String? registrationPassword(String? value) {
    final requiredError = password(value);
    if (requiredError != null) return requiredError;

    // The API counts Unicode code points, not UTF-16 units or graphemes.
    // Do not trim or normalize the password, including whitespace.
    var length = 0;
    for (final rune in value!.runes) {
      if (rune >= 0xD800 && rune <= 0xDFFF) {
        return 'Şifrenizde geçersiz bir karakter var.';
      }
      length++;
      if (length > 128) return 'Şifreniz en fazla 128 karakter olabilir.';
    }
    return length < 8 ? 'Şifreniz en az 8 karakter olmalıdır.' : null;
  }

  static String? confirmation(String? value, String password) {
    if (value == null || value.isEmpty) return 'Şifrenizi tekrar girin.';
    return value == password ? null : 'Şifreler eşleşmiyor.';
  }
}
