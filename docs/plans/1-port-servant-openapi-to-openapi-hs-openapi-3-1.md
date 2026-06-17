---
id: 1
slug: port-servant-openapi-to-openapi-hs-openapi-3-1
title: "Port servant-openapi to openapi-hs (OpenAPI 3.1)"
kind: exec-plan
created_at: 2026-06-17T19:52:07Z
intention: "intention_01kvbj3110eanbcej7x38w161z"
---

# Port servant-openapi to openapi-hs (OpenAPI 3.1)

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`servant-openapi` is a Haskell library that takes the *type* of a web API written with the
[Servant](https://github.com/haskell-servant/servant) framework and automatically produces a
machine-readable description of that API in the **OpenAPI** format (a JSON/YAML document that
tools use to render docs, generate clients, and validate requests). It is a fork of the
upstream package `servant-openapi3`, which only produces **OpenAPI version 3.0** documents.

This plan retargets the fork at **OpenAPI 3.1**. It does so by switching the underlying data
model from the old `openapi3` package to its 3.1 fork **`openapi-hs`** (a sibling repository at
`../openapi-hs`, package name `openapi-hs`, Haskell modules still under the `Data.OpenApi.*`
namespace). OpenAPI 3.1 aligns the schema language with **JSON Schema 2020-12**, which changes
how a few things are expressed (explained in Context below).

After this change, a user who writes:

```haskell
import Servant.OpenApi (toOpenApi)
import Data.Proxy (Proxy (..))

spec :: Data.OpenApi.OpenApi
spec = toOpenApi (Proxy :: Proxy MyApi)
```

and serializes `spec` to JSON will get a document whose top line reads `"openapi": "3.1.0"`
(today the same code on the unported fork would emit `"3.0.0"` and would not even build,
because the package depends on `openapi-hs` now). The observable, verifiable outcome is: the
library builds against `openapi-hs`, the test suite passes, and a generated spec is a valid
OpenAPI 3.1 document.

The dependency name swap (`openapi3` → `openapi-hs`) and the package rename
(`servant-openapi3` → `servant-openapi`) were already completed in the commit that created this
fork; this plan covers making the code actually **build and pass its tests** against
`openapi-hs`, plus reproducible-build wiring and final documentation.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] **M1** — Enter the dev shell and confirm the toolchain (GHC 9.12.4, cabal 3.16.1.0) and
      that `openapi-hs` resolves from the `cabal.project` git pin. ✅
- [x] **M1** — `cabal build lib:servant-openapi` compiles the library against `openapi-hs`
      under `default-language: GHC2024`. One source edit needed (`OpenApiTypeSingle`, see
      Surprises). ✅
- [x] **M2** — `cabal build` compiles the `spec` test suite (test-only deps resolve). Two more
      library edits needed for new 3.1 record fields (`_openApiWebhooks`, `_pathItemRef`). ✅
- [x] **M2** — Update test fixtures in `test/Servant/OpenApiSpec.hs`: changed all four
      `"openapi": "3.0.0"` to `"3.1.0"`. No other fixture changes were required — the derived
      data model is otherwise identical. ✅
- [x] **M2** — Added Layer-1 validation: a `roundTrips` `hspec` example per generated document
      decodes through `openapi-hs`'s version-enforcing `FromJSON OpenApi` and compares at the
      aeson `Value` level (see Surprises for why not `== Right spec`). ✅
- [x] **M2** — Added Layer-2 validation: `validateEveryToJSON (Proxy :: Proxy ValidationAPI)`
      over a sample `Health` API with `Arbitrary`/`ToJSON`/`ToSchema` instances (100 cases). ✅
- [x] **M2** — `cabal test spec` passes — 11 examples, 0 failures. ✅
- [x] **M3** — Added an `exe:gen-openapi` component (`app/GenOpenApi.hs`) emitting a complete
      Todo CRUD document (info, server, tags, unique operationIds) to stdout. ✅
- [x] **M3** — Layer-3 validation: `cabal run gen-openapi > openapi.json` then
      `nix run nixpkgs#vacuum-go -- lint -d openapi.json` reports **0 errors** (28 style warnings
      about missing descriptions/examples; vacuum exits 0; Quality Score 90/100). ✅
- [ ] **M4** — (Reproducible build) Add `flake.module.nix` providing an `openapi-hs` package
      override so `nix build .#default` builds the library through Nix.
- [ ] **M5** — Update `CHANGELOG.md` and `README.md` with the concrete outcome and commit.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`type_` now takes `OpenApiTypeValue`, not `OpenApiType` (M1).** The one library use of the
  3.0→3.1 type-array change predicted in Context surfaced at
  `src/Servant/OpenApi/Internal.hs:362`. `type_ ?~ OpenApiArray` no longer typechecks because
  `_schemaType :: Maybe OpenApiTypeValue`. Fixed to `type_ ?~ OpenApiTypeSingle OpenApiArray`,
  matching how `openapi-hs` itself sets the field (e.g. `Data/OpenApi/Internal/ParamSchema.hs`).

