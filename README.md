# gh-pr-sync

A [GitHub CLI](https://cli.github.com/) extension that checks out a pull request
into a fresh local branch and merges the latest base branch from upstream into it.

Useful when reviewing or testing a PR against the current state of its base
branch, without waiting for the author to rebase.

## Requirements

- [`gh`](https://cli.github.com/), authenticated (`gh auth login`)
- `git`
- `bash`

## Installation

```bash
gh extension install microcoretech/gh-pr-sync
```

Upgrade to the latest version:

```bash
gh extension upgrade pr-sync
```

Uninstall:

```bash
gh extension remove pr-sync
```

## Usage

Run it inside a clone of the repository that has an `upstream` remote pointing
to the GitHub repository the PR was opened against:

```bash
gh pr-sync <PR number | PR URL> [--base <branch>] [--reset]
```

### Options

| Option            | Description                                                    |
|-------------------|----------------------------------------------------------------|
| `--base <branch>` | Base branch to merge (default: the PR's base branch)           |
| `--reset`         | Discard uncommitted changes (`git reset --hard`) without asking |
| `-h`, `--help`    | Show help                                                      |

### Environment

| Variable          | Description                                  |
|-------------------|----------------------------------------------|
| `UPSTREAM_REMOTE` | Remote to merge from (default: `upstream`)   |

### Examples

```bash
gh pr-sync 16935
gh pr-sync https://github.com/kubernetes-sigs/kueue/pull/16935
gh pr-sync 16935 --base main
gh pr-sync 16935 --reset
UPSTREAM_REMOTE=origin gh pr-sync 16935
```

## How it works

1. Resolves the repository from the PR URL, or from the `upstream` remote URL
   when only a PR number is given.
2. If the working tree has uncommitted changes to tracked files, asks before
   running `git reset --hard` (or does it right away with `--reset`).
3. Checks out the PR head into a local branch named after the PR's head branch.
   If that name is `main`, `master` or `release-*`, the branch is named
   `pr-<number>-<head branch>` instead, so local base branches are never overwritten.
   An existing local branch with the same name is reset to the PR head.
4. Fetches `upstream/<base>` and merges it into the branch.

If the merge has conflicts, resolve them and run `git commit`, or abort with
`git merge --abort`.

## Development

To try local changes, install the extension from your working copy:

```bash
gh extension install .
```

This links the installed extension to the local checkout, so edits take effect
immediately.

Tests use [bats-core](https://github.com/bats-core/bats-core) and do not need
network access or a real `gh`:

```bash
brew install bats-core   # or: apt-get install bats
make test
```

## License

[MIT](LICENSE)
