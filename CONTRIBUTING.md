# Contributing

## Commit format

Use Conventional Commits:

```text
<type>[optional scope]: <description>
```

Common types:

- `feat`
- `fix`
- `chore`
- `docs`
- `refactor`
- `test`
- `ci`

Examples:

- `feat(tui): add inspect view`
- `fix(kill): handle process-not-found errors`

CI rejects non-conforming commit messages.

## Optional local commit hook

To enforce Conventional Commits locally, run:

```bash
git config core.hooksPath .githooks
```
