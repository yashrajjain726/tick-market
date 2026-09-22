import '../../domain/entities/market_entities.dart';

String money(int? cents, {bool decimals = true}) {
  if (cents == null) return '—';
  final absolute = cents.abs();
  final whole = (absolute ~/ priceScale).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '${cents < 0 ? '−' : ''}$whole${decimals ? '.${(absolute % priceScale).toString().padLeft(2, '0')}' : ''}';
}

String quantity(int value, {int places = 5}) =>
    (value / quantityScale).toStringAsFixed(places);
String clockTime(int time, {bool seconds = false}) {
  final d = DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}${seconds ? ':${d.second.toString().padLeft(2, '0')}' : ''}';
}

String rate(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
