# Guis Android app: production readiness audit

Date: 2026-11-27. Scope: `apps/agent` (Flutter app, Android target), plus the server routes the app calls (`apps/web/app/api/**`, `apps/web/lib/{api,auth,scope}.ts`, `deploy/Caddyfile`). No code was changed during this audit.

## 1. Executive summary

Guis is a small, well-structured offline-first collection app: about 2,900 lines of Dart across 15 files, three dependencies that do real work (http, geolocator, image_picker, plus flutter_map for the field walk), and a persisted outbox with ordered, idempotent replay. Code quality is above average for its size. The analyzer is clean, 45 tests pass, and the outbox design (one subject per producer, replacement of the last snapshot, attachments uploaded before the record) is sound.

The app is **not ready for release to thousands of agents**. The main risks concern the core promise of the product, that nothing typed in the field is lost:

1. **One bad entry can stop all syncing.** A missing photo file, or any deterministic server 5xx on one record, is treated as a transient error, so it stops the whole queue for *every* producer, forever. Confirmed by a probe test.
2. **Field work is fragile on real phones.** In-progress walks and forms live only in memory: there is no handling of system back, no save of in-progress work, no recovery of a photo when the app is killed (`retrieveLostData`), and GPS capture does not survive the screen locking. Low-end Android devices kill apps while the camera is open, so agents will lose work.
3. **Producer personal data is not protected on the device.** It is stored in plain JSON, included in Android auto-backup (`allowBackup` defaults to true in the merged manifest), and kept after sign-out, where the next account to sign in on the same phone can see it (confirmed).
4. **There is no release infrastructure.** The APK built for this audit is signed with the Android **debug** key. There is no crash reporting, no update channel, and no minimum-version check.

None of these needs a rewrite. Most fixes are small and local (hours to a few days each). Section 7 orders them.

## 2. Scores

| Category | Score | Justification |
|---|---|---|
| Bugs & functional correctness | 60 | Core flows work and are tested; several confirmed data-loss and queue-blocking bugs |
| Code quality & architecture | 80 | Clear layering (screens → `AppServices` → `Outbox`/`Api`), little duplication, good comments; `AppServices` is a growing god object and state is ad hoc |
| Performance & optimization | 72 | Small app; full JSON rewrite on every save, full-size images decoded for thumbnails, no tile cache |
| Security & privacy | 50 | Good: no secrets in the code, bearer tokens hashed on the server. Weak: plaintext PII and token on the device, backup enabled, data kept after sign-out, no login rate limit |
| UI/UX & design consistency | 72 | Consistent, legible design that follows the mockups, in French; destructive actions have no confirmation, no unsaved-changes guard, raw English exception text reaches agents |
| Android compatibility & reliability | 50 | No lifecycle or process-death handling, GPS stops when the screen is off, no rotation or font-scale verification |
| Testing & QA | 65 | Good unit and service tests of the outbox; no tests for the walk page, failure paths, lifecycle, or real devices |
| Production readiness | 40 | Debug-signed release, versionCode 1, no crash reporting, sideloaded with no update path |
| Product & features | 70 | Strong focused scope; missing a sync detail screen, update prompt, and walk safeguards |
| **Overall** | **62 / 100** | Solid base. Not releasable at scale until the Critical and High items are fixed. |

## 3. Tests performed and results

| Check | Result |
|---|---|
| `flutter analyze` (Flutter 3.35.7 / Dart 3.9.2) | **No issues found** |
| `flutter test` | **45 passed, 1 skipped** (`captures_test.dart`, tag-gated screenshots) |
| `flutter build apk --release --target-platform android-arm64 --analyze-size` | **Success**, 19.3 MB arm64 APK, minSdk 24, targetSdk 36, compileSdk 36 |
| `apksigner verify --print-certs` on that APK | Signer DN `CN=Android Debug` (no release key on this Mac; CI behaves the same without secrets) |
| Merged manifest (`aapt2 dump xmltree`) | Only `MainActivity` exported (launcher, correct). Image picker FileProvider not exported. **No `allowBackup` / `dataExtractionRules`** |
| Probe: `backoff()` with large attempt counts (scratch Dart script) | **Bug confirmed**: from 63 attempts, `backoff` returns `0:00:00` (integer overflow) |
| Probe tests P1–P4 (scratch package depending on `apps/agent` by path, repo untouched) | **4/4 confirmed** (see C1, H1, H2, M1) |
| `flutter pub outdated` (via `pub get`) | 37 packages have newer versions outside the constraints; no known critical CVE identified in direct deps, but not verified against an advisory database |