- **Two new 3.1 record fields broke explicit record construction (M2).** The library's
  `combineSwagger`/`combinePathItem` helpers build `OpenApi`/`PathItem` with explicit field
  lists, so new fields are a compile-or-runtime break, not silently defaulted. OpenAPI 3.1 added
  two fields that `openapi-hs` carries:
  - `OpenApi` gained `_openApiWebhooks :: InsOrdHashMap Text (Referenced PathItem)`. Missing it
    produced `RecConError ... Missing field in record construction _openApiWebhooks` at runtime
    (the UVerb test). Added `_openApiWebhooks = _openApiWebhooks s <> _openApiWebhooks t`
    (monoidal union, matching the generic `Semigroup OpenApi`).
  - `PathItem` gained `_pathItemRef :: Maybe Text` (3.1 allows `$ref` in a Path Item). Missing
    it produced `RecConError ... _pathItemRef`. Added
    `_pathItemRef = _pathItemRef s <|> _pathItemRef t` (left-biased, matching the sibling
    `Maybe` fields `_pathItemSummary`/`_pathItemDescription`).
  Evidence: both surfaced as `uncaught exception: RecConError` in `cabal test spec`, fixed
  one-by-one until all 5 fixture tests passed.

- **No fixture data changes beyond the version string (M2).** The `Maybe`-field nullability
  concern raised in Context did not materialize: a Haskell `Maybe` field still only makes a
  property optional (absent from `required`), it does not emit `"type": ["…","null"]`. With the
  four `"3.0.0"` → `"3.1.0"` edits, all five fixture comparisons passed unchanged.

- **Layer 1 cannot use `decoded == Right spec` (M2).** Two independent quirks make structural
  `Eq`/byte equality the wrong round-trip oracle, even though the document is valid and
  semantically unchanged:
  1. `InsOrdHashSet`'s `Eq` (insert-ordered-containers; used for `tags`/`operationTags`) is
     sensitive to an internal index counter that a JSON round-trip does not reconstruct. Proven
     in the repl: for `getPostOpenApi`, `s ^. tags == d ^. tags` is `False` while
     `toList (s ^. tags) == toList (d ^. tags)` is `True`.
  2. aeson decodes JSON objects into an order-insensitive `KeyMap`, so re-encoded bytes differ
     in key order (e.g. `components.schemas` keys reordered) from the original even when the
     documents are identical.
  Resolution: assert at the aeson `Value` level — `toJSON d == toJSON s`. `Value` equality is
  order-insensitive for objects but order-sensitive for arrays (`required`, `enum`, tag lists),
  so it is the precise semantic-equality oracle, and it still forces a decode through
  `openapi-hs`'s version-enforcing `FromJSON OpenApi`. Result: 11 examples, 0 failures.

- **`vacuum`'s default ruleset rates style rules as "errors" (M3).** The bare document
  `toOpenApi` produces (no `operationId`, no `servers`, empty `info.title`/`version`) made
  `vacuum lint` report 6 "errors" and exit 1. None were OpenAPI-3.1 *spec-validity* violations —
  `operationId` and `servers` are optional in the spec; `vacuum`'s recommended ruleset simply
  rates `operation-operationId` and `oas3-api-servers` at error severity. Evidence: `vacuum`'s
  own structural **Validation** category showed `0 errors` even in that run. Rather than
  suppress rules, the `gen-openapi` generator was made to emit a *complete* contract (real
  `info`, a `server`, `tags`, and a unique `operationId` per operation via a `paths`/`imap`
  lens pass). The enriched document lints to **0 errors, 28 warnings** (all
  `operation-description` / `oas3-missing-example` style hints, explicitly acceptable per the
  M3 plan) and `vacuum` exits 0 — Quality Score 90/100. This is the authoritative, independent
  confirmation that the emitted JSON is a valid OpenAPI 3.1 document.


## Decision Log

Record every decision made while working on the plan.

- Decision: Scope this as a single ExecPlan rather than a MasterPlan.
  Rationale: The work is one cohesive deliverable with a single integration point
  (`openapi-hs`), a single build, and a single test suite. A research pass showed the library
  source touches almost no 3.0-specific API — `src/Servant/OpenApi/Internal.hs:363` uses only
  `OpenApiItemsObject`, which `openapi-hs` retains — so the bulk of the work is updating test
  fixtures. MasterPlans are for coordinating multiple interdependent ExecPlans, which this is
  not.
  Date: 2026-06-17

- Decision: Pin `openapi-hs` by git revision in `cabal.project` (already done) rather than a
  relative path or Hackage.
  Rationale: `openapi-hs` is not on Hackage yet; a git pin is reproducible and does not assume
  the two repositories stay siblings on disk. The pinned tag is commit
  `89e9ed07e0dd3e1eaa9b3efea28b3c722f8c60c8` on `shinzui/openapi-hs`.
  Date: 2026-06-17

