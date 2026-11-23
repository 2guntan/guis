import 'dart:io';

import 'package:fieldproof_agent/core/json_store.dart';
import 'package:fieldproof_agent/core/model/dossier.dart';
import 'package:fieldproof_agent/core/services.dart';
import 'package:fieldproof_agent/core/sync/outbox.dart';
import 'package:fieldproof_agent/features/dossiers/dossiers_page.dart';
import 'package:fieldproof_agent/features/editor/editor_page.dart';
import 'package:fieldproof_agent/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Les écrans s'affichent sans débordement sur un petit téléphone Android (360 × 640),
/// sans réseau ni session : chaque étape du dossier, en saisie puis en lecture seule.
void main() {
  late AgentServices services;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('fp_screens');
    services = AgentServices(
      client: SupabaseClient('http://127.0.0.1:9', 'cle-de-test', authOptions: const AuthClientOptions(autoRefreshToken: false)),
      outbox: Outbox(JsonFileStore(File('${dir.path}/outbox.json'))),
      dossiers: DossierStore(dir),
      dir: dir,
      photos: dir,
    );
    services.referentials = Referentials(
      regions: [
        {'id': 'r1', 'name': 'ZIGUINCHOR'},
      ],
      communes: [
        {'id': 'c1', 'name': 'ZIGUINCHOR', 'region_id': 'r1'},
      ],
      organizations: [
        {'id': 'qa', 'code': 'FIELDPROOF-QA', 'name': 'Bac à sable', 'is_sandbox': true},
      ],
      memberships: [
        {'organization_id': 'qa', 'role': 'field_agent'},
      ],
      lenderConfigs: [
        {
          'organization_id': 'qa',
          'config': {
            'consent_notice_version': 'demo-2026-11',
            'required_documents': [
              {'kind': 'id_front', 'label': 'Pièce d\'identité — recto'},
            ],
            'complementary_fields': [
              {'key': 'father_name', 'label': 'Prénom et nom du père', 'type': 'text', 'required': true},
              {'key': 'guarantee', 'label': 'Garantie proposée', 'type': 'select', 'options': ['Aucune', 'Caution solidaire']},
            ],
          },
        },
      ],
    );
  });

  Widget app(Widget home) => MaterialApp(
        theme: fieldproofTheme(),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      );

  Dossier dossier({String status = statusDraft}) => Dossier(
        id: 'f1',
        clientId: 'c1',
        farmId: 'fa1',
        profileId: 'me',
        createdAt: DateTime(2026, 11, 20),
        status: status,
        lenderOrganizationId: 'qa',
        returnReason: status == statusReturned ? 'Photo de la CNI floue, à reprendre' : null,
        client: {'last_name': 'Diatta', 'first_names': 'Awa'},
        farm: {'name': 'Jardin Awa'},
        parcels: [Parcel(id: 'p1')],
      );

  Future<void> walkSteps(WidgetTester tester, Dossier d) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(EditorPage(services: services, dossier: d)));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(const Key('next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Récapitulatif'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('les 9 étapes d\'un brouillon s\'affichent sur un petit écran', (tester) async {
    await walkSteps(tester, dossier());
  });

  testWidgets('un dossier renvoyé montre le motif au récapitulatif', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(EditorPage(services: services, dossier: dossier(status: statusReturned), initialStep: 8)));
    await tester.pump();
    expect(find.text('Photo de la CNI floue, à reprendre'), findsOneWidget);
    expect(find.text('Soumettre à nouveau au superviseur'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('un dossier soumis est en lecture seule', (tester) async {
    await walkSteps(tester, dossier(status: statusSubmitted));
  });

  testWidgets('« Mes dossiers » sans session ni réseau', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(DossiersPage(services: services)));
    await tester.pump();
    expect(find.text('Tout est envoyé'), findsOneWidget);
    expect(find.text('Nouveau dossier'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
