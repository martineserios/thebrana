#!/usr/bin/env bash
# setup.sh — Bootstrap the VM after deploy.sh creates it
#
# Usage: ./setup.sh <PUBLIC_IP>
#
# What it does:
#   1. Installs system deps (git, curl)
#   2. Installs uv
#   3. Creates botuser service account
#   4. Copies bot files to /opt/personal-bot
#   5. Writes .env with bot token
#   6. Installs Python deps via uv
#   7. Generates deploy key for git-sync
#   8. Installs + enables systemd service
#   9. Sets up git-sync cron (hourly journal backup)
#  10. Sets up CPU heartbeat cron (anti-reclamation)

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: ./setup.sh <PUBLIC_IP>"
  exit 1
fi

PUBLIC_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSH_KEY="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"

source "$SCRIPT_DIR/config.env"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"
SSH_CMD="ssh $SSH_OPTS ubuntu@$PUBLIC_IP"
SCP_CMD="scp $SSH_OPTS"

echo "=== VM Setup ==="
echo "Target: ubuntu@$PUBLIC_IP"
echo ""

# --- Wait for SSH ---
echo "→ Waiting for SSH..."
for i in $(seq 1 30); do
  if $SSH_CMD "echo ok" >/dev/null 2>&1; then
    echo "  SSH ready"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  ERROR: SSH not available after 5 min"
    exit 1
  fi
  sleep 10
done

# --- System packages ---
echo "→ Installing system packages..."
$SSH_CMD "sudo apt-get update -qq && sudo apt-get install -y -qq git curl" >/dev/null 2>&1
echo "  Done"

# --- Install uv ---
echo "→ Installing uv..."
$SSH_CMD "curl -LsSf https://astral.sh/uv/install.sh | sh" >/dev/null 2>&1
echo "  Done"

# --- Create botuser ---
echo "→ Creating botuser..."
$SSH_CMD "sudo useradd --system --create-home --shell /bin/bash botuser 2>/dev/null || true"
echo "  Done"

# --- Copy bot files ---
echo "→ Copying bot files to /opt/personal-bot..."
$SSH_CMD "sudo mkdir -p /opt/personal-bot && sudo chown ubuntu:ubuntu /opt/personal-bot"

$SCP_CMD "$PROJECT_DIR/bot.py" "ubuntu@$PUBLIC_IP:/opt/personal-bot/"
$SCP_CMD "$PROJECT_DIR/pyproject.toml" "ubuntu@$PUBLIC_IP:/opt/personal-bot/"
[ -f "$PROJECT_DIR/uv.lock" ] && $SCP_CMD "$PROJECT_DIR/uv.lock" "ubuntu@$PUBLIC_IP:/opt/personal-bot/"
echo "  Done"

# --- Write .env ---
echo "→ Writing .env..."
$SSH_CMD "cat > /opt/personal-bot/.env <<'ENVEOF'
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN  # placeholder — value from config.env
ENVEOF"
echo "  Done"

# --- Install Python deps ---
echo "→ Installing Python dependencies..."
$SSH_CMD "cd /opt/personal-bot && /home/ubuntu/.local/bin/uv sync" 2>&1 | tail -1
echo "  Done"

# --- Create journal directory ---
echo "→ Creating journal directory..."
$SSH_CMD "mkdir -p /opt/personal-bot/journal"
echo "  Done"

# --- Generate deploy key ---
echo "→ Generating deploy key for git-sync..."
$SSH_CMD "sudo -u botuser ssh-keygen -t ed25519 -f /home/botuser/.ssh/id_ed25519 -N '' -C 'personal-bot-deploy' 2>/dev/null || true"
DEPLOY_KEY=$($SSH_CMD "sudo cat /home/botuser/.ssh/id_ed25519.pub")
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  DEPLOY KEY — Add to GitHub as deploy key       ║"
echo "  ║  (Settings → Deploy keys → Add, enable write)   ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""
echo "  $DEPLOY_KEY"
echo ""
echo "  Press Enter after adding the deploy key to GitHub..."
read -r

# --- Init git repo ---
echo "→ Initializing git repo..."
$SSH_CMD "sudo chown -R botuser:botuser /opt/personal-bot"
$SSH_CMD "sudo -u botuser bash -c 'cd /opt/personal-bot && git init && git remote add origin $GIT_REPO_URL'" 2>/dev/null || true
$SSH_CMD "sudo -u botuser bash -c 'cd /opt/personal-bot && git config user.email \"bot@personal\" && git config user.name \"personal-bot\"'"
echo "  Done"

# --- Install systemd service ---
echo "→ Installing systemd service..."
$SCP_CMD "$SCRIPT_DIR/personal-bot.service" "ubuntu@$PUBLIC_IP:/tmp/"
$SSH_CMD "sudo mv /tmp/personal-bot.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now personal-bot"
echo "  Done"

# --- Setup git-sync cron ---
echo "→ Setting up git-sync cron (hourly journal backup)..."
CRON_SYNC='0 * * * * cd /opt/personal-bot && git add journal/ && git diff --cached --quiet || git commit -m "journal sync $(date +\%F-\%H\%M)" && git push origin main 2>/dev/null'
$SSH_CMD "sudo -u botuser bash -c '(crontab -l 2>/dev/null; echo \"$CRON_SYNC\") | crontab -'"
echo "  Done"

# --- Setup CPU heartbeat cron ---
echo "→ Setting up CPU heartbeat cron (anti-reclamation, every 5 min)..."
CRON_HEARTBEAT='*/5 * * * * find /opt/personal-bot -name "*.md" -newer /tmp/.heartbeat 2>/dev/null | wc -l > /tmp/.heartbeat && date >> /tmp/.heartbeat-log'
$SSH_CMD "sudo -u botuser bash -c '(crontab -l 2>/dev/null; echo \"$CRON_HEARTBEAT\") | crontab -'"
echo "  Done"

# --- Verify ---
echo ""
echo "→ Checking service status..."
$SSH_CMD "sudo systemctl status personal-bot --no-pager" 2>&1 | head -10

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Bot should be running. Test by sending /start on Telegram."
echo ""
echo "Useful commands:"
echo "  ssh ubuntu@$PUBLIC_IP sudo journalctl -u personal-bot -f    # live logs"
echo "  ssh ubuntu@$PUBLIC_IP sudo systemctl restart personal-bot   # restart"
echo "  ssh ubuntu@$PUBLIC_IP sudo systemctl status personal-bot    # status"
