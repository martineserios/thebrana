# Mobile Architecture (SenseLedger)

> Fill this in at the start of scenario 1 and keep it current. This doc is the single source of truth for mobile-side decisions.

## Framework choice

- **Chosen:** _TBD (Flutter or React Native)_
- **Rationale:** _one paragraph — why this over the other_
- **Revisit trigger:** _what would make us change?_

## Layers

```
presentation (widgets / screens)
    │
    ▼
application (view models, use cases)
    │
    ▼
domain (entities, value objects, repositories as interfaces)
    │
    ▼
infrastructure (API clients, DB, wallet, sensors)  → external world
```

- Presentation never imports infrastructure directly.
- Domain has no dependency on any framework or package.
- Infrastructure implements interfaces defined in domain.

## State management

- **Chosen:** _TBD_
- **Conventions:**
  - All async state goes through a typed `AsyncValue` / `Result` pattern (loading / data / error).
  - View models never swallow errors. Every error must hit the UI or a Sentry event.
  - No direct mutation of state outside the view model layer.

## Navigation

- **Chosen:** _TBD_
- **Conventions:**
  - Deep links: `senseledger://dao/proposals/<id>`, `senseledger://wallet`, `senseledger://sampling`.
  - Protected routes (sampling, wallet, DAO) require onboarding complete + permissions granted.
  - No navigation from widgets; navigation calls live in view models or explicit handlers.

## Data flow (reading capture → backend)

1. Sensor tick → local queue (sqlite) with `synced = false`.
2. Background sync worker polls the queue every N seconds when online.
3. Sync worker batches into a single POST to `/ingest/v1/readings`.
4. On 2xx, rows are marked `synced = true`.
5. On 4xx, row is marked `rejected` with error code, surfaced to the user.
6. On 5xx / network errors, backoff and retry (exponential, capped).

No reading should ever be lost to an app crash or force-kill.

## Secrets and identity

- Device fingerprint: derived from stable device identifiers, **hashed** before leaving the device. Never sent raw.
- Local keystore entry per user: holds the (optional) custodial key.
- No server-issued tokens persisted in plain SharedPreferences / AsyncStorage. Use Keychain / Android Keystore.
- All network calls go over HTTPS with SSL pinning to the k8s ingress cert.

## Observability

- Sentry for crashes + errors + performance traces.
- Custom events for: onboarding completed, first sample, first sync, first reward claimed, first vote cast.
- No PII in events. Ever.

## Open decisions (track and resolve)

- [ ] Custodial wallet vs WalletConnect for scenario 5
- [ ] Background sampling cadence for battery-friendly mode
- [ ] Which OTel exporter to use (or just Sentry performance)
- [ ] Store credentials for iOS — personal Apple account vs org account
