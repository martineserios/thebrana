---
name: meta-verification
description: "Meta Business Verification — full recipe for verifying a business on Meta Business Manager for WABA access. Covers prerequisites, document submission, post-approval steps, and account hygiene. Cross-pollinated from somos_mirada."
effort: medium
argument-hint: "[check|submit|audit] [phase]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
  - WebFetch
  - WebSearch
---

# Meta Business Verification

End-to-end recipe for verifying a business on Meta Business Manager. Covers the full lifecycle: prerequisites, document preparation, submission, post-approval steps, WABA setup, and ongoing account hygiene.

Based on battle-tested execution with somos_mirada (2026-02) and nexeye (2026-03).

## When to use

- Setting up a new Meta Business Manager for a client
- Verifying an existing unverified business on Meta
- Auditing an existing BM against the 27-item checklist
- Preparing for WABA (WhatsApp Business API) access
- Display Name verification after BV approval

**Invocation:**
- `/brana:meta-verification` — interactive: assess current state, recommend next step
- `/brana:meta-verification check` — audit BM against checklist, report gaps
- `/brana:meta-verification submit` — guided document preparation + submission flow
- `/brana:meta-verification audit` — full 27-item account hygiene audit

---

## Overview — 6 Phases

```
Phase 1: Prerequisites & Document Collection     (client provides docs)
Phase 2: Security & Access Audit                  (2FA, user cleanup, min 2 admins)
Phase 3: Business Verification Submission         (docs → Meta, 2-14 business days)
Phase 4: Post-Approval                            (Display Name, WABA, phone registration)
Phase 5: Domain, Assets & Billing                 (pixel, domain verify, asset linking)
Phase 6: Messaging Optimization                   (templates, warming, deliverability)
```

---

## Phase 1 — Prerequisites & Document Collection

### Required documents

The client must provide **all 3** before Phase 3 can begin:

| # | Document | Purpose | Format | Notes |
|---|----------|---------|--------|-------|
| 1 | **Tax registration certificate** | Proves legal entity | PDF or JPG | Argentina: Constancia de inscripción ARCA (ex-AFIP). Must be **current** (not expired). Download from arca.gob.ar with CUIT + clave fiscal — takes 2 minutes. |
| 2 | **Government-issued ID of BM admin** | Proves who is submitting | JPG (front + back) | The name on the ID must match the admin's name in Meta BM. Argentina: DNI. Convert PDF to JPG: `pdftoppm -jpeg -r 300 input.pdf output` |
| 3 | **Privacy policy** | Legal compliance | Published URL | Must be live on the business website and accessible from ads. If it doesn't exist, create one before submitting. |

### Additional documents (may be requested by Meta)

| Document | When needed |
|----------|-------------|
| Contrato social / articles of incorporation | If tax cert alone doesn't satisfy Meta |
| Utility bill or bank statement | If Meta needs additional address proof (must show business name + address) |
| Health/aesthetics sector policies | If the business operates in regulated sectors |

### The #1 Rule: Address & Name Consistency

**This is the single most common rejection reason.** Every document submitted must match exactly:

- **Legal name**: abbreviations, accents, spacing, punctuation must be identical across all documents AND the BM form. `NEXEYE TECHNOLOGIES S.R.L.` ≠ `Nexeye Technologies SRL` ≠ `NEXEYE TECHNOLOGIES S. R. L.`
- **Address**: street, floor, apartment, postal code, city — exact match. `Piso 10` ≠ `Piso:10`. `Dpto D` ≠ `Dpto:D`.
- **If multiple tax certificates exist** with different addresses, use only the one that matches the admin's ID domicile.

### Pre-submission checklist

Before moving to Phase 3, verify ALL of these:

- [ ] Fresh tax certificate (not expired)
- [ ] Admin ID (front + back, JPG, not expired)
- [ ] Privacy policy live on website
- [ ] Legal name on BM matches documents exactly
- [ ] Address on BM matches documents exactly
- [ ] Business phone number is real and reachable
- [ ] Contact email is domain-based (not Gmail/Hotmail personal)
- [ ] Website URL matches verified domain

---

## Phase 2 — Security & Access Audit

Complete this BEFORE submitting verification. A clean security posture signals trust to Meta.

### 2.1 User cleanup

1. List all users with BM access — note role, last active date
2. Remove inactive users, ex-employees, duplicate accounts
3. Reassign assets (pages, ad accounts, catalogs) from removed users to active admins
4. Confirm minimum **2 active administrators** remain

