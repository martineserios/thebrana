# Mobile — SenseLedger Hands-On

Scaffold for the mobile-development roadmap. The actual project gets generated
by the framework CLI (so it stays canonical), but this folder holds the
decisions, conventions, and integration points that **don't** come from a
generator.

## First step: pick a framework

Make the decision before you scaffold. Both are valid — see
`learning/roadmaps/03-mobile-development.md` for the trade-off table.

- **Flutter** (this scaffold defaults here):
  ```bash
  flutter create senseledger_mobile \
    --org dev.senseledger \
    --platforms=android,ios \
    --project-name senseledger_mobile \
    app
  mv app/* app/.* . 2>/dev/null || true
  rmdir app
  ```

- **React Native** (Expo preferred for DX):
  ```bash
  npx create-expo-app@latest senseledger-mobile --template default
  mv senseledger-mobile/* senseledger-mobile/.* . 2>/dev/null || true
  rmdir senseledger-mobile
  ```

Do **not** commit the full generated project in one go. Review what the
generator produces (`ios/`, `android/`, `lib/`, `package.json`, etc.), delete
what you don't need, and commit the trimmed starting point.

## What's in this folder (curated, not generated)

```
mobile/
├── README.md                ← you are here
├── ARCHITECTURE.md          ← architecture decisions you write up front
├── FEATURES.md              ← per-feature slice notes tied to roadmap scenarios
├── api-contracts/           ← OpenAPI / .proto files for the ingest/query APIs
│   └── ingest-v1.yaml
└── fastlane/                ← once you reach scenario 8 — release automation
```

## Architecture decisions to make up front

Record each of these in `ARCHITECTURE.md`:

1. **State management**: Riverpod (recommended for Flutter) or Bloc. For RN: Zustand, Redux Toolkit, or Jotai.
2. **Navigation**: `go_router` (Flutter) or `expo-router` (RN).
3. **Local storage**: drift (Flutter) or WatermelonDB / op-sqlite (RN).
4. **Networking**: dio (Flutter) or ky/fetch (RN). Interceptors for auth, retries, offline queue.
5. **Wallet**: custodial (local key in secure storage) or WalletConnect. Scenario 5 walks through both.
6. **Crash reporting**: Sentry (works for both).
7. **CI**: GitHub Actions with self-hosted runners (for iOS builds) or EAS Build (Expo).

## Feature slices

Each roadmap scenario produces a "feature slice" that gets its own folder
inside the real project (once generated), e.g. `lib/features/sampling/`.
Track them in `FEATURES.md` with:

- The roadmap scenario it comes from
- The API endpoints it hits
- The permissions it needs
- Its dependencies on other slices

Writing this index-first makes dependencies visible before they bite you.

## Integration boundary

The mobile app talks to exactly **three** external things:

1. The ingest API on k8s — versioned REST under `/ingest/v1/*`. Schema in `api-contracts/ingest-v1.yaml`.
2. The query API on k8s — for reading history, rewards, leaderboards.
3. The Ethereum RPC / WalletConnect — for reading balances, signing, voting.

Anything else routed through the app belongs behind one of those three. No
direct mobile → database, ever.

## Testing posture

- **Unit tests** for pure logic (reducers, view models, parsing, validation).
- **Widget / component tests** for isolated UI.
- **Golden / snapshot tests** for critical screens.
- **Integration tests** running against a mock server *and* (separately) against the real dev backend.
- **Manual on-device testing** on at least: one low-end Android, one recent Android, one iPhone from the last 3 generations.

## Release gates

Before cutting a TestFlight / Play Internal build:

- [ ] Crash-free session rate > 99% in the last dev run.
- [ ] All permissions have a human explanation in the UI and in the Info.plist / AndroidManifest.
- [ ] App works fully offline for 1 hour, then syncs cleanly when online.
- [ ] Wallet flows tested against Sepolia with a throwaway wallet.
- [ ] No hardcoded secrets, endpoints, or feature flags in committed code.
