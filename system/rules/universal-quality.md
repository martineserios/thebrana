# Quality Standards

- **Test before committing**: run relevant tests before any commit. If no test suite exists, at least verify the change manually.
- **Verify before done**: confirm functionality before declaring completion. Compare before/after behavior when modifying existing code. Ask: would an experienced engineer endorse this solution?
- **No secrets in code**: never commit API keys, tokens, passwords, or `.env` files. Use environment variables.
- **Error handling**: handle errors explicitly. Don't swallow exceptions or ignore return codes.
- **Type safety**: prefer typed approaches where the language supports it.
- **Code review mindset**: write code as if someone else will maintain it tomorrow.
- **Test assertion discipline**: investigate code before weakening assertions. Explain why the expectation was wrong.