### 2.2 Two-Factor Authentication (2FA)

**Non-negotiable.** No 2FA = higher restriction risk, blocks WhatsApp Business app install.

1. Prepare per-user checklist: current role, assets managed, 2FA status
2. **In-person session recommended** (~2 hours): each person activates 2FA on their Facebook account with their own device
3. Store backup codes securely
4. Verify all users show 2FA active in BM → Settings → Security Center

### 2.3 Organization & Documentation

1. **Activate Security Center** in BM — enable email alerts
2. **Rename assets** with consistent nomenclature: `{BUSINESS}-Page-Main`, `{BUSINESS}-Pixel-Tracking`, etc.
3. **Create access map document:**
   - User name | Role | Assets assigned | 2FA status | Last active
4. **Link corporate email** to BM (domain-based, not personal Gmail)
5. **Create backup document:**
   - Business Manager ID
   - Primary admin email
   - Verified domain
   - Pixel ID
   - Ad account ID
   - Payment methods on file

---

## Phase 3 — Business Verification Submission

### Flow in Meta

1. **Go to** Business Manager → Settings → Security Center → Business Verification
2. **Select business type**: Sole Proprietorship, Corporation, etc.
3. **Fill business details** (must match documents exactly):
   - Legal business name
   - Alternative/trading name (DBA)
   - Full address (no abbreviations)
   - Business phone number
   - Business email (domain-based)
   - Website URL
4. **Upload documents:**
   - Tax registration certificate (ARCA constancia / equivalent)
   - Admin ID — front (JPG)
   - Admin ID — back (JPG)
5. **Accept sector-specific policies** if prompted (health, aesthetics, finance)
6. **Complete contact verification** — choose one:
   - **Business phone**: receive code via call or SMS
   - **Business email**: receive code via email (recommended if domain email works)
   - **Domain verification**: prove ownership of business domain
7. **Submit** and wait

### Timeline

- **Processing:** 2–14 business days (typical: 3-5 days)
- **Status visible** in Security Center
- **Email notification** on approval or rejection

### If rejected

1. Read the rejection reason carefully
2. Most common: name/address mismatch between docs and form
3. Correct the discrepancy
4. Re-submit (no penalty for re-submission)
5. If rejected twice: contact Meta Business Support directly

---

## Phase 4 — Post-Approval

### 4.1 Display Name Verification

Separate step, only available after BV is approved. Takes 1-2 additional business days.

1. Go to WhatsApp Manager → Phone Numbers
2. Click the phone number → Request Display Name Verification
3. Enter verified business name
4. Submit and wait 1-2 business days

**Impact:** Users see the verified business name instead of just a phone number.

### 4.2 WABA Creation

1. Create WhatsApp Business Account in BM
2. Associate with the verified business
3. Configure webhook URL (if using API directly)
4. Set up system user for API access

### 4.3 Phone Number Registration

**Critical rules:**
- **Avoid VoIP numbers** — Meta blocks them
- **10-attempt limit per 72h rolling window** with escalating cooldowns
- Dedicated SIM card recommended (not shared with personal use)
- Number must be able to receive SMS or voice calls for verification
- Number cannot be currently registered on regular WhatsApp — must be deregistered first

**Process:**
1. Insert SIM in a phone, verify it can receive SMS
2. In WhatsApp Manager → Phone Numbers → Add Phone Number
3. Enter the number with country code
4. Choose verification method: SMS (recommended) or voice call
5. Enter the 6-digit code
6. If SMS fails, wait and try voice call
7. **Do not burn attempts** — if it fails twice, wait 24h before retrying

### 4.4 Message Limit Progression

After verification, limits increase progressively based on quality:

| Tier | Daily limit | How to reach |
|------|-------------|--------------|
| Unverified | 250 messages/day | Default |
| Verified | 1,000 messages/day | After BV approval |
| Tier 2 | 10,000 messages/day | Maintain high quality rating |
| Tier 3 | 100,000 messages/day | Sustained high quality + volume |
| Unlimited | No limit | Consistent excellent quality |

---

## Phase 5 — Domain, Assets & Billing

### 5.1 Domain Verification

1. Go to BM → Security Center → Domain
2. Add business domain
3. Verify via DNS TXT record or HTML file upload
4. Once verified: all tracking associated with verified domain

### 5.2 Pixel & Tracking