**Not tested (limitations, stated plainly):**
- **No emulator or device run.** Two AVDs exist on this Mac, but no Android system image is installed (`FATAL: Broken AVD system path`). Installing one is a ~1.5 GB download and was not done. So rotation, font scaling, dark mode, the camera, real GPS, screen-lock behaviour, process death, low-end devices and permission-denial dialogs are assessed **from code and known platform behaviour only**. They are marked "Suspected" below.
- Real server (PostgreSQL/PostGIS) not started. Server behaviour was read from source, not run.
- No penetration test, no dependency CVE scan, no Play Console pre-launch report.

Legend: **Confirmed** = reproduced by a test or tool. **Code-confirmed** = deterministic from reading the code, not executed. **Suspected** = needs a device to confirm.

## 4. Issues

Effort: S ≤ ½ day, M = 1–3 days, L = about a week.

### Critical

**C1. One failing entry blocks the whole outbox for every producer, forever** (Confirmed, P1 and P2)
- Files: `lib/core/sync/outbox.dart:276-291`, `lib/core/api.dart:68-72`, `lib/core/services.dart:276-279`
- Evidence: producer A saved with a photo, then the photo file deleted, then producer B saved. After 3 forced syncs, B is never sent and A is never marked rejected. `lastSyncError` is `PathNotFoundException: Cannot open file, path = …` and is shown to the agent verbatim. The same happens when the server returns 500 on one specific producer (P2): B never leaves.
- Root cause: every error that is not an `ApiException` 4xx is "transient", and a transient error `break`s the whole loop to keep global order. A `FileSystemException`, a `TypeError` in the payload, or a deterministic 500 (`apps/web/lib/api.ts:47-48` maps any unknown error to 500) is a poison message.
- Fix: (a) classify local errors (`FileSystemException`, `FormatException`, `TypeError`) as definitive and mark the entry rejected, or drop a missing attachment and send the record without it. (b) After N transient failures (for example 8) on the *same* entry, mark it "blocked" and continue with *other* subjects; per-subject ordering is all the server needs. (c) Map errors to a French message, never `toString()`.
- Effort: M. Regression risk: medium. Outbox ordering is well tested; extend `outbox_test.dart`.

**C2. Release APK is debug-signed, and switching keys later forces agents to uninstall and lose their offline data**
- Files: `android/app/build.gradle.kts:52-56`, `.github/workflows/apk.yml:37-52`
- Evidence: the built APK's signer is `CN=Android Debug`. The CI only prints a `::notice::` when the secrets are missing.
- Root cause: silent fallback to the debug key. An APK signed with another key cannot update the installed one, so an agent must uninstall, which **deletes `outbox.json` and unsent photos**.
- Fix: create the release keystore now, before the first field deployment. Make `assembleRelease` fail without it (keep the debug fallback only for a `-Pci-unsigned` flag or for PR builds). Back up the keystore offline.
- Effort: S. Regression risk: low.

### High

**H1. Producer data is kept on the phone after sign-out and visible to the next account** (Confirmed, P4)
- Files: `lib/core/services.dart:153-166`, `lib/core/services.dart:293-337`
- Evidence: after `signOut()`, `data.json` still contains the previous agent's producer phone numbers. A second agent signs in, the bootstrap fails (flaky network), and `searchExact('77 999 88 77')` returns the first agent's producer, which is outside their communes (breaks ADR-0001).
- Fix: on sign-out, clear `producers`, `fields`, `lists`, `syncedAt` and the photos **except** what pending outbox entries still reference (those must survive for same-account re-login, per the current design). On sign-in with a different account id, clear the cache before syncing.
- Effort: S. Regression risk: low. Add a test next to "déconnexion".

**H2. A seed removed after the producer was saved in the same screen comes back** (Confirmed, P3)
- File: `lib/features/producers/producer_page.dart:137-140`
- Steps: new producer → add seed → "Ajouter un champ" (stores the producer) → back → remove the seed → "Enregistrer la fiche". The seed stays on the server and reappears after refresh.
- Root cause: deletion is recorded only if `widget.producer` (the producer at page open) had the seed. It should check what was last *saved* (`_saved ?? widget.producer`).
- Fix: `if ((_saved ?? widget.producer)?.seeds.any((x) => x.id == seed.id) ?? false) _deletedSeeds.add(seed.id);`. Simpler and more robust: always send the ids removed in this session.
- Effort: S. Regression risk: low.

