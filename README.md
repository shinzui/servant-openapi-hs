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

`servant-openapi` and its dependency `openapi-hs` are not yet on Hackage. Pin
both from source. With Cabal, add a `source-repository-package` for each to your
`cabal.project` and depend on the package as usual:

```cabal
build-depends: servant-openapi
```

Import the umbrella module:

```haskell
import Servant.OpenApi
```

Requires GHC **9.12.4** or **9.14.1**.

## Usage

Please refer to the [Haddock documentation](https://hackage.haskell.org/package/servant-openapi3)
for the upstream package; the API surface is unchanged. Generated specifications
can be explored interactively in the [Swagger Editor](https://editor.swagger.io/)
and served via [Swagger UI](https://github.com/swagger-api/swagger-ui).

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
