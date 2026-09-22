import '../config/app_config.dart';
import '../../core/network/json_transport.dart';
import '../../features/market/data/datasources/market_remote_data_source.dart';
import '../../features/market/data/repositories/remote_market_repository.dart';
import '../../features/market/domain/use_cases/market_session.dart';
import '../../features/market/presentation/bloc/market_bloc.dart';

/// Constructor injection at the composition root; no global service locator.
MarketBloc createMarketBloc({AppConfig? config}) {
  final settings = config ?? AppConfig.fromEnvironment();
  final source = MarketRemoteDataSource(
    IoJsonTransport(policy: settings.network),
  );
  final repository = RemoteMarketRepository(source);
  return MarketBloc(
    MarketSession(
      repository: repository,
      baseUrl: settings.server,
      policy: settings.session,
    ),
  );
}