**H3. In-progress work is lost on back, cancel, or "Recommencer"; no unsaved-changes guard** (Code-confirmed)
- Files: `lib/features/fields/field_walk_page.dart:230-235, 328, 337`, `lib/features/fields/field_page.dart`, `lib/features/producers/producer_page.dart`. No `PopScope` anywhere (grep).
- Scenario: an agent walks a 2 ha field for 15 minutes, then the system back gesture or "Annuler" throws all the points away with no prompt. "Recommencer" sits next to "Terminer le tracé" and clears all points in one tap. Seeds or consent ticked in consultation mode are discarded silently on back.
- Fix: a `PopScope` with a confirmation dialog when there are changes (the walk page has points, or a form is dirty). A confirmation on "Recommencer". Undo already exists for one point; keep it.
- Effort: S–M. Regression risk: low.

**H4. Killed process loses the form and the photo (camera on low-end devices)** (Suspected, high likelihood)
- Files: `lib/core/photos.dart:56-70`. No `retrieveLostData` and no restoration (grep).
- Root cause: launching the camera intent backgrounds the app, and Android often kills it on 1–2 GB phones. On return, Flutter restarts at the list; the form state and the captured photo are gone. image_picker documents `ImagePicker().retrieveLostData()` for exactly this case.
- Fix: persist a draft (producer or field form as JSON) before opening the camera or the walk, restore it on start, and call `retrieveLostData()` at startup. Alternatively use `RestorationMixin`.
- Effort: M. Regression risk: medium.

**H5. GPS walk stops when the screen locks or the app is backgrounded** (Suspected)
- File: `lib/features/fields/field_walk_page.dart:47-58`
- Root cause: the foreground-only position stream has no foreground service (`AndroidSettings.foregroundNotificationConfig`) and no wakelock. With the default 30 s screen timeout, auto mode ("tous les 5 m") stops capturing while the agent walks with the phone in hand or in a pocket. Points held only in memory are lost if Android kills the app.
- Fix: keep the screen on during the walk (a wakelock package or `FLAG_KEEP_SCREEN_ON` through a tiny platform channel), **or** use geolocator's foreground notification config (needs the `FOREGROUND_SERVICE_LOCATION` permission and a Play declaration). Persist the points to disk after each one.
- Effort: M. Regression risk: low.

**H6. Personal data and session token stored in plain text and included in Android backup**
- Files: `lib/core/services.dart:59-69` (`session.json`, `data.json`, `outbox.json`, `photos/` under `getApplicationSupportDirectory` = `filesDir`), `android/app/src/main/AndroidManifest.xml` (no `allowBackup`), merged manifest confirms the default.
- Risk: names, phone numbers, photos, GPS contours, and a 90-day bearer token (`apps/web/lib/auth.ts:12`) go into Google auto-backup and `adb backup` (on older APIs). They can be restored onto another device with a valid session. A lost or stolen phone exposes everything to anyone with physical access.
- Fix: `android:allowBackup="false"` plus `android:dataExtractionRules`/`fullBackupContent` that exclude everything. Store the token in Android Keystore (`flutter_secure_storage`). Optionally encrypt `data.json` with a key from Keystore. Consider a shorter token lifetime with silent renewal, and a way for the admin to revoke one device's sessions.
- Effort: S (backup) / M (secure storage). Regression risk: low.

**H7. No crash reporting, no logging, startup failure shows a blank screen**
- Files: `lib/main.dart:14-28`. No `FlutterError.onError` or `runZonedGuarded` (grep).
- Root cause: any exception in `AppServices.open()` (for example a corrupt or old-schema `data.json`, or a cast error in `_load`) happens before `runApp`, so the app is stuck on the splash screen forever. The only workaround is "clear data", which deletes the unsent outbox.
- Fix: wrap `_load` in try/catch per file. On a corrupt `data.json`, discard it, because it can be re-downloaded. **Never** discard `outbox.json`: move it aside and show an error screen. Add Sentry or Firebase Crashlytics (free tier), with personal data scrubbed.
- Effort: S–M. Regression risk: low.

