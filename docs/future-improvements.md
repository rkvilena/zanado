# Future improvements

Deferred ideas from the original roadmap and post-release testing. Re-prioritized 2026-10-28: the first three are ordered; the rest are unordered (no priority implied). Items marked **deferred 2026-10-27** were parked when the media-playback MVP milestone was re-allocated (see [architectural-decisions.md](architectural-decisions.md) ADR-014).

## Prioritized

1. **Multiple-file transfer UX polish.** The sender/receiver current flow was single-file-first: per-file progress on the receiver, queue display on the sender, partial-failure reporting ("3 of 5 transferred"), per-file retry and duplicate handling.
2. **Receiver-completion acknowledgment.** Sender "completed" is not proof the receiver stored the file (see [troubleshooting.md](troubleshooting.md)); a terminal-status ack from the receiver would make the sender banner trustworthy. Protocol change: sender polls or receiver posts final status before the session closes.
3. **Media playback / library.** Deferred 2026-10-27. Original design (`just_audio`/`video_player`) replaced by Android content URIs (`ACTION_OPEN_DOCUMENT` per-file selection) — no folder scan, no `MANAGE_EXTERNAL_STORAGE`, no copy-import-before-play. Includes the "Open with Zanado" / `ACTION_VIEW` entry point.

## Unordered

- **Resumable transfers.** The receiver already streams into a `.part` file with a known byte offset; resuming would need sender-side offset negotiation in the protocol. Builds directly on the ADR-015 interrupted-transfer model.
- **Transport security.** Cleartext HTTP + `anyIPv4` bind is accepted for LAN scope with a 120-bit one-shot token. Options: TLS with self-signed certs, a short human-friendly pairing code instead of a QR, or both. Also consider constant-time token comparison (practically irrelevant on a LAN, flagged in code review).
- **MainActivity.kt modularization.** Split the MethodChannel handler / MediaStore repository / publish executor into separate classes; also an optional >4 GB receive confirmation test.
- **Transfer UX polish.** Sender-side progress/cancel during an active session, richer failure reasons in the receiver banner, transfer history.
- **Additional platforms.** macOS/Linux via the same `LocalStorageRepository` pattern; requires a platform check update in `createStorageRepository()`.