- Decision: Set the package's `default-language` to `GHC2024` (both the `library` and the
  `spec` test stanzas in `servant-openapi.cabal`), replacing `Haskell2010`.
  Rationale: Part of modernizing the fork onto the GHC 9.12.4 / 9.14.1 toolchain. `GHC2024`
  is the current language edition and is available on GHC ≥ 9.10, so it is safe for our
  targets. It enables a large set of extensions by default (see Context), which removes the
  need for many per-file `LANGUAGE` pragmas. The known risk is `MonoLocalBinds` (on by default
  under `GHC2024`), which can change inference of local `let`/`where` bindings and occasionally
  require an explicit type signature; any such breakage will surface during the M1/M2 compile
  and is handled there.
  Date: 2026-06-17

- Decision: Validate the generated spec in three layers — (1) in-test round-trip decode through
  `openapi-hs`, (2) `validateEveryToJSON` example-conformance, (3) external authoritative
  conformance with `vacuum` — rather than relying only on fixture equality.
  Rationale: Fixture equality only proves the output matches *our* expectation; a fixture we
  "correct" could itself be invalid 3.1. Layer 1 is free and strong: `openapi-hs`'s
  `FromJSON OpenApi` rejects any `openapi` version outside `3.1.0 … 3.1.1`
  (`Data/OpenApi/Internal.hs:1552`), so a successful `decode (encode spec)` proves valid 3.1.x
  versioning and a structurally-decodable document. Layer 2 is the package's own headline
  testing feature and proves schemas describe their data. Layer 3 checks the emitted JSON
  against the OpenAPI 3.1 model with an independent tool, catching anything the in-process
  layers miss. Layers 1–2 run on every `cabal test`; Layer 3 is a separate step.
  Date: 2026-06-17

- Decision: Use `vacuum` as the Layer-3 external validator, run from nixpkgs as
  `nix run nixpkgs#vacuum-go -- lint …` (no dev-shell change).
  Rationale: User preference; `vacuum` is a fast, actively-maintained OpenAPI linter with strong
  OpenAPI 3.1 / JSON-Schema-2020-12 support, and it is packaged in nixpkgs. Confirmed: the
  nixpkgs attribute is `vacuum-go` and its main program is `vacuum`
  (`nix eval --raw nixpkgs#vacuum-go.meta.mainProgram` → `vacuum`). Running via `nix run` keeps
  it reproducible without adding it to `haskellProject.extraDevPackages`.
  Date: 2026-06-17

- Decision: Add a small `exe:gen-openapi` component (`app/GenOpenApi.hs`) that prints a
  representative API's OpenAPI document to stdout, used to feed Layer-3 validation.
  Rationale: Layer 3 needs a real document on disk; a tiny dedicated executable is reproducible
  and CI-friendly (`cabal run gen-openapi > openapi.json`) and avoids entangling the unit tests
  with file IO. It also partly restores the usage example that the `example/` directory
  provided before it was removed in the fork.
  Date: 2026-06-17

- Decision: Implement Layer-1 round-trip as `toJSON (decode (encode spec)) == toJSON spec`
  (aeson `Value` equality) rather than the originally-planned `decode (encode spec) == Right
  spec`.
  Rationale: Discovered during M2 that `== Right spec` fails for valid, semantically-identical
  documents because (1) `InsOrdHashSet`'s `Eq` distinguishes index state a JSON round-trip drops
  and (2) aeson's `KeyMap` does not preserve object key order. `Value` equality is the precise
  oracle: object-key-order-insensitive, array-order-sensitive, and still routes through
  `openapi-hs`'s version-enforcing decoder (a wrong version → `Left` → `expectationFailure`). See
  Surprises & Discoveries for the repl evidence. This strengthens, not weakens, the assertion.
  Date: 2026-06-17

- Decision: Renumber milestones after inserting validation work: M3 = external (vacuum)
  conformance, M4 = reproducible Nix build, M5 = finalize docs. (Previously M3 = Nix build,
  M4 = docs.)
  Rationale: Validation is first-class to this port's purpose, so it earns its own milestone
  between "tests pass" and the build/doc wrap-up.
  Date: 2026-06-17

- Decision: Treat the `nix build .#default` wiring (now M4) as a real but lower-priority
  milestone; the primary acceptance path is the Nix **dev shell** plus `cabal`.
  Rationale: `nix/haskell.nix` builds the default package with `callCabal2nix`, which resolves
  dependencies from the nixpkgs Haskell package set — that set has no `openapi-hs`, so a pure
  `nix build` cannot succeed without an override. The dev shell + `cabal` path uses the
  `cabal.project` git pin and works today, so it is the source of truth for "it builds".
  Date: 2026-06-17


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of this repository. Read it fully before editing.

**What this repository is.** The working directory is the `servant-openapi` package (formerly
`servant-openapi3`). Its job is to convert a Servant API type into an OpenAPI document. The
public entry points live in `src/Servant/OpenApi.hs` (re-exports) and the real logic in
`src/Servant/OpenApi/Internal.hs`. Supporting modules:

