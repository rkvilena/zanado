# Troubleshooting

Symptom-based guide for runtime and transfer problems. Build/toolchain issues are covered separately in [development.md](development.md).

## Connection and discovery

### Receiver can't connect — "connection refused" or no response

1. **Check the token.** Every request must carry the one-shot session token; a stale or mistyped `zanado://` URI fails the 401/403 checks. Always paste or scan the full URI from the current session.
2. **Session expired.** Sessions live 30 s–30 min (10-minute default) and expire only at request time — a session that expires mid-transfer still completes. Re-pick the file on the sender and start a new session.
3. **Session already used.** Sessions are one-shot: the first receiver that passes all checks wins; a second gets `409 second_receiver`. Restart the sender session.
4. **Same Wi-Fi required.** The server binds `anyIPv4` on the LAN — cellular, VPN, or a guest network with client isolation will block the connection.
5. **Sender firewall.** On Windows, allow inbound connections for Zanado on the local network (private profile). The listener is torn down the moment the session reaches a terminal state, so you cannot reconnect after success/failure.

## Transfer failures

### Receiver shows FAILED (connection)

- Sender stopped the app or closed the connection mid-stream → the receiver aborts, deletes the `.part`, and reports a connection failure. Correct behavior; retry from the sender.
- Stalled sender: the receiver enforces a 30 s idle timeout on headers and body reads. A hung transfer self-aborts after ~30 s instead of hanging the busy screen forever.
- A mid-transfer network abort is classified as a **connection** failure (not storage) — if you ever see storage errors for a network drop, that's a misclassification bug.

### Receiver shows "File verification failed" (checksum)

The streamed SHA-256 computed by the receiver did not match the header value. The receiver **deletes the committed file** — nothing partial is ever presented as complete. Causes: corrupted Wi-Fi transfer, or the source file was modified between pick and serve. Retry the transfer.

### Receiver shows a size-mismatch error

The received byte count didn't match the header. A truncated file can never be committed (size is checked before the rename). Usually a connection drop; retry.

### Sender says "Transfer finished" but the file isn't on the receiver

**Known accepted behavior, not a bug.** `dart:io`'s transport can buffer an entire body before a vanished receiver aborts, so the sender may mark `completed` "into the void" — especially on loopback/fast links. The sender banner deliberately says "the receiver may still be saving the file." **Success must always be judged by the receiver's storage list**, never by the sender's status. Receiver-side checksum + commit is authoritative.

## Storage

### File doesn't appear in the receiver's list after a transfer

- The storage list refreshes via a revision counter bumped only after a successful commit. If the list looks stale, leave and reopen the screen (the provider rebuilds on reopen).
- On Android the commit copies the `.part` into MediaStore. A multi-GB copy runs on a background executor, so completion may lag a few seconds after the receiver reports success — check the system Downloads/zanado folder.

### Android: app killed seconds after a large transfer succeeds (ANR)

Fixed 2026-10-28 (see ADR-012): the multi-GB MediaStore copy ran on the main thread inside a MethodChannel handler and triggered a "MainThread worked timeout" ANR **after** the copy completed. If you rebuild from source and reintroduce this symptom, verify `MainActivity.kt` still publishes via `runPublishInBackground` on the dedicated executor. Rule: never do multi-GB synchronous I/O on the Android main thread.

### Zero-byte or leftover `.part` files

A `.part` present at startup is always stale (single-receiver enforcement means no transfer can be mid-flight). Startup cleanup (`cleanupStaleParts`) deletes them automatically. If you see one persisting, it's a cleanup bug.

### Android permission prompts

Zanado writes via MediaStore with per-file user consent (`ACTION_OPEN_DOCUMENT`-style selection); no `MANAGE_EXTERNAL_STORAGE` and no folder scanning. If saving fails with a storage error, the user declined the system dialog — retry the transfer and accept it.

## Known UX behaviors (not failures)

- **"Preparing file…" takes a while on large files** — the sender hashes the whole file before accepting a session (determinate progress shown). On multi-GB files this is minutes of pure hashing.
- **Post-download wait on the receiver** (~3 s on a 700 MB file) is the disk flush/`.part` rename commit inside storage — same as a browser committing a finished download. No status is shown for it by design.
- **Sender "completed" is not proof of receiver success** — see the connection section above.

## Build and tooling

See [development.md](development.md) — it covers the toolchain table, the clean-build procedure, the failure-classification table, and the seven known build failure modes (Windows file locks, unauthorized device, multiple devices, SDK location, signature mismatch, release INTERNET permission, Kotlin cross-drive crash).

Quick sanity checks before reporting a runtime bug:

```bash
flutter analyze   # must be zero issues
flutter test      # 136 tests pass
flutter doctor -v # toolchain matches the development.md table
```
