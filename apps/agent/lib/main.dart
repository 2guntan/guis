import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'core/api.dart';
import 'core/config.dart';
import 'core/error_log.dart';
import 'core/services.dart';
import 'features/auth/sign_in_page.dart';
import 'features/producers/producers_page.dart';
import 'features/update_page.dart';
import 'ui/theme.dart';

// Démarrage repris de Fieldproof (apps/agent/lib/main.dart) : Supabase remplacé par l'API Guis,
// contrôle du rôle retiré (le serveur accepte tout compte connecté).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait seulement : la carte du tour du champ et ses boutons sont pensés pour la hauteur.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (AppConfig.missing.isNotEmpty) {
    runApp(
      _Message(
        'Configuration absente : ${AppConfig.missing.join(', ')}.\n'
        'Compiler avec --dart-define=API_URL=https://… (voir apps/agent/README.md).',
      ),
    );
    return;
  }
  final dir = await getApplicationSupportDirectory();
  // Erreurs inattendues : gardées dans le journal du téléphone (menu « Journal des erreurs »).
  final log = ErrorLog(File('${dir.path}/erreurs.log'));
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    log.write(d.exception, d.stack);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    log.write(e, st);
    return true;
  };
  final AppServices services;
  try {
    final build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    services = await AppServices.open(dir, Api(AppConfig.apiUrl), appBuild: build);
  } catch (e, st) {
    await log.write(e, st);
    runApp(
      const _Message(
        'Guis n\'a pas pu démarrer.\n\n'
        'Vos saisies non envoyées restent sur le téléphone : ne supprimez pas les données de l\'app. '
        'Fermez Guis puis rouvrez-la ; si le problème continue, prévenez le coordinateur.',
      ),
    );
    return;
  }
  runApp(GuisApp(services: services));
}

class GuisApp extends StatelessWidget {
  const GuisApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guis',
      debugShowCheckedModeBanner: false,
      theme: guisTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: services,
        builder: (context, _) => services.updateRequired
            ? UpdatePage(services: services)
            : services.signedIn
            // La clé force un écran neuf à chaque changement de compte.
            ? ProducersPage(key: ValueKey(services.account!.id), services: services)
            : SignInPage(services: services),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
      ),
    ),
  );
}
