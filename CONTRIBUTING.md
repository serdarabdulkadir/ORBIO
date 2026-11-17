# Contributing to ORBIO

Thanks for helping. ORBIO is an independent open source project (MIT).

## Build and test

macOS 15+, Swift 6 toolchain:

```bash
swift build
swift test
scripts/paketle.sh --ac     # local ORBIO.app in ~/Applications
```

Android (JDK 17, Android SDK 35, set `ANDROID_HOME`):

```bash
cd Android
./gradlew testDebugUnitTest assembleDebug
```

Please run the relevant build and tests before opening a pull request. New logic in `Sources/EkosistemCore` (and the pure Kotlin packages) needs unit tests.

## Protocol bytes: no unverified meanings

Earbud protocols here are reverse engineered for interoperability with devices you own.

- Do not document or implement a byte meaning you have not observed on a real device or in a source you can cite.
- If a meaning is plausible but unverified, label it **experimental** in code comments, docs and UI, and say how you tested (or that you did not).
- Bug and device reports should include model, firmware, and the raw bytes or log that show the behavior (use the device-support issue template).
- Never include personal identifiers (serial numbers, MAC addresses, phone numbers) in issues or commits; redact them.

## No GPL code copying

Do not copy code from GPL (or otherwise incompatible) projects such as Gadgetbridge or OpenPods. Describing observed behavior and citing a method is fine; pasting or translating their source is not. If you are unsure about a source's license, ask first. Do not add vendor APK code, assets or keys.

## Scope

Own devices and interoperability only: no decrypting protected fields, no clients for vendor cloud servers, no identity spoofing.

## Pull requests

1. Open an issue first for larger changes.
2. Fork, branch from `main`, keep the change focused (no unrelated reformatting).
3. Match existing style and naming; user-visible text follows the project's existing language conventions.
4. Fill in the pull request template; CI (macOS build + tests, Android tests + build) must pass.
5. A maintainer reviews; squash merge is the default.

By contributing you agree that your contribution is licensed under the MIT License.
