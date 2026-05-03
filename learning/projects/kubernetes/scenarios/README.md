# Scenarios

Per-scenario notes live in this folder once you start each one. Create a
subfolder per scenario with:

```
scenarios/
├── 01-cluster-up/
│   ├── README.md        # what this adds, how to run, exit criteria
│   ├── journal.md       # what surprised you, what broke, what you learned
│   └── manifests/       # any scenario-specific manifests that don't belong in /manifests yet
├── 02-stateful-postgres/
│   └── ...
└── ...
```

The `journal.md` file is the most valuable long-term artifact. Fill it in as
you work — not after — because the "what surprised me" bits vanish from your
memory within a day. Close each session with `/brana:retrospective` to pull the
most transferable learnings into the brana knowledge base.
