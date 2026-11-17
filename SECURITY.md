# Security Policy

## Reporting a vulnerability

Please do not open a public issue for security problems.

Use GitHub's private vulnerability reporting: open the repository's **Security** tab, then **Report a vulnerability** (https://github.com/serdarabdulkadir/ORBIO/security/advisories/new). Include what you found, steps to reproduce, affected version, and impact. Do not include other people's personal data.

We aim to acknowledge reports within a few days and to coordinate a fix and disclosure with you.

## Scope

- The Mac-phone channel (pairing, key pinning, encryption): [docs/telefon-kanali.md](docs/telefon-kanali.md).
- The installer (`install.sh`) and release artifacts (checksums).
- Permission handling on macOS and Android.

## Supported versions

Only the latest release receives fixes.

## Notes

The macOS app is ad-hoc signed and not notarized (see README). That is a known limitation, not a vulnerability.
