import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/market_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../formatters/market_formatters.dart';

class DiagnosticsSheet extends StatefulWidget {
  const DiagnosticsSheet({super.key});
  @override
  State<DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<DiagnosticsSheet> {
  late final TextEditingController address = TextEditingController(
    text: context.read<MarketBloc>().state.baseUrl.toString(),
  );
  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: BlocBuilder<MarketBloc, MarketState>(
          builder: (context, c) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Connection lab',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.7,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('close-lab'),
                        tooltip: 'Close connection lab',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const Text(
                    'The server chooses how often your chart updates.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric('TARGET RATE', '${rate(c.targetHz)} Hz'),
                      ),
                      Expanded(
                        child: _Metric(
                          'DELIVERED · 5s',
                          '${rate(c.effectiveHz)} Hz',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          'ROUND TRIP',
                          c.rtt == null ? '—' : '${c.rtt!.round()} ms',
                        ),
                      ),
                      Expanded(
                        child: _Metric('JITTER', '${c.jitter.round()} ms'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'Delivery mode',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Auto follows your connection. Force a tier to compare.',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final value in [
                        'auto',
                        'full',
                        'degraded',
                        'minimal',
                      ])
                        ChoiceChip(
                          key: Key('tier-$value'),
                          label: Text(
                            '${value[0].toUpperCase()}${value.substring(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.overrideMode == value
                                  ? paletteBackground
                                  : ink,
                            ),
                          ),
                          selected: c.overrideMode == value,
                          showCheckmark: false,
                          selectedColor: accent,
                          side: BorderSide(
                            color: c.overrideMode == value ? accent : line,
                          ),
                          onSelected: c.debugEnabled && c.connected
                              ? (_) => context.read<MarketBloc>().add(
                                  TierOverrideRequested(value),
                                )
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${c.tier.toUpperCase()} · ${c.reason}',
                    style: const TextStyle(fontSize: 11, color: accent),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Recovery checks',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('toggle-offline'),
                          onPressed: () => context.read<MarketBloc>().add(
                            OfflineChanged(!c.offline),
                          ),
                          icon: Icon(
                            c.offline ? Icons.wifi : Icons.wifi_off,
                            size: 15,
                          ),
                          label: Text(
                            c.offline ? 'Reconnect' : 'Go offline',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('skip-book'),
                          onPressed: c.debugEnabled && c.connected
                              ? () => context.read<MarketBloc>().add(
                                  const BookGapRequested(),
                                )
                              : null,
                          icon: const Icon(Icons.sync, size: 15),
                          label: const Text(
                            'Skip a delta',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const Key('drop-socket'),
                      onPressed: c.debugEnabled && c.connected
                          ? () => context.read<MarketBloc>().add(
                              const SocketDropRequested(),
                            )
                          : null,
                      child: const Text(
                        'Drop socket & auto-reconnect',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${c.bookRecoveries} book recoveries   ·   ${c.reconnects} reconnects   ·   ${c.malformed} invalid messages',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: address,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Backend address',
                      helperText: 'Android emulator: http://10.0.2.2:8080',
                      helperStyle: const TextStyle(fontSize: 10, color: muted),
                      errorText: c.addressError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Connect to backend',
                        icon: const Icon(Icons.arrow_forward, size: 19),
                        onPressed: () {
                          context.read<MarketBloc>().add(
                            ServerChanged(address.text),
                          );
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  final String label, value;
  const _Metric(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 9, color: muted, letterSpacing: 1),
      ),
      const SizedBox(height: 7),
      Text(value, style: numbers(size: 24, weight: FontWeight.w500)),
    ],
  );
}
