<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/mark/gragas-plugins-banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/mark/gragas-plugins-banner-light.svg">
    <img src="docs/mark/gragas-plugins-banner-light.svg" width="422" alt="gragas-plugins: the gragas feather with a plug, then a coral bird in flight and the name">
  </picture>
</p>

The plugins that connect [gragas](https://github.com/birdtable/gragas) to each tool: `ast-grep`, `eslint`, `golangci-lint` and `tsc`.

gragas names no tool. A plugin is a WebAssembly module with a `plugin.yaml` manifest. It answers gragas's five operations (`plan`, `entries`, `findings`, `rank` and `preset`) for one tool, and gragas runs it with [wazero](https://wazero.io). The plugins are written with [gragas-plugin-sdk](https://github.com/birdtable/gragas-plugin-sdk); its `declarative` package covers a tool whose rules are a flat list, with no code of your own.

## Layout

A plugin is a Go module at `plugins/<name>/` whose main package builds for `wasip1`. A release of it is a bundle, `plugins/<name>/<version>/`:

    plugin.yaml          the manifest, with the digest of plugin.wasm
    plugin.wasm          the module, built for wasip1
    testdata/cases       a request and its response, one folder a case
    testdata/fixtures    the planted and the clean files a run reads
    testdata/recordings  made by `gragas plugin record`

`plugins/README.md` says how to rebuild a bundle and write its digest.

## Develop

`task pre-push` runs the checks: vet and tests of every module (in the workspace and again with it off), the build of each bundle's `plugin.wasm` from its folder with the pinned Go (the build is a function of the module's tree, so anyone rebuilds it byte for byte and gets the manifest's digest), and the secret scan. Every tool the checks use is pinned in `gate/pins.env` and runs with `go run`, so nothing is installed. `task hooks` runs them on commit and push.

## Releases

A bundle's tag is `<name>/v<version>`, annotated, on a commit of `main`, and its message carries the bundle's digest. `RELEASES` lists each release with its tag object, commit and digest, so a tag moved or made again is caught. `gate/release.sh` makes and checks them.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md). Report a vulnerability as [SECURITY.md](SECURITY.md) says.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
