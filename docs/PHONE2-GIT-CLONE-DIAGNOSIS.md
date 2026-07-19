# Phone 2 Git Clone Failure — Root Cause Diagnosis

**Date:** 2026-07-19
**RUN_ID:** 20260719T060200Z
**Device:** Phone 2 (Android 15, SDK 35, aarch64, u0_a217)

---

## Root Cause

**`git clone --branch <SHA>` fails because a raw commit SHA is not a branch name.**

The installer passes the candidate commit SHA (`89f46cc98393e4e38a1a470a65df6507153f32fe`) as the `--branch` argument to `git clone`. Git interprets this as a branch name, not a ref, and fails:

```
fatal: Remote branch 89f46cc98393e4e38a1a470a65df6507153f32fe not found in upstream origin
```

**This is NOT a network issue.** Phone 2 has full access:
- DNS resolves github.com
- CA certificates present (`ca-certificates/stable,now 1:2026.05.14`)
- HTTPS to `raw.githubusercontent.com` → HTTP 200
- HTTPS to `github.com` → HTTP 200
- `git ls-remote` → succeeds (lists all branches and tags)
- `git clone --depth 1` (default branch) → succeeds
- `git clone --depth 1 -b <branch-name>` → succeeds
- codeload tarball download → succeeds

## Verified Working Methods

| Method | Works | Notes |
|--------|-------|-------|
| `git clone` (default branch) | YES | Clones `main` |
| `git clone -b <branch-name>` | YES | e.g. `-b fix/phone-bootstrap-release-gate-20260719` |
| `git clone --branch <SHA>` | **NO** | SHA ≠ branch name |
| `git clone` + `git checkout <SHA>` | YES | Clone default, then checkout SHA |
| codeload tarball | YES | `https://codeload.github.com/<owner>/<repo>/tar.gz/<SHA>` |
| `git ls-remote` | YES | All refs visible |

## Fix (for installer)

### Option 1: Clone default + checkout SHA (recommended)
```sh
git clone --depth 1 "$REPO_URL" "$REPO_DIR" && \
  git -C "$REPO_DIR" fetch --depth 1 origin "$REF" && \
  git -C "$REPO_DIR" checkout "$REF"
```

### Option 2: Tarball fallback
```sh
curl -fsSL "https://codeload.github.com/$OWNER/$REPO/tar.gz/$REF" | tar xz
mv "$REPO-$REF_SHORT" "$REPO_DIR"
```

### Chosen approach: Option 1 primary, Option 2 fallback
Both should be implemented in `ensure_repo()` in `bootstrap-termux.sh`.

## Impact

This bug affects the `phone-relay` profile's repo clone step on ALL fresh phones, not just Phone 2. It was masked during Phone 1 testing because Phone 1 already had the repo from a previous install (the `if [ -d "$_REPO_DIR/.git" ]` path was taken).

## Verification

After fix, confirm on Phone 2:
```
git clone --depth 1 https://github.com/dharani-sg/universal-omni-master /tmp/test-clone
git -C /tmp/test-clone fetch --depth 1 origin 89f46cc98393e4e38a1a470a65df6507153f32fe
git -C /tmp/test-clone checkout 89f46cc98393e4e38a1a470a65df6507153f32fe
```
