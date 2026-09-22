import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/theme/app_theme.dart';
import '../features/market/presentation/bloc/market_bloc.dart';
import '../features/market/presentation/pages/market_screen.dart';
import 'di/dependencies.dart';

class TickApp extends StatelessWidget {
  final MarketBloc Function()? createBloc;
  const TickApp({super.key, this.createBloc});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        (createBloc ?? createMarketBloc)()..add(const MarketStarted()),
    child: const _MarketApp(),
  );
}

class _MarketApp extends StatefulWidget {
  const _MarketApp();
  @override
  State<_MarketApp> createState() => _MarketAppState();
}

class _MarketAppState extends State<_MarketApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MarketBloc>().add(const LifecyclePausedChanged(false));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      context.read<MarketBloc>().add(const LifecyclePausedChanged(true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tick · Market',
    debugShowCheckedModeBanner: false,
    theme: tickTheme,
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => const MarketScreen()),
  );
}