**H8. No protection against password guessing on login** (server side, affects the app)
- Files: `apps/web/app/api/auth/login/route.ts`, `deploy/Caddyfile` (no rate limit)
- Risk: phone numbers are predictable (9 digits), and bcrypt slows guessing but does not stop it.
- Fix: limit attempts per phone and per IP (a small `login_attempts` table or an in-memory limiter, since there is a single instance), with a lockout after N failures. Return 429; the app already treats 429 as retryable, but on the login screen it should show "Trop de tentatives".
- Effort: S. Regression risk: low.

### Medium

**M1. Error text shown to agents is raw English exception output** (Confirmed in P1)
- File: `lib/core/api.dart:75-82` (`_ => error.toString()`). It is also used in `photo_box.dart:36` ("Appareil photo indisponible : $e").
- Fix: a default French message ("Erreur inattendue, réessai automatique"); log the detail to crash reporting.
- Effort: S.

**M2. Backoff overflows to 0 s after 63 attempts** (Confirmed)
- File: `lib/core/sync/outbox.dart:152`. `10 * pow(2, attempts-1).toInt()` overflows an int64 to a negative or zero number. After about 16 h of failures at the 15 min cap, retries happen every minute (auto-sync).
- Fix: `Duration(seconds: math.min(900, 10 << math.min(attempts - 1, 7)))`, or clamp the exponent first.
- Effort: S.

**M3. GPS stream subscription can leak and call `setState` after dispose** (Code-confirmed)
- File: `field_walk_page.dart:41-58`. `_start()` awaits `ensureLocation()` (which may show the permission dialog). If the user leaves first, `_sub` is created after `dispose()` and is never cancelled; each fix calls `setState` on a disposed state (an exception every second, GPS kept on, battery drain).
- Fix: `if (!mounted) return;` after the await, plus `mounted` checks in the listeners.
- Effort: S.

**M4. Last-writer-wins with no conflict detection**
- Files: `apps/web/app/api/app/producers/[id]/route.ts:38-45`, `apps/web/app/api/app/fields/[id]/route.ts:53-59`
- Two agents (or an agent and an admin) editing the same producer: a phone that has been offline for days overwrites newer edits with its stale snapshot without warning.
- Fix: send the `updated_at` the app last saw (it is already in the bootstrap) as `If-Unmodified-Since` or a `base_updated_at` field. The server returns 409 on mismatch and the app shows "modifié ailleurs". Or merge field by field. Decide the policy in an ADR.
- Effort: M.

**M5. Satellite tiles: Esri terms of use, no cache, mobile data cost**
- File: `field_walk_page.dart:127-132`. Esri World Imagery tiles without an API key or account may not be allowed for production use (check the Esri terms). Each walk downloads tiles over mobile data, with no caching, and nothing shows offline.
- Fix: an ArcGIS developer key (free tier) or another licensed provider. Add a tile cache (`flutter_map_cache` or `CachedTileProvider`). Optionally pre-download tiles for a commune over Wi-Fi.
- Effort: M.

**M6. Photos accumulate forever; orphan photos never cleaned up**
- Files: `lib/core/photos.dart:66-67`, `lib/core/services.dart:26` ("gardées après dépôt").
- A photo taken and then abandoned (back without saving) stays on disk. Uploaded photos are kept for preview indefinitely. At about 300 KB each, a season of collection can fill hundreds of MB on cheap phones.
- Fix: on startup, delete photos referenced neither by a pending entry nor by a local producer or field. Optionally delete uploaded photos older than X days (the preview falls back to the "envoyée" placeholder).
- Effort: S.

**M7. Thumbnails decode 1600 px images at full size**
- Files: `lib/ui/photo_box.dart:61, 90`, `producer_page.dart:480`
- Fix: `Image.file(file, cacheWidth: 192)` for the 96 px thumbnail and `cacheWidth: 900` for the large view; `ResizeImage` for `FileImage`.
- Effort: S.

**M8. Whole data set rewritten to disk on every action**
- Files: `lib/core/services.dart:94-100`, called from `markMine` (on every producer tap for agents), `saveProducer`, `saveField`, `refresh`.
- Fine for hundreds of producers; with an admin account and thousands of producers with 200-point contours, this is several MB of JSON encoded on the UI isolate per tap (jank on low-end phones).
- Fix: store `mine` separately, encode in `compute()`, or move to SQLite (`sqflite`/`drift`) if volumes grow.
- Effort: S (split) / L (SQLite).

