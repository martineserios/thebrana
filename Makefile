.PHONY: hooks-deploy hooks-check

HOOKS_SRC  := system/hooks
HOOKS_DEST := $(HOME)/.claude/hooks

# Deploy all hooks + hooks.json to the stable runtime location.
# Run this once on machine setup, then auto-deploy handles ongoing syncs.
hooks-deploy:
	@mkdir -p $(HOOKS_DEST)
	@rsync -a --delete $(HOOKS_SRC)/ $(HOOKS_DEST)/
	@echo "hooks deployed: $(HOOKS_SRC)/ → $(HOOKS_DEST)/"

# Check for drift between source and deployed hooks. Exit 1 if stale.
hooks-check:
	@DIFF=$$(diff -rq --exclude="*.pyc" --exclude="__pycache__" $(HOOKS_SRC)/ $(HOOKS_DEST)/ 2>&1); \
	if [ -n "$$DIFF" ]; then \
		echo "DRIFT detected — run 'make hooks-deploy' to sync:"; \
		echo "$$DIFF"; \
		exit 1; \
	else \
		echo "OK — hooks in sync"; \
	fi
