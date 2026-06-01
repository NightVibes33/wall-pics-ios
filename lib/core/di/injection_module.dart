import 'package:Prism/core/debug/network_logging_client.dart';
import 'package:Prism/core/remote_store/remote_store_client.dart';
import 'package:Prism/core/remote_store/remote_store_tracked_client.dart';
import 'package:Prism/core/persistence/local_store.dart';
import 'package:Prism/core/persistence/persistence_runtime.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:quick_actions/quick_actions.dart';

@module
abstract class AppModule {
  @lazySingleton
  RemoteStoreClient get remoteStoreClient => const RemoteStoreTrackedClient();

  @lazySingleton
  AppLinks get appLinks => AppLinks();

  @lazySingleton
  InternetConnectionChecker get internetConnectionChecker => InternetConnectionChecker.instance;

  @lazySingleton
  QuickActions get quickActions => const QuickActions();

  @lazySingleton
  LocalStore get localStore => PersistenceRuntime.store;

  @lazySingleton
  http.Client get httpClient => NetworkLoggingClient();
}
