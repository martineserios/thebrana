# Mobile Development Roadmap

> Intermediate, practical. Goal: a real mobile app that does background sensor sampling, talks to the SenseLedger backend, holds a wallet, and lets users vote in the DAO — released to at least internal TestFlight / Play Internal Testing.

## Framework choice: Flutter (recommended) or React Native

Both are fine. Pick one and commit — you don't have time to learn both deeply in this roadmap. Brief trade-off:

| | Flutter | React Native |
|---|---------|--------------|
| Language | Dart | TypeScript |
| UI | Own rendering engine (Skia/Impeller), pixel-perfect identical across platforms | Native components via bridge, platform-idiomatic look |
| Ecosystem | Tight, curated (pub.dev), fewer 3rd-party footguns | Huge, chaotic, lots of web overlap |
| Blockchain libs | `web3dart`, `walletconnect_flutter_v2` — works but smaller community | `ethers.js`, `wagmi`, `@walletconnect/react-native` — richer ecosystem |
| Sensor access | `sensors_plus`, `geolocator`, `flutter_blue_plus` — solid | `react-native-sensors`, `@react-native-community/geolocation`, `react-native-ble-plx` |

**Recommendation**: Flutter if you want single-codebase polish and faster compile. React Native if you want to leverage JS/TS skills and a larger web3 ecosystem.

The rest of this doc uses **Flutter** as the default. Mentally substitute for RN where needed — the concepts are identical.

## Mental model first

1. **Mobile is a hostile environment.** No network, bad network, low battery, backgrounded, killed by OS, permissions revoked, storage full, OS version fragmentation.
2. **The UI thread is sacred.** Anything > 16ms on the UI thread is jank. Heavy work goes off-thread (isolates in Flutter, native modules or worklets in RN).
3. **Local-first is the default.** Persist locally, sync when possible. The network is a nice-to-have, not a precondition.
4. **Permissions are UX, not plumbing.** The "why do we need this?" moment determines your consent rate.
5. **Release is the hardest step.** Code signing, provisioning profiles, store review, crash reporting, staged rollouts — plan for all of them from day one.

## Core surface area

| Area | What to know |
|------|--------------|
| Architecture | Feature-first folder structure, DI (get_it or Riverpod), Clean-ish separation of data/domain/presentation |
| State | Riverpod (recommended) or Bloc. Understand reactive state, async state, error states |
| Navigation | `go_router` with deep links and protected routes |
| Data | `drift` or `sqflite` for local SQL, `hive` or `isar` for key-value, `http`/`dio` for REST, `grpc`/`connectrpc` for bidi |
| Offline-first | Optimistic UI, conflict resolution, background sync, retry queues |
| Platform | Method channels (Flutter) or native modules (RN) for things no package covers |
| Sensors | accelerometer, gyroscope, magnetometer, microphone RMS, GPS, BLE (for external air quality sensors) |
| Background | WorkManager (Android) / BGTaskScheduler (iOS). Understand the OS constraints — you don't own the CPU in background. |
| Security | Keystore / Keychain for secrets, SSL pinning, root/jailbreak detection (optional), obfuscation |
| Testing | Widget tests, golden tests, integration tests (`integration_test`), device farm runs |
| Release | Fastlane, app signing, TestFlight / Play Internal, staged rollouts, crash reporting (Sentry/Crashlytics) |

## Scenarios

### Scenario 1 — Project scaffold and architecture skeleton

- Scaffold a Flutter app (`flutter create senseledger_mobile --org dev.senseledger`).
- Set up a feature-first structure: `lib/features/{onboarding,sampling,dashboard,wallet,dao}/`.
- Add Riverpod, go_router, dio, drift, freezed/json_serializable.
- Write one end-to-end vertical slice: a "Readings" screen that loads mock data from a repository → view model → widget. Tests for each layer.
- **Exit criteria**: `flutter test` green, hot reload working, CI running tests on every push.

### Scenario 2 — Sensor sampling with permissions

- Permissions flow: explain → request → handle denial → settings fallback. Use `permission_handler`.
- Sample accelerometer + gyroscope + mic RMS at 50Hz for 10 seconds. Display live values.
- Persist sessions to local SQLite (drift).
- **Exit criteria**: User can record a sampling session, see live values, review history. Permissions feel humane.

