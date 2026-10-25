/// Basic local form checks, not the server's still-open password policy.
abstract final class AuthValidation {
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

  static String? confirmation(String? value, String password) {
    if (value == null || value.isEmpty) return 'Şifrenizi tekrar girin.';
    return value == password ? null : 'Şifreler eşleşmiyor.';
  }
}
