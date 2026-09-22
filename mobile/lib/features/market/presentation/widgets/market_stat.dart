import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class MarketStat extends StatelessWidget {
  final String label, value;
  const MarketStat(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 10)),
      const SizedBox(height: 5),
      Text(value, style: numbers(size: 11)),
    ],
  );
}