### Scenario 3 — Background sampling

- Schedule a background task every 15 minutes that samples briefly and queues results.
- Handle the OS constraints: iOS will throttle hard, Android has Doze mode.
- Add a "battery-friendly mode" toggle that reduces frequency.
- **Exit criteria**: App samples passively for a full day without killing battery; sampled data survives app kill and reboot.

### Scenario 4 — Networking and offline sync

- Point the app at the k8s-hosted ingest API (from the k8s roadmap).
- Build a retry queue: failed uploads are persisted and retried with exponential backoff.
- Add a clear online/offline indicator.
- Handle server errors distinctly from network errors.
- **Exit criteria**: Airplane mode for an hour, return to online — all data arrives at the backend exactly once.

### Scenario 5 — Wallet integration

- Integrate a wallet. Two options:
  - **Custodial-ish**: Generate a local keypair, store in secure storage, use `web3dart` to sign. Simpler, educational, not great UX.
  - **WalletConnect**: User brings their own wallet (Metamask Mobile, Rainbow), WC handles signing. Better UX, more moving parts.
- Show the user's SENSE token balance (read from the token contract on Sepolia).
- Show their rewards history (from event logs or the wallet bridge API).
- **Exit criteria**: App shows current balance and updates after a reward is minted. Test with a testnet wallet.

### Scenario 6 — DAO voting UI

- List active proposals from the SenseDAO contract.
- Show current vote tally and the user's voting power.
- Let the user cast a vote (signed tx via the wallet integration).
- Handle pending / confirmed / failed transaction states.
- **Exit criteria**: User can see and vote on a real proposal you created from the blockchain roadmap.

### Scenario 7 — Observability and crash reporting

- Integrate Sentry for crashes, errors, and performance traces.
- Add OpenTelemetry (or use Sentry's tracing) for key user journeys: onboarding, sampling, sync.
- Add custom metrics: sampling sessions per day, sync failures, permission grants.
- **Exit criteria**: You can see a user's journey through a failure in one dashboard, from tap to stack trace.

### Scenario 8 — Release pipeline

- Set up Fastlane with lanes for `ios_beta`, `android_beta`, `ios_release`, `android_release`.
- Automate version bumping, build, upload to TestFlight / Play Internal.
- Wire Fastlane into CI (GitHub Actions). Tag a release → CI builds and ships.
- Staged rollout: 10% → 50% → 100% over a week.
- **Exit criteria**: Cut a release with one git tag; beta testers get it without you touching a console.

## Where this feeds SenseLedger

| Mobile deliverable | SenseLedger piece |
|--------------------|-------------------|
| Scenario 2–3 | The actual data source for the pipeline |
| Scenario 4 | Production client for the k8s-hosted ingest API |
| Scenario 5 | Gateway into the on-chain reward system |
| Scenario 6 | Governance participation — closes the loop back into the validation config |
| Scenario 7 | Field telemetry for everything upstream |

## Resources

- `docs.flutter.dev` — official docs. Start with the architectural samples.
- `riverpod.dev`
- `pub.dev` — package search. Favor official / well-maintained packages (green "verified publisher" badge, recent updates).
- `docs.walletconnect.com`
- `developer.apple.com/documentation/backgroundtasks`
- `developer.android.com/topic/performance/power/power-details`
- `sentry.io/for/flutter`
- If React Native: `reactnative.dev`, `wagmi.sh`, `reactnavigation.org`

## Anti-patterns to avoid

- Shipping without crash reporting. You will not find out about crashes from the store.
- Storing secrets in SharedPreferences / AsyncStorage. Use Keychain/Keystore.
- Network calls from widgets directly. Route everything through repositories / use-cases.
- Ignoring accessibility. Screen readers, font scaling, contrast, tap target size — all first-class.
- Treating the app as "release-ready" before you've tested on 3+ real devices and at least one old phone.
- Running your own Ethereum node in the app. Use a hosted RPC (Alchemy, Infura) with rate limiting and fallbacks.

## Done when

- A real person can install the app, grant permissions, sample data, see their balance, vote on a proposal, and hit "upload" — all of this working against the live SenseLedger backend on Sepolia + k8s.
- The app survives a week in internal testing without a P0 crash.
- You have numbers for battery impact, sync reliability, and permission grant rate.