**M9. Bootstrap is a single request with a 45 s timeout**
- File: `lib/core/api.dart:26, 43`. On 2G/EDGE in rural areas, a large admin bootstrap may never finish within 45 s, so it fails forever while the UI shows stale data.
- Fix: a longer timeout for GET bootstrap, a delta sync (`?since=updated_at`), and pagination later.
- Effort: M.

**M10. No app update channel or minimum version**
- APKs are distributed as GitHub artifacts with a 30-day retention. Agents will not know about updates, and a server change can break old clients silently.
- Fix: the server returns `min_app_version` and `latest_apk_url` in the bootstrap, and the app shows a blocking or optional update banner. Bump `versionCode` (CI already passes `--build-number`, but local builds use `1`).
- Effort: S–M.

**M11. Auto mode in the walk records GPS jitter, which likely leads to self-intersection rejections** (Suspected)
- File: `field_walk_page.dart:54-56`. Points are accepted every 5 m with accuracy up to 30 m. Standing still or walking slowly in poor signal adds zigzags, so "Le contour se croise" appears often.
- Fix: in auto mode, require accuracy ≤ 10–15 m, require the step to exceed the reported accuracy, and simplify the ring (Douglas–Peucker) on "Terminer".
- Effort: S–M. Needs a field test to tune.

**M12. Client and server validation differ, so some errors only show up at sync**
- Declared area: the app accepts any value > 0, the server rejects > 1000 ha (`fields/[id]/route.ts:19`). Seed quantity: no limit in the app, the server caps at 100,000 and 50 seeds. Phone: the app accepts ≥ 9 digits (`producer_page.dart:289`), for example 10 random digits.
- Fix: share the limits (constants file) and validate on the form, which avoids "Refusé" entries discovered later, away from the producer.
- Effort: S.

### Low

| ID | Issue | Location | Fix | Effort |
|---|---|---|---|---|
| L1 | `_saving` never reset if `saveProducer`/`saveField` throws, leaving the button disabled forever | `producer_page.dart:79-100`, `field_page.dart:81-96` | try/finally | S |
| L2 | `retry()` silently does nothing if a sync is already running | `services.dart:244-248` | queue a follow-up sync | S |
| L3 | Date picker: `firstDate: DateTime(2025)` with `initialDate` from an older `received_on`, or a phone clock set wrong (`lastDate < firstDate`), triggers an assertion in debug and odd behaviour in release | `producer_page.dart:637-642` | clamp `initialDate`, compute `firstDate` from data | S |
| L4 | Dark-mode launch theme is black, then the light app appears: flash | `res/values-night/styles.xml` | use the light theme for both, or the app's sand color | S |
| L5 | No dark theme in the app (acceptable for outdoor use; document the choice) | `lib/ui/theme.dart` | none, or `darkTheme` later | — |
| L6 | Fixed `toolbarHeight` 72/76 and fixed-size rows may overflow at system font scale 1.3–2.0 (tests check 360×640 at 1.0 only) | `producers_page.dart:94`, `producer_page.dart:150` | add a widget test with `textScaler: 1.5/2.0` | S |
| L7 | Landscape not handled: the walk page overlays cover the map (Suspected) | `field_walk_page.dart` | lock to portrait (`SystemChrome.setPreferredOrientations`) or adapt | S |
| L8 | Accessibility: `CustomPaint` contour has no `Semantics`; GPS precision chip conveyed by color plus text (OK); avatar colors only decorative (OK) | `field_page.dart:264` | `Semantics(label: 'Contour, N sommets')` | S |
| L9 | CI silently builds an APK pointing to `guis.example.invalid` when the secret is missing | `.github/workflows/apk.yml:55` | fail the job on push to main if the secret is missing | S |
| L10 | `android.enableJetifier=true` is no longer needed (slows builds) | `android/gradle.properties` | remove after checking deps | S |
| L11 | Java/Kotlin target 11 is fine; AGP 8.9.1 / Kotlin 2.1.0 / Gradle 8.12 are current enough; 37 transitive packages are behind | `pubspec.lock` | scheduled `flutter pub upgrade` | S |
| L12 | Photo upload: any authenticated user can upload under any UUID and reference another user's photo id (low impact) | `apps/web/app/api/photos/[id]/route.ts` | record `uploaded_by` and check it when linking | S |
| L13 | `ProducerPage` does not listen to `AppServices`: a sync that refreshes data while the page is open is not reflected until a rebuild | `producer_page.dart` | wrap in `ListenableBuilder` | S |
| L14 | `_ProducerTile` uses `p.id.hashCode` for the avatar color: stable within a run, but not guaranteed stable across Dart versions | `producers_page.dart:382` | hash the UUID characters explicitly | S |

