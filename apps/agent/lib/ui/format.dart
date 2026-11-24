/// Numéro affiché à la sénégalaise : « 221771234567 » → « 77 123 45 67 ».
String formatPhone(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('221') && d.length == 12) d = d.substring(3);
  if (d.length != 9) return raw;
  return '${d.substring(0, 2)} ${d.substring(2, 5)} ${d.substring(5, 7)} ${d.substring(7)}';
}

/// Initiales d'un nom affiché « Awa DIOP » → « AD ».
String initials(String firstName, String lastName) {
  String first(String s) => s.trim().isEmpty ? '' : s.trim()[0].toUpperCase();
  return '${first(firstName)}${first(lastName)}';
}
