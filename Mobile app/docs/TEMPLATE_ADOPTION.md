# RIDC Flutter template adoption

The user requested that the supplied template be used to continue the existing RoadGuard app. The source was inspected read-only at `/home/egovirdc/Desktop/flutter_template`, revision `797af815d4e8fe7190382b47cf0f9b8693308261`, after the remote repository connection failed. Its existing uncommitted change to `lib/shared/providers_list.dart` was left untouched. The working application remains in this RoadGuard directory; no remote push is part of this adoption.

## Concrete mapping

| Template convention | RoadGuard implementation |
|---|---|
| `lib/app.dart` application wrapper | `RoadGuardApp` retains Material 3, persisted appearance, the supplied palette and lifecycle audio handling. |
| `core/routes/app_router.dart` composes module routes | Riverpod-owned GoRouter composes RoadGuard routes with persisted onboarding guards and existing navigation behavior. |
| Module `routes/*_paths.dart` and `*_routes.dart` | Boarding, home, planner, trips, reports and profile own their path constants and route builders. Detail-path helpers encode IDs. |
| Module `presentation/pages` | Existing RoadGuard onboarding, Explore, planner, trips, reporting and profile screens live in their corresponding modules. |
| Feature state near presentation | Riverpod controllers/providers live in module `presentation/providers` directories where needed. |
| `core/injection/injection_container.dart` | RoadGuard initializes settings, SQLite and restored trip state for Riverpod overrides; service declarations live in `service_providers.dart`. |
| `shared/providers_list.dart` | Exports Riverpod infrastructure and module providers for application composition. |
| `shared/widgets` | Existing reusable RoadGuard components and map illustration. |

The former `lib/app/*.dart`, `lib/features/*` and `lib/core/widgets/*` files remain as compatibility exports. Existing callers and tests can retain their import paths; there is one implementation of each screen and provider. Domain policy, repositories, native services and storage stay under `core`.

## Retained behavior and boundaries

Riverpod remains the sole state and dependency-injection framework, as requested for RoadGuard. The template's Provider/GetIt structure is translated into Riverpod providers and `ProviderScope` overrides. Package name, application ID, native customizations, dependency constraints and generated lockfile are retained.

Startup still loads persisted settings and active trips before rendering. Storage errors retain the retry screen without wiping data or falling back to temporary storage. Reporting keeps the strict GPS stationary gate, freshness/lifecycle checks, save-time recheck, photo sanitation and explicit demo/local-only labeling. The architecture change does not enable background collection or authenticated features.

The following template content is not integrated:

- School-bus onboarding, signup and FAQ operations: these belong to another product and are not a supplied RoadGuard identity or GraphQL contract.
- Google Maps example and its automatic startup permission request: RoadGuard still uses clearly labeled sample map/route data. A licensed provider and real routing integration remain open.
- Disabled device-security branch (`if (false)`) and notification placeholder: neither establishes a working security control or notification service.
- Template dependency list and native shells: copying these would add unused frameworks/services and replace established app configuration without an implementation need.
- Counter smoke test referencing `MyApp`: the inspected template entry point defines `AppWrapper`, and the counter assertions do not describe RoadGuard behavior. RoadGuard's actual safety, persistence and journey tests remain the validation basis.

No credentials, GraphQL operations, authentication success, live routing or server submissions are inferred from the template. Existing SRS ambiguities remain unresolved. The source template itself was inspected, not certified as compiling. Executed checks and device/build results for RoadGuard are recorded separately in [VALIDATION.md](VALIDATION.md).