- `src/Servant/OpenApi/Internal/Orphans.hs` — instances that bridge Servant and OpenAPI types.
- `src/Servant/OpenApi/Internal/Test.hs` — helpers to test that handler JSON conforms to the
  generated schema (uses `validateJSON` from `openapi-hs`).
- `src/Servant/OpenApi/Internal/TypeLevel/*` — type-level machinery; no OpenAPI-version concern.
- `test/Servant/OpenApiSpec.hs` — the single test module (529 lines). It builds small Servant
  APIs, generates their OpenAPI documents, and compares the produced JSON against hand-written
  expected JSON literals. `test/Spec.hs` is the one-line `hspec-discover` driver.

**The dependency that changed.** The package `cabal` file `servant-openapi.cabal` already
depends on `openapi-hs >=4.0 && <5` (not `openapi3`). `cabal.project` pins `openapi-hs` from
git. The Haskell modules of `openapi-hs` keep the **same names** as the old `openapi3`
(`Data.OpenApi`, `Data.OpenApi.Declare`, `Data.OpenApi.Schema.Validation`), so the `import`
lines in this repo do **not** change. A research pass confirmed all modules and names this repo
imports still exist in `openapi-hs`: `Data.OpenApi`, `Data.OpenApi.Declare`,
`Data.OpenApi.Schema.Validation`, the `Pattern` type alias (`type Pattern = Text`), `ToSchema`,
`toSchema`, and `validateJSON`.

**Term: "OpenAPI 3.0 vs 3.1".** OpenAPI is a specification for describing HTTP APIs. Version
3.0 used a custom schema dialect; version 3.1 adopts JSON Schema 2020-12. The differences that
can affect *generated output* (and therefore the expected-JSON literals in the test) are:

1. **The version string.** A 3.0 document starts with `"openapi": "3.0.0"`; a 3.1 document
   starts with `"openapi": "3.1.0"`. In `openapi-hs` the default empty document
   (`mempty :: Data.OpenApi.OpenApi`) emits `"3.1.0"`, controlled by the constants
   `lowerOpenApiSpecVersion = 3.1.0` and `upperOpenApiSpecVersion = 3.1.1` in
   `Data/OpenApi/Internal.hs`. This is the change that is *guaranteed* to appear in the test
   fixtures: the literal `"openapi": "3.0.0"` occurs four times in
   `test/Servant/OpenApiSpec.hs` (around lines 72, 198, 379, 456).

2. **`nullable` removed.** JSON Schema 2020-12 has no `nullable` keyword. Nullability is
   expressed with a type array, e.g. `{"type": ["string", "null"]}`. In `openapi-hs` the field
   `_schemaType` has type `Maybe OpenApiTypeValue`, where `OpenApiTypeValue` is either
   `OpenApiTypeSingle OpenApiType` or `OpenApiTypeArray [OpenApiType]`; there is **no**
   `_schemaNullable` field. Note: in the upstream `ToSchema` derivation, a Haskell `Maybe a`
   field merely makes the property *optional* (absent from the `required` list); it does not by
   itself emit a `"null"` type. So whether any fixture changes on this account depends on the
   exact derived output — the test runner will tell us. The test types that contain `Maybe`
   fields are `Todo` (`summary :: Maybe String`, around line 58) and a few others.

3. **`exclusiveMaximum` / `exclusiveMinimum` are numbers, not booleans.** Not currently used in
   the test fixtures; listed for completeness in case a derived schema surfaces it.

4. **Tuple `items` arrays removed.** 3.0 wrote `"items": [s1, s2]` for fixed tuples; 3.1 uses
   `"prefixItems"`. In `openapi-hs`, `OpenApiItems` has constructors `OpenApiItemsObject` and
   `OpenApiItemsBoolean` (no `OpenApiItemsArray`), and tuple positions live in a new
   `_schemaPrefixItems` field. The only `items` use in this repo's *library* code is
   `src/Servant/OpenApi/Internal.hs:363`, which uses `OpenApiItemsObject` (the single-schema
   form, retained) — so no library change is expected there.

**Term: "language edition" and `GHC2024`.** A Haskell *language edition* is a named bundle of
language extensions that are turned on by default for a whole package. `servant-openapi.cabal`
sets `default-language: GHC2024` in both the `library` and the `spec` test stanzas (replacing
the older `Haskell2010`). `GHC2024` is the modern edition supported on GHC ≥ 9.10, so it is
valid for our 9.12.4 / 9.14.1 targets. It enables by default many extensions this code base
otherwise turns on per file with `{-# LANGUAGE ... #-}` pragmas — including `DataKinds`,
`GADTs`, `TypeApplications`, `ScopedTypeVariables`, `TypeOperators`, `FlexibleContexts`,
`DeriveGeneric`, `LambdaCase`, `ImportQualifiedPost`, and `MonoLocalBinds`. Two practical
consequences: (1) existing per-file pragmas that name an extension already in `GHC2024` become
redundant but remain harmless — leave them; (2) `MonoLocalBinds` (on by default under
`GHC2024`) changes how local `let`/`where` bindings are generalized and can, in rare cases,
make the compiler ask for an explicit type signature it did not need under `Haskell2010`. If
the M1/M2 build reports such an error, add the requested signature at the indicated binding and
note it in Surprises & Discoveries.

