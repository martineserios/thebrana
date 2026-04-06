
# Do — Alias for backlog start

`/brana:do` is an alias for `/brana:backlog start` with freeform text input.

## Usage

`/brana:do <description>`

## How it works

Invoke `/brana:backlog start` with the arguments treated as freeform text (step 1a of the start procedure):

```
Skill(skill="brana:backlog", args="start $ARGUMENTS")
```

All routing, skill matching, task creation, and batch detection logic lives in `/brana:backlog start`. See `system/procedures/backlog.md` § `/brana:backlog start` → step 1a.
