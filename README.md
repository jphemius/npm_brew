# npm_brew

Menubar macOS app to detect and update Homebrew packages and global npm packages.

## Install

```bash
./install_app.sh
```

This installs the app in `~/Applications`.

## Publish a release

```bash
./publish_release.sh 1.1.0
```

This:
- updates the app version
- builds the Release app
- creates a zip asset
- creates or updates the GitHub Release

The in-app updater reads GitHub Releases from:

- `jphemius/npm_brew`

To allow auto-update from inside the app, publish each version as a GitHub Release with the generated `.zip` asset attached.