**Toolchain.** The repo ships a Nix flake (`flake.nix`, `nix/haskell.nix`) that provides a dev
shell with GHC 9.12.4, a matching `cabal`, and HLS. Inside that shell, ordinary `cabal`
commands work and use `cabal.project` (which carries the `openapi-hs` git pin). The package is
Cabal-only (`build-type: Simple`, `cabal-version: 3.0`); there is no `stack.yaml` and no custom
`Setup.hs`.


## Plan of Work

The work proceeds in four milestones. The first two are the substance (build + tests); the
third makes the Nix package build reproducible; the fourth records the result.

### Milestone M1 — Library compiles against openapi-hs

Scope: get the library (not yet the tests) to compile. At the end, `cabal build
lib:servant-openapi` succeeds inside the dev shell, proving the `openapi-hs` git pin resolves
and the library source is API-compatible with `openapi-hs`.

This milestone also exercises the new `default-language: GHC2024` setting (already committed in
`servant-openapi.cabal`): the library now compiles under the `GHC2024` language edition rather
than `Haskell2010`. Because research showed the library imports only names that still exist in
`openapi-hs`, the expectation is **zero or very few** source edits. If the compiler reports an
error, it will be either (a) one of the 3.0→3.1 removals listed in Context (a reference to
`_schemaNullable`, a boolean `exclusiveMaximum`, or `OpenApiItemsArray`), or (b) a
`GHC2024`-induced inference change (most likely a `MonoLocalBinds`-related "ambiguous type" /
"could not deduce" message asking for an explicit signature on a local binding). For (b), add
the requested type signature at the indicated binding. For (a), translate to the 3.1
equivalent:

- A use of `nullable`/`_schemaNullable` → set `_schemaType` to
  `Just (OpenApiTypeArray [theType, OpenApiNull])` (import the constructors from `Data.OpenApi`).
- A boolean `exclusiveMaximum`/`exclusiveMinimum` → move the bound into the numeric
  `_schemaExclusiveMaximum`/`_schemaExclusiveMinimum` field.
- An `OpenApiItemsArray [...]` → set `_schemaPrefixItems` to the list and `_schemaItems` to
  `Just (OpenApiItemsBoolean False)`.

Record any such edit in Surprises & Discoveries with the compiler message as evidence. Acceptance:
the `cabal build lib:servant-openapi` transcript ends with `Linking`/no errors.

### Milestone M2 — Test suite compiles and passes

Scope: get `test/Servant/OpenApiSpec.hs` to compile and the `spec` suite to pass. At the end,
`cabal test spec` reports 0 failures, proving the generated OpenAPI 3.1 documents match the
(updated) expected JSON.

First make the suite **compile** (resolve any test-only API drift the same way as M1). Then run
it; it will fail on fixture mismatches. The guaranteed change is the version string: replace all
four occurrences of `"openapi": "3.0.0"` with `"openapi": "3.1.0"`. Re-run. For any *remaining*
failures, `hspec` prints a diff between expected and actual JSON. For each diff, decide whether
the **actual** output is correct 3.1 (it almost always is, since `openapi-hs` is the source of
truth for the data model) and update the expected literal to match. Do **not** weaken assertions
(e.g. do not delete a comparison); update the expected JSON to the correct 3.1 shape and note
*why* in the Decision Log if the change is non-obvious (e.g. a `nullable: true` becoming a
`"type": ["string","null"]`).

This milestone also adds the two in-process validation layers, so correctness is checked beyond
fixture equality on every test run:

- **Layer 1 (round-trip decode).** Add an `hspec` example that, for each generated document
  `spec`, asserts `eitherDecode (encode spec) == Right spec` (using `Data.Aeson.eitherDecode`
  and `Data.Aeson.encode`). This proves the document survives a parse by `openapi-hs`'s
  `FromJSON OpenApi`, which **rejects** any `openapi` version outside the `3.1.0 … 3.1.1` range
  (enforced at `Data/OpenApi/Internal.hs:1552` in `openapi-hs`). A round-trip failure means the
  emitted JSON is not a structurally valid 3.1 document.
- **Layer 2 (example-conformance).** Add an `hspec` example that calls
  `Servant.OpenApi.Test.validateEveryToJSON (Proxy :: Proxy SampleApi)` for a sample API whose
  response types have `ToJSON` and `Arbitrary` instances. `validateEveryToJSON` generates random
  values of each response type and checks them against the *generated* schema via `openapi-hs`'s
  `validateJSON`; an empty list of errors means the schemas faithfully describe the data. If the
  existing test module already covers this, assert it explicitly rather than leaving it implicit.

