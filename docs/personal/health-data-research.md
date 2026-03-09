# Health Data Tracking & Unification

**Date:** 2026-03-09
**Purpose:** Input for personal space design (input #7)

---

## Wearable Landscape

| Device | Key Metrics | Cost | API |
|--------|------------|------|-----|
| **Oura Ring** | HRV, sleep stages, body temp, readiness | $300 upfront | Limited (business partnerships) |
| **Whoop 4.0** | Strain, recovery, HRV, sleep, stress | $35/mo | Spike API (developer-friendly) |
| **Apple Watch** | HR, ECG, SpO2, steps, HRV | $250-800 | HealthKit (iOS only) |
| **Garmin** | VO2 max, training stress, recovery, HRV | $200-1000 | OAuth 2.0 (complex) |
| **Fitbit** | HR, sleep, steps, SpO2 | $100-300 | Deprecating (→ Health Connect) |

## Aggregation Tools

| Tool | Type | Best for |
|------|------|----------|
| **Apple Health** | Native iOS aggregator | Already in ecosystem |
| **Google Health Connect** | Android unified platform | Android users |
| **Gyroscope** | AI insights + coaching | Most feature-rich aggregator |
| **Exist.io** | Lightweight all-in-one | Simple correlation tracking |
| **Open Wearables** | Self-hosted, MIT licensed | Privacy-first, zero cost |
| **Spike API** | Developer API for 500+ wearables | Building custom integrations |

## Practical Minimum (80% Value)

**Pick ONE device:**
- **Oura Ring** if you want minimal intrusion (sleep/HRV/recovery focus)
- **Whoop** if you want strain/recovery + excellent API
- **Apple Watch** if already in ecosystem

**Track only 5 metrics:**
1. Sleep duration & quality (most actionable)
2. HRV (morning, 5-min measurement — recovery state)
3. Resting heart rate trend (cardiovascular macro indicator)
4. Strain/activity score (exertion vs recovery capacity)
5. Skip everything else initially (glucose, blood work, biomarkers — add only if problems emerge)

**Workflow:**
- Device syncs automatically → aggregator pulls daily
- Weekly review (5 min): HRV trend + sleep quality + activity
- Adjust training/recovery based on 2-3 week trends, not daily noise

**Cost:** $35-50/month for baseline setup.

## Quantified Self Insights

- 79% of self-trackers report gaining insights, but only 23% sustain behavior change
- Binary tracking (yes/no) for first 30 days, then expand if valuable
- 80% completion rate is sustainable; perfection fails
- Automate collection — manual logging kills consistency
- Monthly/quarterly review cycles, not daily obsession

## Privacy

**Safe to store:** Aggregated metrics (HRV trend, sleep score, activity level), self-reported lifestyle data, summary statistics.

**Don't store:** Raw diagnosis/medication data in unencrypted systems, geolocation near healthcare facilities, PII + health data in same queryable system.

**Best practice:** Self-hosted solutions (Open Wearables, Fasten Health) for sensitive data. Consumer apps for non-sensitive metrics. Encrypt at rest.

## Patterns for Personal Space

| Pattern | Application | Priority |
|---------|-------------|----------|
| Single device + auto-sync | Minimal friction data collection | High |
| 5 core metrics only | Don't overtrack | High |
| Weekly 5-min review | Trend-based, not daily noise | High |
| Self-hosted aggregation | Privacy + control | Medium |
| Binary tracking for habits | Simple yes/no before expanding | Medium |

## What NOT to Steal

- Full biohacker stack (glucose monitors, blood panels, etc.) — overkill initially
- Multiple overlapping wearables
- Daily metric obsession (leads to anxiety, not insight)
- AI-driven workout planning apps (solve a problem you don't have yet)

---

## Sources

- [Health Data Integration Guide 2026 — lifetrails.ai](https://lifetrails.ai/blog/health-data-integration-app-switching-export-guide)
- [Open Wearables — openwearables.io](https://www.openwearables.io/)
- [Spike API — spikeapi.com](https://www.spikeapi.com/integrations)
- [Gyroscope — gyrosco.pe](https://gyrosco.pe/)
- [Quantified Self & Well-being — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8493454/)
- [HRV Ultimate Guide — Marco Altini](https://marcoaltini.substack.com/p/the-ultimate-guide-to-heart-rate)
- [Health Data Privacy 2026 — bankinfosecurity.com](https://www.bankinfosecurity.com/health-data-privacy-cyber-regs-what-to-watch-in-2026-a-30320)
