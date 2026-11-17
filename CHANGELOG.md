# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-10

First public release.

### Added
- macOS menu bar app: earbud battery, noise control, audio switching, proximity card, settings.
- QCY MeloBuds Pro support (battery, noise modes, EQ, touch controls, wear detection, game mode).
- Experimental Apple AirPods and Beats support (proximity advertisement decoding); not yet verified on real hardware.
- Android companion app (Kotlin, Jetpack Compose): direct earbud control and phone channel.
- Encrypted Mac-phone channel over the local network (ECDH P-256, HKDF, AES-GCM, SAS confirmation, key pinning); call control, contacts and call history, each off by default.
- `install.sh` installer and CI/release workflows.

[Unreleased]: https://github.com/serdarabdulkadir/ORBIO/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/serdarabdulkadir/ORBIO/releases/tag/v0.1.0