Acceptance: `cabal test spec` passes (0 failures) with Layers 1 and 2 present.

### Milestone M3 — Authoritative OpenAPI 3.1 conformance (vacuum)

Scope: prove an emitted document is valid OpenAPI 3.1 according to an **independent** tool, not
just `openapi-hs` and our fixtures. At the end, a generated `openapi.json` passes `vacuum`'s
OpenAPI validation with no errors.

First add a tiny generator so there is a real document to validate. Create `app/GenOpenApi.hs`
with a small but representative Servant API — a couple of routes with a request body, a path
capture, and a response record type that has a `ToSchema` instance (a Todo-style CRUD is ideal,
mirroring the example that the fork removed). Its `main` calls
`Servant.OpenApi.toOpenApi (Proxy :: Proxy SampleApi)` and prints
`Data.ByteString.Lazy.Char8.putStrLn (Data.Aeson.encode spec)`. Register it in
`servant-openapi.cabal` as an `executable gen-openapi` stanza (depends on `base`,
`servant-openapi`, `openapi-hs`, `aeson`, `bytestring`, `servant`, `text`; `default-language:
GHC2024`).

Then generate and validate:

```bash
cabal run gen-openapi > openapi.json
nix run nixpkgs#vacuum-go -- lint -d openapi.json
```

`vacuum lint` structurally validates the document against the OpenAPI specification (3.1 is
detected from the `openapi` field) and exits non-zero if it finds errors. Acceptance: the run
reports **0 errors** (warnings from `vacuum`'s style ruleset are acceptable and need not be
fixed; only spec-validity *errors* gate acceptance). If `vacuum` reports a genuine validity
error, treat the emitted JSON as wrong: trace it back to the schema generation or a fixture and
fix the root cause, recording it in Surprises & Discoveries with the `vacuum` output as evidence.

### Milestone M4 — Reproducible Nix build (optional but tracked)

Scope: make `nix build .#default` build the library through Nix, not just the dev-shell +
`cabal` path. At the end, `nix build .#default` succeeds.

`nix/haskell.nix` builds the default package with
`haskellPackages.callCabal2nix "servant-openapi" inputs.self { }`. That call resolves
dependencies from the nixpkgs Haskell package set, which has no `openapi-hs`. Supply it via the
**unmanaged** `flake.module.nix` (copy from `flake.module.nix.example`), adding `openapi-hs` as
a flake input and overriding the package set so `callCabal2nix` finds it. The exact override is
written in Concrete Steps. Acceptance: `nix build .#default` produces a `result` symlink.

If this milestone proves disproportionately costly (e.g. `openapi-hs` itself needs Nix wiring
it does not yet have), stop, record the blocker in Surprises & Discoveries, and leave the
dev-shell + `cabal` path as the supported build. The library is still "working" by the M2
acceptance.

### Milestone M5 — Finalize documentation

Scope: record the concrete result. Update `CHANGELOG.md`'s `4.0.0` entry to state that the
fork builds and tests green against `openapi-hs`, and adjust any README wording that implied the
port was not yet done. Commit. Acceptance: `git log` shows the milestone commits with
`ExecPlan:` and `Intention:` trailers.


## Concrete Steps

All commands run from the repository root
`/Users/shinzui/Keikaku/bokuno/openapi-hs-project/servant-openapi-hs` unless stated otherwise.

**Enter the dev shell (M1).** Either prefix each command with `nix develop -c`, or enter once:

```bash
nix develop
```

Confirm the toolchain:

```bash
ghc --version    # expect: The Glorious Glasgow Haskell Compilation System, version 9.12.4
cabal --version  # expect: cabal-install version 3.x
```

**Build the library (M1).** This downloads and builds `openapi-hs` from the git pin the first
time (may take several minutes), then the library:

```bash
cabal build lib:servant-openapi
```

Expected tail of a successful run:

```text
[ 9 of 10] Compiling Servant.OpenApi.Internal ...
[10 of 10] Compiling Servant.OpenApi          ...
```

with no `error:` lines. If errors appear, fix per Milestone M1 guidance and re-run.

**Build the test suite (M2).**

```bash
cabal build spec
```

**Run the tests (M2).** They will likely fail before fixtures are updated:

```bash
cabal test spec --test-show-details=direct
```

Update the version strings in `test/Servant/OpenApiSpec.hs`:

```bash
# from the repo root, inside or outside the shell
grep -n '"openapi": "3.0.0"' test/Servant/OpenApiSpec.hs
```

Edit each of those lines to `"openapi": "3.1.0"` (use the editor / Edit tool; there are four
occurrences). Re-run `cabal test spec --test-show-details=direct` and reconcile any remaining
diffs as described in M2. A passing run ends with a line like:

```text
Finished in 0.0xxx seconds
NN examples, 0 failures
```

