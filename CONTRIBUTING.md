# Contributing

Thanks for helping. Open an issue first for anything larger than a small fix, so the change fits the plugin contract before you write it.

- Pull requests go to `main`. Keep one change to a pull request.
- Run `task pre-push` before you push. It runs vet, the tests, the check that each bundle's `plugin.wasm` rebuilds to its manifest's digest, and the secret scan. `task hooks` arms it as a git hook once per clone. Go and every tool the checks use are pinned in `gate/pins.env`; nothing is installed.
- A released bundle (`plugins/<name>/<version>/`) is never edited. A change to a plugin is a new version, with its own folder, manifest and digest; [plugins/README.md](plugins/README.md) says how to rebuild one.
- The contract itself lives in [gragas-plugin-sdk](https://github.com/birdtable/gragas-plugin-sdk) and [gragas](https://github.com/birdtable/gragas); a change to it is made there first.
- Add a test with the change, and a case under `testdata/cases` where it changes what a plugin answers.

Report a security problem as [SECURITY.md](SECURITY.md) says, never in a public issue.
