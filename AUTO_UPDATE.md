# Auto-Update (Sparkle)

SentryReplayDebugger updates itself using [Sparkle 2](https://sparkle-project.org).
There is no backend: the app reads a static `appcast.xml` that is attached to each
GitHub release, and CI regenerates and signs that feed on every release build.

```
release build (CI)
  → notarize + zip
  → generate_appcast (EdDSA-signs the zip, extends the previous feed)
  → appcast.xml attached to the GitHub release
app (any user)
  → polls https://github.com/getsentry/replay-debugger/releases/latest/download/appcast.xml
  → downloads + verifies (Developer ID notarization + EdDSA) + installs on next launch
```

## How it works

- **Feed URL** (`SUFeedURL` in `Info.plist`) points at the `latest/download` permalink,
  so it always resolves to the newest release's `appcast.xml`.
- Each release's appcast is **cumulative**: CI fetches the previously published appcast
  and `generate_appcast` preserves prior versions' entries (default: last 3) while adding
  the new one. No appcast file is committed to the repo.
- Updates carry **two independent trust checks**: the existing Developer ID notarization
  and Sparkle's EdDSA signature (`sparkle:edSignature`), verified against `SUPublicEDKey`.
- The app is sandboxed, so Sparkle's `Downloader.xpc` / `Installer.xpc` are embedded in
  `Sparkle.framework` (handled automatically by SPM) and the two
  `com.apple.security.temporary-exception.mach-lookup.global-name` entitlements
  (`$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki`) are granted in all entitlements files.

## One-time setup (required before the first signed release)

The EdDSA signing key is **not** the Developer ID certificate — it is Sparkle-specific.

### 1. Generate the key pair

Download the Sparkle tools and run `generate_keys`:

```bash
curl -fsSL -o /tmp/sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.2/Sparkle-2.9.2.tar.xz
mkdir -p /tmp/sparkle && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle
/tmp/sparkle/bin/generate_keys
```

This stores the **private** key in your login Keychain and prints the **public** key,
e.g. `<SUPublicEDKey>` value like `zxTzplYA86MHeuxMcI08hdHmF9YICsPMrHxie5emzX0=`.

### 2. Embed the public key in the app

Replace the placeholder in `SentryReplayDebugger/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY</string>   <!-- ← paste the public key -->
```

> `generate_appcast` only emits a signature when the bundle's `SUPublicEDKey` matches the
> signing key. If this is left as the placeholder, releases build but the appcast will be
> **unsigned** and clients will reject the update.

### 3. Add the private key as a CI secret

Export the private key and store it as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret:

```bash
/tmp/sparkle/bin/generate_keys -x /tmp/sparkle_private_key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/sparkle_private_key
rm /tmp/sparkle_private_key            # do not leave the private key on disk
```

Keep a secure backup of the private key (1Password / Keychain). **If it is lost you cannot
ship updates that existing installs will accept** — users would have to reinstall manually.

## Releasing

No change to the release process. `release.yml` → craft still drives it. On a `release/**`
branch CI now also runs `fastlane generate_appcast`, which:

1. downloads the Sparkle CLI tools and **verifies the tarball against a pinned SHA-256
   (fail closed)** before extracting or running anything — the binary is fed the private
   signing key, so an unverified swapped upstream asset could exfiltrate it,
2. copies the notarized zip into a feed directory,
3. seeds it with the previously published appcast (best-effort, for version history),
4. signs and writes `appcast.xml`,
5. places it next to the zip so craft attaches it to the GitHub release.

> **Bumping Sparkle:** when you change the Sparkle SPM version, also update both the
> `sparkle_version` and the pinned digest in the `sparkle_tarball_sha256` map in
> `fastlane/Fastfile`. Confirm the new digest by checking the tarball's `generate_appcast`
> binary is byte-identical to the one in the checksum-verified
> `SourcePackages/artifacts/sparkle/Sparkle/bin/` that SwiftPM resolves.

## Testing an update end-to-end

1. Complete the one-time setup above and merge it.
2. Install the current release (e.g. `0.2.0`).
3. Cut a release one patch higher (`0.2.1`).
4. Launch the old build and choose **SentryReplayDebugger → Check for Updates…**
   (or wait for the automatic background check). It should find `0.2.1`, verify, and
   install on relaunch.

## User-facing controls

- **App menu → Check for Updates…** — manual check.
- **Settings (⌘,) → Updates → Automatically check for updates** — toggles background checks.