**Generate and externally validate the spec (M3).** After adding `app/GenOpenApi.hs` and the
`executable gen-openapi` stanza:

```bash
cabal run gen-openapi > openapi.json
nix run nixpkgs#vacuum-go -- lint -d openapi.json
```

Expected: `vacuum` prints a summary and exits 0 with no errors, e.g.:

```text
... openapi.json
No errors or warnings found! Looking good! 🚀
```

(If only style *warnings* appear, that still passes — acceptance gates on **errors**. If the
exact `vacuum` flags differ in the pinned version, run `nix run nixpkgs#vacuum-go -- lint --help`
to confirm; the report's error count is the signal.)

**Nix build (M4).**

```bash
cp flake.module.nix.example flake.module.nix
# edit flake.module.nix per Interfaces and Dependencies below, then:
nix build .#default
ls -l result
```

**Commit (each milestone).** Use Conventional Commits with both trailers:

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: build servant-openapi against openapi-hs (OpenAPI 3.1)

<one or two lines describing the milestone's concrete change>

ExecPlan: docs/plans/1-port-servant-openapi-to-openapi-hs-openapi-3-1.md
Intention: intention_01kvbj3110eanbcej7x38w161z
EOF
)"
```


## Validation and Acceptance

The change is proven, beyond mere compilation, by the build plus three independent layers of
spec validation. "Validation" here means proving the generated document is genuinely a valid
OpenAPI 3.1 document, not merely that it equals a JSON literal we wrote by hand (which could be
wrong). Each layer catches what the previous one cannot.

**Build.** `cabal build lib:servant-openapi` succeeds inside the dev shell. This fails today
only because nothing has built the new dependency yet; after M1 it links cleanly. The
generator and tests build too (`cabal build all`).

**Layer 1 — round-trip decode (automatic, in `cabal test spec`).** For each generated document
`spec`, the suite asserts `eitherDecode (encode spec) == Right spec`. This is meaningful because
`openapi-hs`'s `FromJSON OpenApi` parser **rejects** any `openapi` version outside `3.1.0 …
3.1.1` (it errors at `Data/OpenApi/Internal.hs:1552` with a message like
`The provided version 3.0.0 is out of the allowed range`). So a passing round-trip proves the
version field is valid 3.1.x and the document is structurally decodable under the 3.1 model.
Failure looks like an hspec diff or a `Left "...out of the allowed range..."`.

**Layer 2 — example-conformance (automatic, in `cabal test spec`).** The suite calls
`Servant.OpenApi.Test.validateEveryToJSON (Proxy :: Proxy SampleApi)`, which QuickCheck-generates
values of each response type and validates them against the *generated* schema via `openapi-hs`'s
`validateJSON`. A pass (empty error list) proves the schemas actually describe the data the API
returns — catching "the schema is present but wrong", which fixture equality never detects. A
failure prints the offending value and the schema-validation error.

**Layer 3 — authoritative external conformance (`vacuum`, manual/CI step).** Generate a real
document and lint it with an independent tool that has no knowledge of `openapi-hs`:

```bash
cabal run gen-openapi > openapi.json
nix run nixpkgs#vacuum-go -- lint -d openapi.json
```

Expected: `vacuum` reports **0 errors** (style warnings are acceptable). This is the definitive
"the OpenAPI Initiative would accept this document" check — it would catch a fixture we
"corrected" into something that round-trips through `openapi-hs` yet is still illegal 3.1. A
genuine validity error from `vacuum` means the generated JSON is wrong; trace it to the schema
generation or a fixture and fix the root cause.

**End-to-end sanity (quick spot check).** To eyeball the version without the generator, open
`cabal repl spec` and run:

```haskell
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.OpenApi (OpenApi)
BL.putStrLn (encode (mempty :: OpenApi))
```

Expected: the printed JSON contains `"openapi":"3.1.0"` (not `3.0.0`), confirming the underlying
model is the 3.1 one.

Interpretation: any `error:` from `cabal build`, any `failures` count greater than zero from
`cabal test` (Layers 1–2), or any `vacuum` *error* (Layer 3) means acceptance is not met — read
the message, map it to the relevant Context item, fix, and re-run.


## Idempotence and Recovery

Every step here is safe to repeat. `cabal build` and `cabal test` are idempotent; re-running
after a fix simply recompiles what changed. Editing fixtures is reversible via git
(`git checkout -- test/Servant/OpenApiSpec.hs` restores the last committed version). The
`cabal.project` git pin is fixed to a specific commit, so re-resolving `openapi-hs` always
fetches the same source.

If a build gets into a confusing state, clear the local build products and rebuild:

```bash
cabal clean
cabal build lib:servant-openapi
```

The Nix step (M4) is additive: `flake.module.nix` is unmanaged and can be deleted to revert to
the dev-shell-only build with no other consequence. `nix build` writes only a `result` symlink,
which is git-ignored.

Commit after each milestone so a failed later step never forces redoing earlier work; recover by
checking out the last good commit.


## Interfaces and Dependencies

**Runtime/library dependency.** `openapi-hs >= 4.0 && < 5`, pinned in `cabal.project` to commit
`89e9ed07e0dd3e1eaa9b3efea28b3c722f8c60c8` of `https://github.com/shinzui/openapi-hs.git`. The
modules and names this repo relies on, all confirmed present in that revision:

