# Release notes — v1.0

Status as of **2026-10-28**. This document summarizes what shipped, what was verified, and the known limitations accepted for v1.0. Full verification evidence: [docs/release-test-v1.0.md](release-test-v1.0.md) (13/15 checks pass; 2 accepted limitations).

## What shipped in v1.0

- **End-to-end LAN transfer** Android ↔ Windows over the same Wi-Fi, device-verified up to 3.7 GB.
- **QR pairing** (Android camera) and paste/manual entry on Windows via the `zanado://transfer` URI.
- **Integrity verification:** receiver-side SHA-256 + size check before commit; checksum failure deletes the file and shows a dedicated error card.
- **User-visible storage:** `Downloads/zanado` on both platforms (MediaStore on Android, no storage permissions on API 29+).
- **Hardening:** one-shot token-gated server, session expiry, 30 s receiver idle timeout, stale `.part` startup sweep, duplicate-name auto-rename, path-traversal sanitization.
- **Live storage list:** refreshes via a revision counter after a successful commit (ADR-011).
- **Adaptive UX:** platform-decided layouts (desktop composition on Windows, stacked touch layout on Android, ADR-013).

## Critical fixes since the first release candidate

| Defect | Fix | ADR |
|---|---|---|
| **RC-03** — Android app killed after a 3.7 GB transfer succeeded | Multi-GB MediaStore copy moved off the main thread into a background executor; device-verified clean | ADR-012 |
| **RC-08** — receiver hung forever on a stalled sender | 30 s idle timeout on headers and body; stale `.part` cleanup at startup | ADR-015 |
| **RC-08** — misleading sender success banner | Banner never claims receiver success; wording points to the receiver library | ADR-015 |

## Verification status

- `flutter analyze`: zero issues. `flutter test`: **136/136 pass** (as of 2026-10-28, post RC-03 marker cleanup).
- Release-test report: **13/15 checks pass** — the two non-passes are accepted limitations, not defects.
- Device-verified highlights: 3.7 GB receive with no ANR (Android), 2.2 GB Windows↔Android, Wi-Fi-drop mid-transfer, sender shutdown mid-transfer, expiry mid-transfer.

## Accepted limitations

1. **Sender cannot always detect receiver abort** (dart:io transport buffering) — the sender banner never claims receiver success; receiver-side storage is the only source of truth. Fix requires a protocol change (receiver-completion acknowledgment).
2. **Android-sender → Windows-receiver cancellation** leaves a partial file on Windows — a separate P1 follow-up, not a release blocker.

## Known open items (not blockers)

- One transfer >4 GB is to be done after v1.0 release.
- `MainActivity.kt` modularization (handler / repository / executor) is a refactor task. Also planned for after v1.0 release

## Terminology used across the docs

| Term | Meaning |
|---|---|
| **Session** | One-shot transfer lifecycle: sender serves one file to exactly one receiver |
| **Token** | 24-character, 120-bit secure-random credential required by the file endpoint |
| **`zanado://` payload** | Custom URI scheme carrying host, port, token, and expiry for pairing |
| **`.part`** | Staging file written before the final commit; renamed on success, deleted on failure |
| **Commit** | Final storage step after verification: rename on Windows, MediaStore publish on Android |
| **Storage revision** | Counter bumped after a successful commit that refreshes the storage list |