## 5. Architecture notes

**What works well:**
- `AppServices` is the single facade screens talk to. This makes the service-level tests (`services_test.dart`) meaningful.
- The outbox is persisted, ordered per subject, replaces the tail snapshot, uploads attachments before the record, has a deterministic photo path, and uses atomic writes (`JsonFileStore` writes a temp file then renames). This is the right design for offline collection.
- No secrets in the app (`config.dart` takes only the URL); public repo hygiene is respected.

**What to change:**
- `AppServices` combines session, cache, outbox orchestration, timers and photo files. Before it grows further, split it into `SessionStore`, `LocalCache` and `SyncController`.
- Validation rules are duplicated between Dart and TypeScript by hand (M12). A shared JSON of limits, served in the bootstrap, would keep them aligned.
- Sync status is a set of loose fields (`syncing`, `lastSyncError`, `sessionExpired`, `recentlySent`). A small immutable `SyncState` would simplify the UI logic in `_SyncStatus` and `_ProducerTile`.

## 6. UI/UX review (from code and mockups; no device run)

- Visual consistency is good: one theme file, the Fraunces + Geist pair, big touch targets (52–64 px buttons), French microcopy that is clear and kind ("Gardé sur le téléphone, envoyé avec le réseau").
- Empty, loading and error states exist for the list (agent and admin), for an expired session, for a rejection (with "Écarter"), and for GPS precision. **Missing:** a view of what is waiting to sync (which entries, why they failed, a retry per entry). Today the agent sees only a count and a "Refusé" chip per producer, and nothing at all for C1-type blocks.
- Destructive or irreversible actions need confirmation: "Recommencer" (walk), "Écarter" (rejected entry: this deletes the agent's typed data), "Supprimer" (seed).
- The consent checkbox is locked once saved; this is good, but no audit trail is shown of who recorded the consent.
- "Se reconnecter" on an expired session calls the full `signOut()` (clears "Mes producteurs"). Ideally re-authentication keeps the context.

## 7. Prioritised roadmap

**Before any field deployment (about 1 week):**
1. C2 release keystore and mandatory signing (S)
2. C1 outbox poison handling plus French errors (M), M1 (S), M2 (S)
3. H1 clear the cache on sign-out or account switch (S)
4. H2 seed deletion (S)
5. H3 back and "Recommencer" confirmations (S–M)
6. H6 disable backup (S)
7. H7 safe startup plus crash reporting (S–M)
8. M3 walk page `mounted` checks (S)

**Before scaling to many agents (about 1–2 weeks):**
9. H4 drafts plus `retrieveLostData` (M)
10. H5 keep the screen on / foreground service during the walk, persist the points (M)
11. H8 login rate limiting (S)
12. M10 update channel plus min version (S–M)
13. M5 tile licence plus cache (M)
14. M6/M7 photo cleanup and thumbnails (S)
15. A "File d'envoi" screen listing pending and blocked entries (M)

**Hardening (ongoing):**
16. M4 conflict detection (M), M8/M9 storage and bootstrap scaling, M11 auto-walk filtering, M12 shared validation, the Low items.

**Tests to add (alongside the fixes):** outbox poison entry and missing attachment; sign-out cache wipe; seed deletion after an intermediate save; walk page (cancel confirmation, permission denied, dispose during permission prompt); font scale 2.0 overflow; startup with a corrupt `data.json`. Then a manual device test pass on one low-end phone (2 GB RAM, Android 10–12): camera with "Don't keep activities" enabled, a 15-minute walk with the screen timeout at 30 s, airplane mode in the middle of a sync, rotation, location permission denied permanently.

## 8. Regression risks of the fixes

- Outbox changes (C1) touch the most critical code. Keep the existing 15 outbox tests green and add the poison-entry tests first, test-driven.
- Clearing the cache on sign-out (H1) must **not** delete photos still referenced by pending entries. Test the "same account re-login sends pending work" path, which is already covered.
- Disabling backup (H6) also removes an accidental recovery path for unsent data. This is acceptable once C1 and H7 make the outbox robust.
- A foreground service (H5) needs a Play Console foreground-service declaration if the app is ever published on Play. A keep-screen-on approach avoids that.
