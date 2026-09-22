import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/market_bloc.dart';
import '../formatters/market_formatters.dart';

class ConnectionStatus extends StatelessWidget {
  final MarketState state;
  const ConnectionStatus({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final c = state,
        color = state.isLive ? (state.tier == 'full' ? accent : amber) : amber;
    final label = switch (c.link) {
      LinkState.live => 'Live',
      LinkState.syncing => 'Syncing',
      LinkState.connecting => 'Connecting',
      LinkState.stale => 'Stale',
      LinkState.paused => 'Paused',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.13)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 12, color: line),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.targetHz == 0
                  ? 'Awaiting delivery status'
                  : '${c.tier[0].toUpperCase()}${c.tier.substring(1)} · ${rate(c.targetHz)} Hz',
              style: const TextStyle(color: ink, fontSize: 11),
            ),
          ),
          Icon(
            c.isLive ? Icons.network_check_rounded : Icons.wifi_off_rounded,
            size: 13,
            color: muted,
          ),
          const SizedBox(width: 5),
          Text(
            c.connected && c.rtt != null ? '${c.rtt!.round()} ms' : 'Offline',
            style: numbers(size: 10, color: muted),
          ),
        ],
      ),
    );
  }
}
