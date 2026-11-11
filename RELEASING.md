# Releasing Even Dimmer

Notes for maintainers. Users don't need any of this.

## Building

You need the Xcode command line tools (`xcode-select --install`).

```bash
scripts/build-app.sh
```

This creates `build/Even Dimmer.app` and `build/EvenDimmer.zip`. Local builds have auto-updates switched off.

Options (environment variables):

- `SIGN_ID="…"`: sign with a certificate instead of ad-hoc. Even a self-signed code-signing certificate helps, because macOS then keeps the Accessibility permission across updates.
- `HARDENED_RUNTIME=1`: sign with the hardened runtime. This is only needed for notarization, together with a Developer ID in `SIGN_ID`.

## Releasing a new version

Releases use [Sparkle](https://sparkle-project.org) for auto-updates and a Homebrew tap for installs.

**One-time setup:**

1. Create the update-signing key. It's stored in your login keychain, and every future update must be signed with it, so keep a backup (`generate_keys -x <file>` exports it):

   ```bash
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. Create a public GitHub repo named `homebrew-tap` for the Homebrew cask.

**Each release:**

```bash
scripts/release.sh 1.1.0 --publish
```

This:

1. sets the version (and bumps the build number) in `Resources/Info.plist`
2. builds the app with the update key's public half included
3. writes the update feed (`appcast.xml`)
4. updates `packaging/homebrew/even-dimmer.rb`
5. creates the GitHub release with the zip and the feed

Leave out `--publish` to build everything without publishing. Afterwards, commit the version bump and copy the cask file into the tap repo's `Casks/` folder.

The app reads its update feed from `https://github.com/isjl/even-dimmer/releases/latest/download/appcast.xml` (`SUFeedURL` in `Resources/Info.plist`). If you fork the project, change it there, in `GITHUB_REPO` for `scripts/release.sh`, and in the cask.

The app isn't notarized, so the cask removes macOS's download quarantine flag when it installs. Otherwise macOS would refuse to open the app.

## Updating the README demo GIF

Screen recordings can't capture the dimming, so `docs/images/demo.gif` is a simulation built from real popup screenshots:

1. Capture the popup (Screen tab) at slider positions 0.35, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05 and 0.0. Name the files `pop_0.35.png` … `pop_0.0.png`, and use `screencapture -l <window id>` for a clean background.
2. Build the frames and encode them:

   ```bash
   python3 scripts/make_demo_gif.py <screenshots folder> build/gif
   cd build/gif && ffmpeg -f concat -safe 0 -i concat.txt \
     -vf "split[a][b];[a]palettegen=stats_mode=single[p];[b][p]paletteuse=new=1" -loop 0 ../../docs/images/demo.gif
   ```
