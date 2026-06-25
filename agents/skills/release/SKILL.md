---
name: release
description: Cut a release of the servant-openapi-hs package and publish it to Hackage following the Haskell PVP. Walks through computing the version bump, updating the cabal version and changelog, running the format/build/test/flake-check gates, committing, tagging, pushing, uploading to Hackage, and creating the GitHub release.
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# Release `servant-openapi-hs` to Hackage

This skill releases **`servant-openapi-hs`** — a single-package Cabal project — to
[Hackage](https://hackage.haskell.org/) following the Haskell
[Package Versioning Policy (PVP)](https://pvp.haskell.org/).

The package lives at the repository root (`servant-openapi-hs.cabal`) and contains
three components that all ship together in one sdist:

- the **library** (`Servant.OpenApi.*`) — the published API;
- the **`gen-openapi` executable** (`app/GenOpenApi.hs`) — an OpenAPI 3.1
  conformance generator;
- the **`spec` test-suite** (`test/`) — hspec tests.

There is exactly one publishable unit (`servant-openapi-hs`); the executable and
test-suite are components of that same package, not separate Hackage packages.
**Nothing is excluded or split out**, so there is no multi-package dependency
order to manage.

## Versioning strategy (PVP)

A version is `A.B.C.D` (e.g. `4.0.0` is `A.B.C` with an implicit `.D = 0`).
Given a `major|minor|patch` argument — or inferred from the changes if no
argument is passed:

- **major** → bump `A.B` (the major version). Use for any breaking change:
  removed/renamed exports, changed type signatures, behavioral changes that
  could break downstream code, or tightening/loosening that breaks builds.
  Reset the lower components.
- **minor** → bump `C`. Use for backwards-compatible additions: new exported
  functions, modules, or instances.
- **patch** → bump `D`. Use for changes that do not affect the API at all:
  documentation, internal refactors, dependency-bound widening that adds no
  new API, test-only changes.

When in doubt between minor and major, prefer **major** — PVP treats any change
to existing signatures as breaking. Confirm the computed bump with the operator
before writing it anywhere.

## Steps

### 1. Determine what changed since the last release

```bash
# Most recent release tag (tags use the v<version> format, e.g. v4.0.0)
git describe --tags --abbrev=0 2>/dev/null || echo "(no tags yet)"
git tag --list
```

- If a previous tag exists, review `git log <last-tag>..HEAD` and
  `git diff <last-tag>..HEAD -- servant-openapi-hs.cabal src` to classify the
  changes (API additions, breakages, or non-API).
- If there are **no tags yet** (first release), the working `CHANGELOG.md` top
  section and the current cabal `version:` describe the release-in-progress.
  Treat the existing version as the version to publish unless a further bump is
  warranted.

Read the current version:

```bash
grep -m1 '^version:' servant-openapi-hs.cabal
```

### 2. Compute the PVP bump

Apply the rule from **Versioning strategy** to the current version, honoring the
`major|minor|patch` argument if one was given. Present the operator with:

- the current version and the proposed new version,
- the reason (which changes drove the bump),
- the changelog entries you intend to write.

Get explicit confirmation before editing any file.

### 3. Update the cabal version

Edit `servant-openapi-hs.cabal`:

- Set `version:` to the new version.
- If GHC support changed, update the `tested-with:` line.
- Review the `build-depends` upper bounds — if you bumped because a new
  dependency major was adopted, make sure the bounds reflect what actually
  builds.

### 4. Update the changelog

Edit `CHANGELOG.md`. The convention here is a version heading underlined with
hyphens, followed by `*`-bulleted entries (see the existing `4.0.0` section):

```
<new-version>
-----

* <entry describing the change>
* <entry ...>
```

Add a new top section for the release with human-readable bullets summarizing
the user-facing changes since the last release. Keep the older sections intact.

### 5. Run the gates (all must pass)

Run every gate. **Stop immediately on any failure** — do not proceed to commit
or upload until everything is green.

```bash
# Formatting must be clean (treefmt: fourmolu + cabal-fmt + nixpkgs-fmt)
nix fmt
git diff --exit-code            # nix fmt rewrites in place; fail if it changed anything

# Build every component
cabal build all

# Run the hspec test-suite
cabal test

# Full flake check (build + treefmt + pre-commit hooks)
nix flake check
```

If `nix fmt` reformats files, review and stage the formatting changes (or fold
them into your release commit) and re-run the build/test/check gates.

Optionally validate the package as Hackage will see it:

```bash
cabal check          # warns about anything Hackage would reject
cabal sdist          # produces dist-newstyle/sdist/servant-openapi-hs-<version>.tar.gz
```

### 6. Commit, tag, push

Use a Conventional Commits message for the release commit (this repo follows
Conventional Commits — recent history uses `chore(release): ...`):

```bash
git add servant-openapi-hs.cabal CHANGELOG.md
git commit -m "chore(release): servant-openapi-hs <new-version>"

# Annotated tag, v<version> format
git tag -a v<new-version> -m "servant-openapi-hs <new-version>"

git push origin HEAD
git push origin v<new-version>
```

### 7. Publish to Hackage

Build the sdist and a candidate, eyeball it, then publish. `cabal upload`
without `--publish` creates a *candidate* (a dry run you can inspect on
Hackage); `--publish` makes the release permanent and **irreversible**.

```bash
# Source distribution
cabal sdist

# (optional, recommended) upload a candidate first and inspect it on Hackage
cabal upload dist-newstyle/sdist/servant-openapi-hs-<new-version>.tar.gz

# Publish the package (irreversible)
cabal upload --publish dist-newstyle/sdist/servant-openapi-hs-<new-version>.tar.gz

# Build and publish the Haddock documentation
cabal haddock --haddock-for-hackage --enable-doc
cabal upload --publish --documentation \
  dist-newstyle/servant-openapi-hs-<new-version>-docs.tar.gz
```

Hackage credentials come from `~/.cabal/config` or a `HACKAGE_KEY` / interactive
login; if `cabal upload` prompts for a username/password or token, surface that
to the operator rather than guessing.

### 8. Create the GitHub release

```bash
gh release create v<new-version> \
  --title "servant-openapi-hs <new-version>" \
  --notes "$(sed -n '/^<new-version>$/,/^---$/p' CHANGELOG.md)"
```

Adjust the `--notes` extraction to capture just the new version's bullets (or
pass `--notes-file` with a hand-trimmed body). Confirm the release renders
correctly on GitHub.

## Important

- **Confirm the version bump and changelog with the operator before committing.**
  Never write a new version or upload without explicit sign-off.
- **Never skip the gates.** `nix fmt` (clean), `cabal build all`, `cabal test`,
  and `nix flake check` must all pass before any upload.
- **Stop on any failure.** A red gate, a `cabal check` warning that Hackage
  would reject, or a failed push means halt and fix — do not upload.
- **Publishing is irreversible.** `cabal upload --publish` cannot be undone for
  a given version. Prefer uploading a candidate first and inspecting it.
- **Tag and push before publishing** so the Hackage release always corresponds
  to a pushed, tagged commit.
