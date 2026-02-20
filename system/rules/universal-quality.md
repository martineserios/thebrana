# Quality Standards

- **Test before committing**: run relevant tests before any commit. If no test suite exists, at least verify the change manually.
- **No secrets in code**: never commit API keys, tokens, passwords, or `.env` files. Use environment variables.
- **Error handling**: handle errors explicitly. Don't swallow exceptions or ignore return codes.
- **Type safety**: prefer typed approaches where the language supports it.
- **Code review mindset**: write code as if someone else will maintain it tomorrow.
- **Test assertion discipline**: when tests fail, investigate code first. Never weaken or remove an assertion without explaining why the original expectation was wrong.
