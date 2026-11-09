# Agent instructions

`gh-pr-sync` is a GitHub CLI extension written in bash. The extension itself is
the `gh-pr-sync` script in the repository root.

## License header

Every source file must carry the license header. In scripts (any file starting
with `#!`) it goes right after the shebang:

```bash
#!/usr/bin/env bash
# Copyright (c) 2026 MicroCore Tech
# SPDX-License-Identifier: MIT
```

`Makefile` and YAML files (such as GitHub workflows) start with it:

```yaml
# Copyright (c) 2026 MicroCore Tech
# SPDX-License-Identifier: MIT
```

Use the year the file is created. `README.md`, `AGENTS.md`, `CLAUDE.md`,
`LICENSE` and `.gitignore` do not need a header. The test suite fails if a
source file is missing it.

## Help text

`usage()` in `gh-pr-sync` prints the comment block at the top of the script by
line range (`sed -n '5,22p'`). When you change the header or the help comment,
update that range and check `./gh-pr-sync --help`.

## Tests

Tests use [bats-core](https://github.com/bats-core/bats-core) and run offline:
`test/bin/gh` replaces the real `gh`, and a local bare repository stands in for
GitHub.

```bash
make test
```

CI (`.github/workflows/test.yml`) runs the same command on Ubuntu and macOS.
Add or update tests in `test/gh-pr-sync.bats` for every behavior change.
