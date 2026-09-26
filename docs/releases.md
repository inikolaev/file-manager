# macOS releases

Every push to `main` runs `.github/workflows/release.yml`. It tests the project,
builds a release-mode universal executable (arm64 and x86_64), packages
`Commander.app`, verifies its signature and architectures, and publishes a GitHub
Release with the ZIP and a SHA-256 checksum. You can also run **macOS release**
manually from GitHub Actions on `main`. Failed tests/builds do not publish a release.

## Version format

Versions use `YYYY.M.build`, for example `2026.9.42`. The year and month come from
the original workflow creation date in UTC. The final number is GitHub's increasing
run number for this workflow; it does not reset each month or year. Failed runs may
leave gaps. This is calendar versioning, not a semantic compatibility promise.

The version appears in `CFBundleShortVersionString`, the archive filename, the
release title, and its Git tag (`v2026.9.42`). `CFBundleVersion` holds the run number.
Tags associate each release with its exact source commit. GitHub Actions maintains
the counter, so no bot commits or manually updated version file are needed.
Keep this workflow's identity/history to retain its counter.

Re-running an existing workflow keeps its version. Publication uses a draft until
both assets are uploaded; a retry can finish a draft. Already published releases
are left unchanged. Use a new manual run to create another release of the same
commit. Concurrent runs use distinct versions; no push is canceled to make way
for a newer push.

## Local packaging

```sh
APP_VERSION=2026.9.42 APP_BUILD_NUMBER=42 bash scripts/package-app.sh
```

Local builds default to development version `0.1.0`, build `2`. Packaging creates
`dist/Commander-2026.9.42-macOS-universal.zip` and the matching `.zip.sha256` file.
After downloading both release assets into one directory, verify with:

```sh
shasum -a 256 -c Commander-2026.9.42-macOS-universal.zip.sha256
```

## Runner and signing

The workflow uses `macos-15` and Xcode 26.2 (Swift 6.2 or newer), including Apple's
cross-compilation tools for Intel. No custom secrets are needed: the repository's
`GITHUB_TOKEN` receives release-writing permission for the release job.
Organization policies must allow GitHub Actions and that permission.

The app is ad-hoc signed, not Developer ID signed or notarized. Users may need
System Settings → Privacy & Security → Open Anyway for the first launch. Normal
Developer ID distribution can be added later with Apple signing credentials and
notarization; it is independent of this versioning scheme.
