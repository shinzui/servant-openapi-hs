# servant-openapi

[![License BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](/LICENSE)

Generate an [OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0) specification for
your [Servant](https://github.com/haskell-servant/servant) API, and partially
test that the API conforms to its specification.

> **Fork notice.** `servant-openapi` is a fork of
> [`biocad/servant-openapi3`](https://github.com/biocad/servant-openapi3), which
> targets OpenAPI 3.0. This fork retargets it at OpenAPI 3.1 by building on
> [`openapi-hs`](https://github.com/shinzui/openapi-hs) (a fork of
> [`biocad/openapi3`](https://github.com/biocad/openapi3)) instead of `openapi3`.
> The Haskell module namespace is unchanged (`Servant.OpenApi.*`), and because
> `openapi-hs` keeps the `Data.OpenApi.*` namespace, migrating is usually just a
> dependency-name swap: `servant-openapi3` → `servant-openapi` and `openapi3` →
> `openapi-hs`. The fork keeps the upstream [BSD-3-Clause license](#license) and
> copyright.

---

## Motivation

OpenAPI is a language-agnostic format for describing and documenting HTTP APIs.
This package derives an OpenAPI 3.1 specification directly from a Servant API
type, so the description stays in sync with the server, and provides combinators
to test that handlers conform to the generated schema.

A generated specification can then be used to

- display interactive documentation with [Swagger UI](http://swagger.io/swagger-ui/);
- generate clients and servers in many languages with [OpenAPI Generator](https://openapi-generator.tech/);
- and [many other things](http://swagger.io/open-source-integrations/).

## Installation

> **Pre-release.** The first Hackage release is still in preparation. Until it
> is published, depend on this repository directly (see
> [Building from source](#building-from-source) below); the instructions in this
> section describe the package once it is on Hackage.

Add `servant-openapi` to your package's `build-depends`:

```cabal
build-depends: servant-openapi
```

Its OpenAPI 3.1 data model comes from
[`openapi-hs`](https://hackage.haskell.org/package/openapi-hs), which is pulled
in automatically as a transitive dependency.

Import the umbrella module:

```haskell
import Servant.OpenApi
```

Requires GHC **9.12.4** or **9.14.1**.

<a id="building-from-source"></a>
> **Building from source.** Until the first Hackage release, depend on this
> repository directly by adding a `source-repository-package` stanza for
> `servant-openapi` to your `cabal.project`:
>
> ```cabal
> source-repository-package
>     type:     git
>     location: https://github.com/shinzui/servant-openapi.git
>     tag:      <commit-sha>
> ```
>
> Its `openapi-hs` dependency resolves from Hackage automatically.

## Usage

Derive an OpenAPI 3.1 document from a Servant API type with `toOpenApi`:

```haskell
import Data.Aeson (encode)
import Data.OpenApi (OpenApi)
import Data.Proxy (Proxy (..))
import Servant.OpenApi (toOpenApi)

spec :: OpenApi
spec = toOpenApi (Proxy :: Proxy MyApi)
-- encode spec  ==>  {"openapi":"3.1.0", ...}
```

A runnable example lives in [`app/GenOpenApi.hs`](app/GenOpenApi.hs), built as
the `gen-openapi` executable, which prints a complete Todo-CRUD document:

```bash
cabal run gen-openapi > openapi.json
```

The full API surface is unchanged from upstream; see the
[Haddock documentation](https://hackage.haskell.org/package/servant-openapi).
Generated specifications can be explored interactively in the
[Swagger Editor](https://editor.swagger.io/) and served via
[Swagger UI](https://github.com/swagger-api/swagger-ui).

## Validation

Generated documents are checked at three levels:

1. **Round-trip** — the test suite decodes each generated document back through
   `openapi-hs`'s `FromJSON OpenApi`, which rejects any `openapi` version outside
   `3.1.0 … 3.1.1`, then compares the result for semantic equality.
2. **Example-conformance** — `Servant.OpenApi.Test.validateEveryToJSON` checks
   that random values of each response type validate against the generated
   schema.
3. **Authoritative conformance** — the `gen-openapi` output lints cleanly under
   [`vacuum`](https://quobix.com/vacuum/):

   ```bash
   cabal run gen-openapi > openapi.json
   nix run nixpkgs#vacuum-go -- lint -d openapi.json
   ```

## Contributing

Bug reports, fixes, documentation improvements, and other contributions are
welcome. Please open an issue or pull request on the
[GitHub issue tracker](https://github.com/shinzui/servant-openapi/issues).

## License

`servant-openapi` retains the original **BSD-3-Clause** license of the upstream
[`servant-openapi3`](https://github.com/biocad/servant-openapi3) project,
including its copyright. See the [`LICENSE`](/LICENSE) file for the full text;
this fork's changes are released under the same terms.

---

*Originally derived from work by the Servant contributors (David Johnson,
Nickolay Kudasov, Maxim Koltsov, and others).*
