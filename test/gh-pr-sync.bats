#!/usr/bin/env bats
# Copyright (c) 2026 MicroCore Tech
# SPDX-License-Identifier: MIT
#
# Tests for gh-pr-sync. GitHub is replaced by a local bare repository that
# lives under .../github.com/acme/widgets.git, so the upstream URL looks like a
# GitHub one, and gh is replaced by test/bin/gh.
#
# Upstream history built by setup():
#
#   main:              base ── upstream
#   refs/pull/1/head:  base ── feature

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../gh-pr-sync"
  export PATH="$BATS_TEST_DIRNAME/bin:$PATH"
  export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  : >"$GH_LOG"

  # Isolate from the user's git config (signing, hooks, default branch, ...).
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  git config --global user.name "Test"
  git config --global user.email "test@example.com"
  git config --global init.defaultBranch main

  unset UPSTREAM_REMOTE
  export FAKE_PR_HEAD=feature FAKE_PR_BASE=main FAKE_PR_STATE=OPEN FAKE_PR_REMOTE=upstream

  UPSTREAM="$BATS_TEST_TMPDIR/github.com/acme/widgets.git"
  SEED="$BATS_TEST_TMPDIR/seed"
  git init -q --bare "$UPSTREAM"
  git init -q "$SEED"

  commit base.txt "base"
  git -C "$SEED" push -q "$UPSTREAM" main
  push_pr 1 main feature.txt "feature"
  commit upstream.txt "upstream"
  git -C "$SEED" push -q "$UPSTREAM" main

  CLONE="$BATS_TEST_TMPDIR/clone"
  git clone -q -o upstream "$UPSTREAM" "$CLONE"
  cd "$CLONE"
}

# commit <file> <content>: commit a file on the current branch of the seed repo.
commit() {
  echo "$2" >"$SEED/$1"
  git -C "$SEED" add "$1"
  git -C "$SEED" commit -q -m "update $1"
}

# push_pr <number> <start> <file> <content>: publish refs/pull/<number>/head
# as one commit on top of <start>.
push_pr() {
  local current
  current="$(git -C "$SEED" branch --show-current)"
  git -C "$SEED" checkout -q -b "pr-$1" "$2"
  commit "$3" "$4"
  git -C "$SEED" push -q "$UPSTREAM" "HEAD:refs/pull/$1/head"
  git -C "$SEED" checkout -q "$current"
}

# has_file <file>: the file is committed at HEAD.
has_file() {
  git cat-file -e "HEAD:$1"
}

# --- arguments ---------------------------------------------------------------

@test "--help prints usage without the license header" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Check out a GitHub PR into a fresh local branch and merge the latest base" ]
  [[ "${lines[${#lines[@]}-1]}" == *"UPSTREAM_REMOTE  remote to merge from"* ]]
  [[ "$output" != *"SPDX"* ]]
  [[ "$output" != *"Copyright"* ]]
}

@test "no arguments prints usage and fails" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "rejects an argument that is not a PR number or URL" {
  run "$SCRIPT" feature
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected a PR number or URL, got: feature"* ]]
}

@test "rejects a second positional argument" {
  run "$SCRIPT" 1 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected argument: 2"* ]]
}

@test "--base requires a value" {
  run "$SCRIPT" 1 --base
  [ "$status" -eq 1 ]
  [[ "$output" == *"--base requires a value"* ]]
}

# --- environment checks ------------------------------------------------------

@test "fails outside a git repository" {
  cd "$BATS_TEST_TMPDIR"
  run "$SCRIPT" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
}

@test "fails when the upstream remote is missing" {
  git remote rename upstream origin
  run "$SCRIPT" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"remote 'upstream' not found"* ]]
}

@test "fails when the repo cannot be derived from the upstream URL" {
  git remote set-url upstream "$BATS_TEST_TMPDIR/elsewhere.git"
  run "$SCRIPT" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot derive GitHub repo from 'upstream' URL"* ]]
}

@test "fails when the PR cannot be read" {
  export FAKE_PR_HEAD=""
  run "$SCRIPT" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not resolve to a PullRequest"* ]]
  ! grep -q "pr checkout" "$GH_LOG"
}

# --- syncing -----------------------------------------------------------------

@test "checks out the PR and merges the upstream base branch" {
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Done: on 'feature', merged with upstream/main"* ]]
  [ "$(git branch --show-current)" = "feature" ]
  has_file feature.txt
  has_file upstream.txt
  grep -q "pr view 1 -R acme/widgets" "$GH_LOG"
  grep -q "pr checkout 1 -R acme/widgets --branch feature --force" "$GH_LOG"
}

@test "accepts a PR number prefixed with #" {
  run "$SCRIPT" "#1"
  [ "$status" -eq 0 ]
  grep -q "pr view 1 -R acme/widgets" "$GH_LOG"
}

