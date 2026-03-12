# Oracle Cloud Free Tier — Personal Bot Deployment

## Context

The Personal OS Telegram bot (`~/enter_thebrana/personal/bot.py`) needs to run 24/7 but the desktop isn't always on. Oracle Cloud Free Tier offers a genuinely free ARM instance. Deployment is automated via an OCI CLI shell script (not Terraform — simpler for a single VM).

**What we're deploying:**

| Component | Detail |
|-----------|--------|
| Bot | `bot.py` — Telegram polling, journal capture, morning prompts |
| Runtime | Python 3.13 via `uv`, deps in `pyproject.toml` |
| Secret | `TELEGRAM_BOT_TOKEN` in `.env` |
| Storage | Journal markdown files on local disk, backed up via git-sync cron |
| Hosting | Oracle Cloud Free Tier ARM instance |

## Why Oracle Cloud Free Tier

| Criteria | Oracle Free Tier | Alternatives |
|----------|-----------------|--------------|
| **Cost** | $0 forever (not trial) | Fly.io/Render: free tier kills idle processes |
| **Uptime** | VM is always on | PaaS free tiers sleep after inactivity |
| **Resources** | 4 OCPU, 24 GB RAM (ARM) | Most free tiers: 256-512 MB |
| **Polling support** | Yes — full VM, any process | Many PaaS force webhooks (need domain + HTTPS) |
| **SSH access** | Full root | PaaS: no shell access |
| **Persistence** | Local disk survives reboots | PaaS: ephemeral filesystems |

We use 1 OCPU + 6 GB (of the 4+24 free budget), leaving headroom for future services.

### OCI Idle Reclamation Risk (mitigated)

OCI marks Always Free instances as "idle" if CPU averages <15% over 7 days. Mitigations:
1. **Git-sync cron** — journals push to git every hour. If VM is reclaimed, data survives.
2. **CPU heartbeat cron** — lightweight work every 5 min to keep CPU average above threshold.

## Why Shell Script (not Terraform)

Single long-lived VM — shell script is more honest than 5 Terraform files + state management.

## Why systemd (not Docker)

Single Python file with two pip deps. Docker adds Dockerfile maintenance, ARM image builds, and container runtime RAM for zero benefit. Systemd gives `Restart=always`, `journalctl`, `EnvironmentFile`, and boot-start.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              ORACLE CLOUD (Free Tier)                   │
│                                                         │
│  ┌─── VCN (10.0.0.0/16) ────────────────────────────┐  │
│  │  ┌─── Public Subnet (10.0.0.0/24) ────────────┐  │  │
│  │  │  ┌─── ARM Instance (1 OCPU / 6GB) ───────┐ │  │  │
│  │  │  │  Ubuntu 24.04 aarch64                   │ │  │  │
│  │  │  │  systemd: personal-bot.service          │ │  │  │
│  │  │  │    └── uv run python bot.py             │ │  │  │
│  │  │  │        ├── Telegram API (polling)       │ │  │  │
│  │  │  │        └── journal/YYYY-MM-DD.md        │ │  │  │
│  │  │  │  cron: git-sync (hourly) + heartbeat    │ │  │  │
│  │  │  └─────────────────────────────────────────┘ │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  │  Security: SSH in, all out. Internet Gateway.      │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## File Structure

```
personal/deploy/
├── deploy.sh                   ← OCI CLI: VCN, subnet, IGW, instance
├── setup.sh                    ← VM bootstrap: uv, botuser, systemd, crons
├── teardown.sh                 ← reverse destroy
├── personal-bot.service        ← systemd unit
└── config.env.example          ← template: OCI creds + bot token
```

## Deployment

```bash
cd personal/deploy
cp config.env.example config.env  # fill in values
./deploy.sh                       # creates infra → outputs IP
./setup.sh <IP>                   # bootstraps VM → bot starts
```

## Day-to-day

| Task | Command |
|------|---------|
| Check status | `ssh ubuntu@<ip> sudo systemctl status personal-bot` |
| View logs | `ssh ubuntu@<ip> sudo journalctl -u personal-bot -f` |
| Update bot | `ssh ubuntu@<ip> "cd /opt/personal-bot && git pull && sudo systemctl restart personal-bot"` |
| Destroy | `./teardown.sh` |

## Security

- SSH-only ingress (bot polls outbound, no inbound needed)
- Non-root service user (`botuser`)
- `.env` written by setup.sh, never in git
- Deploy key (read-write) for git-sync — no PAT, no user credentials

## Phase 0 → Phase 1

Same VM, same service. Phase 1 adds: Brana reads journals from git, weekly review automation, more prompt modes, CI/CD on push.