1. Install Meta Pixel correctly
2. Set up Conversion API if applicable
3. Configure event priorities in Events Manager
4. Create authorized domains list

### 5.3 Asset Linking

1. Assign assets: pixel → ad account, domain → BM, catalog → ad account
2. Link WhatsApp Business to BM
3. Link Instagram + Facebook Page (via desktop, NOT mobile — mobile creates wrong association)

### 5.4 Billing

1. Add payment method with available funds
2. Create ad account correctly (if needed)
3. Set spend limits to prevent unexpected charges
4. Review account status for penalties or alerts

---

## Phase 6 — Messaging Optimization

### 6.1 Template Strategy

Use `/brana:meta-template` for template creation. Key points:
- Operational messages (confirmations, instructions, reminders) → target **Utility** classification
- Marketing messages (promos, offers, newsletters) → accept **Marketing** classification
- Utility templates avoid frequency capping (#131049) and Meta experiments (#130472)

### 6.2 Progressive Warming

**Critical for new numbers.** Do not send high volume immediately.

| Week | Volume | Notes |
|------|--------|-------|
| 1 | Baseline (~50/day) | Normal operations only |
| 2 | 2x baseline | Add scheduled reminders |
| 3 | 3x baseline | Add follow-ups |
| 4+ | Full desired volume | Monitor quality metrics |

### 6.3 Deliverability

1. **Audit contact list:** remove undeliverable numbers, inactive contacts (60+ days no engagement)
2. **Validate phone format:** consistent country code, no duplicates
3. **Configure automatic retry** for failed messages (15-min delay, notify on permanent failure)
4. **Monitor metrics:** delivery rate >98%, failure rate <1%, watch for error codes #131049 / #130472

### 6.4 Auto-Responses

1. Set up away messages (business closed hours)
2. First-response template (acknowledgment)
3. Instagram auto-replies if applicable

---

## 27-Item Checklist

Use this for auditing an existing BM (`/brana:meta-verification audit`).

### Security & Access (7)
- [ ] 2FA on BM and all personal accounts with access
- [ ] Minimum 2 admins in Business Manager
- [ ] Audit and clean user access (remove inactive/departed)
- [ ] Activate Security Center
- [ ] Corporate email linked (not personal Gmail)
- [ ] Email alerts enabled
- [ ] Backup doc: BM ID, pixel ID, domain, payments, admin contacts

### Verification & Business Data (5)
- [ ] Business name verified (matches legal docs exactly)
- [ ] Business verified in Meta (Security Center)
- [ ] Business info complete (address, contact, website)
- [ ] Legal docs uploaded (privacy policy, terms if applicable)
- [ ] Sector-specific policies accepted (health/aesthetics if applicable)

### Billing & Ads (4)
- [ ] Payment method added and verified with funds
- [ ] Ad account created correctly
- [ ] At least one campaign created (BM not "empty")
- [ ] Spend limits configured

### Domain, Pixel & Tracking (4)
- [ ] Domain verified
- [ ] Pixel installed and tested
- [ ] Conversion API configured (if applicable)
- [ ] Events Manager set up with priorities

### Assets & Linking (3)
- [ ] Assets assigned correctly (pixel, domain, catalog, page, ad account)
- [ ] WhatsApp Business linked
- [ ] Instagram + Facebook linked (via desktop, NOT mobile)

### Messaging & Automation (2)
- [ ] Auto-responses configured (WhatsApp + Instagram)
- [ ] Message center permissions and inbox assignment set

### Legal & Compliance (1)
- [ ] Privacy policy published on website and accessible from ads

### Account Health Signals (not a checkbox — ongoing)
- Verified business identity → lower restriction risk
- Active 2FA → trust signal
- Progressive volume ramp-up → signals legitimate growth
- Conversation engagement → respond to incoming, build history
- No failed sends → audit and remove bad numbers

---

## Argentina-Specific Notes

| Item | Details |
|------|---------|
| **Tax ID** | CUIT (Clave Única de Identificación Tributaria). Format: XX-XXXXXXXX-X |
| **Tax certificate** | Constancia de inscripción ARCA (was AFIP until 2025). Download from arca.gob.ar. Has expiration date — must be current. |
| **Admin ID** | DNI (Documento Nacional de Identidad). Front + back. |
| **Legal forms** | S.R.L. (Sociedad de Responsabilidad Limitada), S.A. (Sociedad Anónima), Monotributista |
| **Address format** | Include: street + number, piso, dpto, barrio, CP, ciudad. Must match DNI domicile AND ARCA exactly. |
| **Contrato social** | Articles of incorporation — may be requested as additional proof |
| **Phone numbers** | Country code +54. Avoid VoIP. Dedicated SIM recommended. |

---

## Common Pitfalls (Learned the Hard Way)

1. **Address mismatch = automatic rejection.** `Piso 10` vs `Piso:10` vs `10° piso` — Meta treats these as different. Use the exact format from the tax certificate.

2. **BM name typo.** Check the BM name BEFORE submitting. Fixing it after submission requires contacting Meta support. Example: "Neyetech" instead of "NexeyeTech".

3. **Expired tax certificate.** ARCA constancias have a vigencia period. If it expired, Meta rejects. Download a fresh one — takes 2 minutes.

4. **Google SSO blocks headless browsers.** If you need to access Meta BM or Brevo via automated browser, Google login will block you ("This browser or app may not be secure"). Use API-based approaches instead.

5. **DNI in PDF format.** Meta wants JPG uploads. Convert: `pdftoppm -jpeg -r 300 input.pdf output` produces high-res JPGs.

6. **Personal Gmail as BM contact.** Meta penalizes non-domain emails. Always use `info@domain.com` or `admin@domain.com`.

7. **Phone registration cooldown.** 10 attempts per 72h rolling window. Each failure extends the cooldown. Don't burn attempts — if SMS fails twice, wait 24h, try voice call.

8. **VoIP numbers.** Meta blocks them for WABA registration. Use a physical SIM card.

9. **Display Name ≠ Business Verification.** Display Name verification is a separate step AFTER BV approval. Takes 1-2 extra days.

10. **Multiple ARCA constancias.** If the business has multiple (e.g., different addresses), submit only the one matching the admin's DNI domicile.

11. **WhatsApp deregistration.** The phone number cannot be active on regular WhatsApp. Must deregister from WhatsApp before registering on WABA.

12. **Asset linking via mobile.** Never link Instagram/Facebook via mobile — creates wrong association. Always do it from desktop BM.

13. **Brevo domain authentication.** If using Brevo for email alongside Meta: register domain → add DKIM CNAMEs + SPF TXT → authenticate → create sender. Sequence matters when DMARC policy exists.

---

## Process

### /brana:meta-verification (interactive)

1. **Ask:** "Which phase are you at?" Present phases 1-6 with current status assessment.
2. **If unknown:** run `/brana:meta-verification check` first.
3. Based on current state, guide through the next actionable phase.

### /brana:meta-verification check

1. **Gather info via AskUserQuestion:**
   - Do you have a Meta Business Manager? (yes/no/unsure)
   - Is the business verified? (yes/no/unsure)
   - Is 2FA active on all admin accounts? (yes/no/unsure)
   - Do you have the required documents ready? (tax cert, admin ID, privacy policy)
2. **Score against the 27-item checklist** — mark known items, flag unknowns.
3. **Report gaps** and recommend next phase.

### /brana:meta-verification submit

1. **Verify Phase 1 prerequisites** — confirm all 3 documents are ready.
2. **Cross-check consistency** — legal name, address, admin name across all docs.
3. **Guide through Phase 3 submission flow** step by step.
4. **Set reminders** for follow-up (2-14 business days).

### /brana:meta-verification audit

1. **Walk through all 27 items** — ask user to confirm each.
2. **Score:** X/27 items passing.
3. **Generate remediation plan** — prioritized list of fixes.
4. **Estimate effort** per fix (from somos_mirada hourly benchmarks).

---

## Timeline Estimates (from somos_mirada)

| Phase | Active hours | Calendar time | Notes |
|-------|-------------|---------------|-------|
| 1. Prerequisites | 0 (client) | 1-3 days | Depends on client responsiveness |
| 2. Security audit | 4-6h | 1 week | Includes in-person 2FA session |
| 3. BV submission | 2-3h | 2-14 business days | Meta processing time |
| 4. Post-approval | 1-2h | 2-3 days | Display Name + phone registration |
| 5. Domain & assets | 2-3h | 1 week | Depends on domain/pixel access |
| 6. Messaging optimization | 4-5h | 2-3 weeks | Warming is calendar time, not active hours |

**Total:** ~15-20 active hours over 4-6 weeks.

Active hours exclude Meta processing time, client response time, and warming monitoring.