@test "takes the repo from a PR URL" {
  run "$SCRIPT" https://github.com/other/fork/pull/1
  [ "$status" -eq 0 ]
  grep -q "pr view 1 -R other/fork" "$GH_LOG"
  grep -q "pr checkout 1 -R other/fork" "$GH_LOG"
}

@test "derives the repo from an SSH upstream URL" {
  # `git remote get-url` expands insteadOf, so emulate the scp-like
  # "github.com:acme/widgets.git" with a local path that ends the same way.
  mkdir -p "$BATS_TEST_TMPDIR/ssh/github.com:acme"
  ln -s "$UPSTREAM" "$BATS_TEST_TMPDIR/ssh/github.com:acme/widgets.git"
  git remote set-url upstream "$BATS_TEST_TMPDIR/ssh/github.com:acme/widgets.git"
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  grep -q "pr view 1 -R acme/widgets" "$GH_LOG"
}

@test "--base merges the given branch instead of the PR base" {
  git -C "$SEED" checkout -q -b release-1.0 main~1
  commit release.txt "release"
  git -C "$SEED" push -q "$UPSTREAM" release-1.0

  run "$SCRIPT" 1 --base release-1.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"merged with upstream/release-1.0"* ]]
  has_file release.txt
  ! has_file upstream.txt
}

@test "UPSTREAM_REMOTE selects the remote to merge from" {
  git remote rename upstream src
  export UPSTREAM_REMOTE=src FAKE_PR_REMOTE=src
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"merged with src/main"* ]]
  has_file upstream.txt
}

@test "warns about a PR that is not open but still syncs it" {
  export FAKE_PR_STATE=MERGED
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: PR 1 is MERGED"* ]]
  has_file feature.txt
}

# --- branch naming -----------------------------------------------------------

@test "does not overwrite local main when the PR head branch is main" {
  export FAKE_PR_HEAD=main
  main_before="$(git rev-parse main)"
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = "pr-1-main" ]
  [ "$(git rev-parse main)" = "$main_before" ]
}

@test "renames master and release-* head branches" {
  export FAKE_PR_HEAD=master
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = "pr-1-master" ]

  export FAKE_PR_HEAD=release-1.0
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = "pr-1-release-1.0" ]
}

@test "resets an existing local branch to the PR head" {
  git branch feature main
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Local branch 'feature' exists; it will be reset to the PR head"* ]]
  [ "$(git branch --show-current)" = "feature" ]
  has_file feature.txt
}

# --- uncommitted changes -----------------------------------------------------

@test "--reset discards unstaged changes" {
  echo "local edit" >base.txt
  run "$SCRIPT" 1 --reset
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discarding uncommitted changes"* ]]
  [ -z "$(git status --porcelain)" ]
}

@test "--reset discards staged changes" {
  echo "staged" >staged.txt
  git add staged.txt
  run "$SCRIPT" 1 --reset
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discarding uncommitted changes"* ]]
  [ -z "$(git status --porcelain)" ]
}

@test "refuses to discard uncommitted changes without a terminal" {
  if (: </dev/tty) 2>/dev/null; then
    skip "a terminal is attached, so the script would prompt"
  fi
  echo "local edit" >base.txt
  run "$SCRIPT" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"working tree has uncommitted changes"* ]]
  [ "$(cat base.txt)" = "local edit" ]
  ! grep -q "pr view" "$GH_LOG"
}

@test "untracked files do not block the sync" {
  echo "scratch" >notes.txt
  run "$SCRIPT" 1
  [ "$status" -eq 0 ]
  [ "$(cat notes.txt)" = "scratch" ]
}

# --- conflicts ---------------------------------------------------------------

@test "stops with a hint when the merge conflicts" {
  push_pr 2 main~1 upstream.txt "conflicting"
  run "$SCRIPT" 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"Merge has conflicts"* ]]
  git rev-parse -q --verify MERGE_HEAD
}

# --- repository --------------------------------------------------------------

# Scripts carry the header right after the shebang; Makefiles and YAML files
# start with it.
@test "every source file starts with the license header" {
  local root="$BATS_TEST_DIRNAME/.." file first missing=()
  while IFS= read -r file; do
    [[ -f "$root/$file" ]] || continue
    if [[ "$(head -c 2 "$root/$file")" == "#!" ]]; then
      first=2
    elif [[ "$file" == Makefile || "$file" == *.yml || "$file" == *.yaml ]]; then
      first=1
    else
      continue
    fi
    sed -n "${first}p" "$root/$file" | grep -Eqx '# Copyright \(c\) [0-9]{4}(-[0-9]{4})? MicroCore Tech' &&
      sed -n "$((first + 1))p" "$root/$file" | grep -qx '# SPDX-License-Identifier: MIT' ||
      missing+=("$file")
  done < <(git -C "$root" ls-files --cached --others --exclude-standard)
  if [ "${#missing[@]}" -ne 0 ]; then
    echo "missing license header: ${missing[*]}"
    return 1
  fi
}
