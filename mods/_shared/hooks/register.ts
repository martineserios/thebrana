import type { Register } from 'claude-code'

// cockpit-shared registers nothing. The module exists so `claude plugin test mods/_shared`
// runs the *.test.ts beside it: the engine skips a folder with no hooks module (exit 0, no
// tests run — see tests/fixtures/mods/captures/test-backlog-pane.txt and t-3446). The
// files here are the source of truth and are vendored into mods/<mod>/hooks/_shared/.
export const register: Register = () => {}
