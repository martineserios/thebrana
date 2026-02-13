# Google Sheets MCP Integration Guide

How to connect Google Sheets to brana's venture skills via MCP (Model Context Protocol).

---

## 1. Overview

Google Sheets is the default operational data store for early-stage ventures. Connecting it via MCP lets venture skills read and write directly to spreadsheets — no copy-paste, no CSV exports.

**What this enables:**
- `/growth-check` reads metrics directly from Sheets
- `/monthly-close` pulls financial data from P&L tabs
- `/pipeline` syncs deal data with CRM spreadsheets
- `/financial-model` reads actuals and writes projections
- `/morning` shows live metric snapshots

**Without MCP:** Skills work fine — you provide data during conversation, or skills read from `docs/` markdown files.
**With MCP:** Skills read/write Sheets directly, reducing manual data entry.

---

## 2. Prerequisites

1. **Google Cloud Project** — create one at [console.cloud.google.com](https://console.cloud.google.com)
2. **Enable APIs:**
   - Google Sheets API
   - Google Drive API (for file discovery)
3. **OAuth2 credentials:**
   - Create OAuth 2.0 Client ID (Desktop application type)
   - Download the credentials JSON file
   - Store it securely (e.g., `~/.config/google/oauth-credentials.json`)
4. **Node.js** installed (for MCP server packages)

---

## 3. MCP Server Options

### Option A: Google Workspace MCP (Full Suite)

**Source:** [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)

Covers Sheets, Drive, Calendar, Gmail, Docs, Slides, Chat, Tasks. Best if you want calendar integration with `/morning` too.

**Tools provided:** `sheets_read`, `sheets_update`, `sheets_create`, `drive_search`, `calendar_list_events`, and more.

### Option B: MCP Google Sheets (Sheets-Only)

**Source:** [xing5/mcp-google-sheets](https://github.com/xing5/mcp-google-sheets)

Lighter footprint — Sheets only. Best if you only need spreadsheet access.

**Tools provided:** `read_sheet`, `write_sheet`, `create_sheet`, `list_sheets`.

### Recommendation

Start with Option A if you also want calendar integration (for `/morning`). Use Option B if you want minimal setup and only need Sheets.

---

## 4. Configuration

Add to your project's `.mcp.json` or global `~/.claude/settings.json`:

### Option A: Google Workspace MCP

```json
{
  "mcpServers": {
    "google-workspace": {
      "command": "/absolute/path/to/google-workspace-mcp",
      "args": ["--credentials", "/home/you/.config/google/oauth-credentials.json"]
    }
  }
}
```

### Option B: MCP Google Sheets

```json
{
  "mcpServers": {
    "google-sheets": {
      "command": "node",
      "args": ["/absolute/path/to/mcp-google-sheets/dist/index.js"],
      "env": {
        "GOOGLE_CREDENTIALS_PATH": "/home/you/.config/google/oauth-credentials.json"
      }
    }
  }
}
```

**Important:** Use absolute paths to binaries, not `npx`. See thebrana MEMORY.md for rationale.

---

## 5. First-Run Auth Flow

1. Start a Claude Code session with the MCP server configured
2. Call any Sheets tool (e.g., try to read a spreadsheet)
3. The MCP server opens a browser window for Google OAuth consent
4. Authorize the application
5. A refresh token is saved locally — subsequent sessions authenticate automatically

**Troubleshooting:**
- If the browser doesn't open, check terminal output for the auth URL
- If you get "insufficient permissions," verify both Sheets API and Drive API are enabled
- Token files are typically saved alongside the credentials file

---

## 6. Skills That Benefit

| Skill | Without MCP | With MCP |
|-------|-------------|----------|
| `/growth-check` | Asks user for metric values during conversation | Reads metrics directly from designated Sheets tab |
| `/monthly-close` | User provides P&L data verbally | Reads P&L from financial workbook, writes close summary |
| `/pipeline` | Markdown-only pipeline in `docs/pipeline/` | Syncs with CRM spreadsheet, reads/writes deal records |
| `/financial-model` | Builds model from conversation input | Reads actuals from Sheets, writes projections back |
| `/morning` | No live metrics — uses last stored snapshot | Reads today's metrics from dashboard tab |
| `/weekly-review` | Manual metric collection | Auto-pulls week's metrics for delta comparison |
| `/monthly-plan` | Reads from `docs/` markdown files only | Reads live data from Sheets for more current planning |
| `/experiment` | Manual result collection | Reads experiment metrics from tracking tab |

---

## 7. Psilea-Specific Mapping

For the Psilea project (Google Sheets with `setup.gs` deployed), this maps existing tabs to skill fields:

| Sheet Tab | Skill | Field Mapping |
|-----------|-------|--------------|
| **CLIENTES** | `/growth-check`, `/pipeline` | Active clients → customer count, acquisition metrics |
| **VENTAS** | `/monthly-close`, `/growth-check` | Sales → revenue, deal count, conversion |
| **CAJA** | `/monthly-close`, `/financial-model` | Cash flow → cash on hand, burn rate, runway |
| **PYL** (P&L) | `/monthly-close` | Profit & Loss → revenue, COGS, expenses, net income |
| **SERVICIOS** | `/pipeline`, `/experiment` | Services → product catalog, pricing, utilization |

### Spreadsheet ID

Once you have the MCP server configured, you'll need the spreadsheet ID. Find it in the Google Sheets URL:

```
https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/edit
```

Skills reference sheets by tab name within the spreadsheet.

---

## 8. Manual vs Automatic

| Task | Manual (you do) | Automatic (MCP does) |
|------|----------------|---------------------|
| Set up Google Cloud project | Yes | — |
| Enable APIs | Yes | — |
| Create OAuth credentials | Yes | — |
| Configure `.mcp.json` | Yes | — |
| First-time auth consent | Yes | — |
| Read metrics during `/growth-check` | — | Yes |
| Write close report to Sheets | — | Yes |
| Sync pipeline deals | — | Yes |
| Read calendar for `/morning` | — | Yes (Option A only) |
| Refresh auth token | — | Yes (automatic) |

**Bottom line:** 5 one-time manual steps, then everything is automatic.

---

## Cross-References

- [venture-guide.md](../venture-guide.md) — full skill usage guide
- Doc 34 (34-venture-operating-system.md in enter repo) — MCP server research and priority tiers
- [skill-catalog.md](../skill-catalog.md) — all available skills
