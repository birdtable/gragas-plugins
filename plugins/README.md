# plugins

The plugins of plugin contract 1. Each is a Go module (`plugins/<tool>`); a bundle is `plugins/<tool>/<version>/`:

    plugin.yaml          the manifest, with the digest of plugin.wasm
    plugin.wasm          the module, built for wasip1
    testdata/cases       a request and its response, one folder a case (replayed by the module's tests)
    testdata/fixtures    the planted and the clean files a run reads
    testdata/recordings  made by `gragas plugin record`

Rebuild the module, then write its digest into `plugin.yaml` (`TestManifestDigest` refuses a stale one):

    GOWORK=off CGO_ENABLED=0 GOOS=wasip1 GOARCH=wasm go -C plugins/<tool> build -trimpath -buildvcs=false -ldflags=-buildid= -o <version>/plugin.wasm .
    shasum -a 256 plugins/<tool>/<version>/plugin.wasm

The digests in the manifests come from go1.27.4, the pin of `gate/pins.env`; a build under another Go gives another digest.
Build with the pin (`GOTOOLCHAIN=go1.27.4`).

The ESLint plugin wraps the SDK's plan: the config round runs `--print-config` on the plugin's own `probe.js` at the
sandboxed level, since an ESLint config is code.
