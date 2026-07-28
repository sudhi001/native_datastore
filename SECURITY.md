# Security Policy

## Supported versions

Security fixes are released against the latest published version on
[pub.dev](https://pub.dev/packages/native_datastore). Please upgrade to the
newest release before reporting, and expect fixes to ship in a new release
rather than a patch to an older line.

| Version | Supported          |
| ------- | ------------------ |
| 1.6.x   | :white_check_mark: |
| < 1.6   | :x:                |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's
[**Report a vulnerability**](https://github.com/sudhi001/native_datastore/security/advisories/new)
flow (Security → Advisories → Report a vulnerability). This opens a private
advisory visible only to the maintainer and you.

When reporting, please include:

- The affected version(s) and platform (Android / iOS).
- A description of the issue and its impact.
- Steps to reproduce, ideally a minimal snippet or project.
- Any suggested remediation, if you have one.

### What to expect

- **Acknowledgement:** within 5 business days.
- **Assessment & updates:** we'll confirm the issue, keep you posted on
  progress, and agree on a coordinated disclosure timeline.
- **Credit:** with your permission, we'll credit you in the release notes and
  advisory.

Please give us a reasonable window to release a fix before any public
disclosure.

## Scope notes

`SecureDatastore` encrypts values **at rest** using platform key management
(iOS Keychain; AndroidKeyStore-backed AES-256-GCM). It is designed to protect
secrets against offline access to the device's storage or backups — not against
a compromised, rooted, or jailbroken runtime in which the app itself is already
under attacker control. See
[**What it protects (and what it doesn't)**](https://github.com/sudhi001/native_datastore#-secure-storage)
in the README for the full threat model.

Reports that reduce to "an attacker with full control of an unlocked, rooted
device can read the app's own secrets" are outside this scope, as that applies
to any on-device storage.