- `Data.OpenApi` — exports `OpenApi`, `Schema`, `ToSchema`, `toSchema`, `OpenApiType`,
  `OpenApiTypeValue` (`OpenApiTypeSingle` | `OpenApiTypeArray`), `OpenApiItems`
  (`OpenApiItemsObject` | `OpenApiItemsBoolean`), `Referenced (..)`, and the lens accessors used
  in `src/Servant/OpenApi/Internal.hs`.
- `Data.OpenApi.Declare` — the `Declare` monad used to thread schema definitions.
- `Data.OpenApi.Schema.Validation` — `validateJSON` (used by
  `src/Servant/OpenApi/Internal/Test.hs`).
- `Pattern` — type alias `Pattern = Text` (used by the same Test module).

No `import` line changes because `openapi-hs` keeps the `Data.OpenApi.*` namespace.

**Signatures that must still hold at the end (unchanged public API of this package).** The fork
keeps the same surface as upstream `servant-openapi3`; the milestones must not change these:

- `Servant.OpenApi.toOpenApi :: HasOpenApi api => Proxy api -> Data.OpenApi.OpenApi`
- `Servant.OpenApi.Internal.HasOpenApi` class with `toOpenApi`.
- `Servant.OpenApi.Test.validateEveryToJSON` / `validateEveryToJSONWithPatternChecker`
  (re-exported from the Internal test helpers). Used in Layer 2 with signature
  `validateEveryToJSON :: (...) => Proxy api -> [ValidationError]` (an empty list means
  conformant).

**Validation tooling (new in this plan).**

- Layer 1 uses `Data.Aeson.encode` / `Data.Aeson.eitherDecode` plus `openapi-hs`'s
  `instance FromJSON Data.OpenApi.OpenApi`, which enforces the 3.1.x version bound.
- Layer 3 uses `vacuum`, an external OpenAPI linter, run as
  `nix run nixpkgs#vacuum-go -- lint -d openapi.json` (nixpkgs attribute `vacuum-go`, binary
  `vacuum`). Not added to the dev shell; invoked on demand via `nix run`.

**Generator component (new in this plan).** `app/GenOpenApi.hs` with an `executable gen-openapi`
stanza in `servant-openapi.cabal`. It must define a self-contained sample Servant API and a
`main :: IO ()` that prints `Data.Aeson.encode (Servant.OpenApi.toOpenApi (Proxy :: Proxy
SampleApi))` to stdout. Build-depends: `base`, `servant-openapi`, `openapi-hs`, `aeson`,
`bytestring`, `servant`, `text`; `default-language: GHC2024`.

**M4 Nix override.** `flake.module.nix` (copied from `flake.module.nix.example`) must add an
`openapi-hs` source and inject it into the Haskell package set the `callCabal2nix` in
`nix/haskell.nix` draws from. Because new flake *inputs* can only be declared in `flake.nix`'s
top-level `inputs` block (a Nix requirement), adding the input is the one edit to a
seihou-managed file this plan permits; record it in the Decision Log when made. The module then
overrides the package set roughly as:

```nix
# flake.module.nix (sketch — adapt names to nix/haskell.nix once writing it)
{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    # openapi-hs built from its own flake/source and added to the GHC 9.12.4 package set
    # used by callCabal2nix; the default package then resolves the dependency.
    # Concrete wiring to be finalized in M4 against nix/haskell.nix.
  };
}
```

The exact override is intentionally deferred to M4 implementation, where it will be validated by
`nix build .#default` and the working version pasted back into this section as evidence.


## Revision Notes

- 2026-06-17 — Set `default-language: GHC2024` (from `Haskell2010`) in both cabal stanzas, per a
  modernization requirement. Reflected in the cabal file and across Progress, Context (new
  language-edition definition and `MonoLocalBinds` risk), Decision Log, and Milestone M1.

- 2026-06-17 — Defined the spec-validation strategy in answer to "how are we going to validate
  the generated spec?". Added a three-layer approach: (1) in-test round-trip decode through
  `openapi-hs` (enforces the 3.1.x version bound), (2) `validateEveryToJSON` example-conformance,
  (3) external authoritative conformance via `vacuum` (`nix run nixpkgs#vacuum-go -- lint`).
  Added a `gen-openapi` executable (`app/GenOpenApi.hs`) to emit a real document for Layer 3.
  Inserted a new Milestone M3 (external conformance) and renumbered the former M3/M4 (Nix build,
  docs) to M4/M5. Comprehensively reflected in Progress, Decision Log, Plan of Work, Concrete
  Steps, Validation and Acceptance, and Interfaces and Dependencies.
