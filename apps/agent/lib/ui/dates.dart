import 'package:flutter/material.dart';

/// Calendrier dont les bornes s'élargissent pour contenir la date affichée : une date ancienne (semence
/// reçue avant la période prévue) ou l'horloge du téléphone mal réglée ne font jamais échouer le
/// calendrier (première date après la dernière, ou date affichée hors des bornes).
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime? initial,
  required DateTime first,
  required DateTime last,
  String? helpText,
}) {
  final shown = DateUtils.dateOnly(initial ?? DateTime.now());
  var from = DateUtils.dateOnly(first);
  var to = DateUtils.dateOnly(last);
  if (shown.isBefore(from)) from = shown;
  if (shown.isAfter(to)) to = shown;
  return showDatePicker(context: context, initialDate: shown, firstDate: from, lastDate: to, helpText: helpText);
}
