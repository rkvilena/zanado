# Architectural decisions

Each decision below records **what** was chosen, **why**, and the trade-off accepted. Decisions are numbered in build order; later decisions build on earlier ones. Deferred ideas live in [Future improvements](future-improvements.md).

These decision is just a log of my development process in building Zanado.

---

## ADR-001 — Flutter as the single codebase for Android + Windows

**Decision.** Build both targets with one Flutter/Dart codebase; Android is the primary device target, Windows the desktop target.

**Why.** The product is inherently multi-device (sender on one platform, receiver on another), so two native codebases would double the protocol, storage, and UI work. Shared domain models and the shared wire contract (`lib/core/constants/transfer_protocol.dart`) mean both sides cannot drift apart silently.

**Trade-off.** Platform differences cannot be avoided entirely: Android needs a MethodChannel for MediaStore, and layouts must be composed per platform (`defaultTargetPlatform`), not just resized.

---

## ADR-002 — Prove the LAN transfer before polishing the UI

**Decision.** The roadmap ordered storage (MVP 1) and raw end-to-end transfer over real Wi-Fi (MVP 2) before transfer UI (MVP 3), QR pairing (MVP 4), and UX refinement (MVP 5). Debug screens were acceptable until then.

**Why.** The network path was the highest-risk, least-predictable part (device behavior, Wi-Fi quirks, transport buffering). De-risking it first prevented building polished screens around an unproven core — a failure there would have invalidated everything downstream.

**Trade-off.** Early milestones shipped debug-only UI, which delayed visible polish but kept each milestone independently verifiable on physical devices.

---

## ADR-003 — `dart:io` HTTP server/client, no external transfer service

**Decision.** The sender runs a one-shot `HttpServer` on an ephemeral port; the receiver uses `HttpClient`. No cloud relay, no third-party transfer library.

**Why.** The product's core promise is fully offline transfer. `dart:io` is built into Dart, streams with backpressure, and adds zero dependencies. Owning the protocol also gave exact control over the integrity and session-lifecycle behavior that defines the app.

**Trade-off.** Everything around the protocol — auth, expiry, cleanup, error codes, streaming discipline — is owned and tested by this project rather than inherited from a library.

---

## ADR-004 — Short-lived random token over plain HTTP

**Decision.** Every receiver request carries `X-Zanado-Token` (a 24-character unambiguous-alphabet token). Sessions are clamped to 30 s–30 min (default 10 min). Transport is plain HTTP.

**Why.** A bare LAN URL is trivially discoverable and usable by anything else on the network. A random short-lived token gives practical access control: missing/unknown/expired tokens are rejected (401/403), and the one-shot server closes the listener after any terminal state so the token/port are never reused.

**Trade-off.** Plain HTTP does not encrypt bytes on the wire. Zanado is explicitly for trusted local networks; TLS is a planned improvement (see [future-improvements](future-improvements.md) #5), framed as measured throughput rather than an untested "near-zero overhead" claim.

---

## ADR-005 — Custom `zanado://transfer` payload instead of a raw URL

**Decision.** The QR code encodes `zanado://transfer?host=&port=&token=&expires=` — a typed payload with validation and expiry, not a bare HTTP URL.

**Why.** A custom scheme separates pairing data from a URL the OS might hijack or the user might mistype into a browser, and gives the payload a stable, versioned shape that can evolve (e.g., adding a short pairing code later) without breaking the transfer endpoint.

**Trade-off.** Both platforms must parse and validate the same scheme — a protocol change, not a UI change. Windows receivers (no camera) use paste-a-full-URI or manual entry as fallback.

---

## ADR-006 — User-visible `Downloads/zanado` storage (SHAREit-like)

**Decision.** Received files land in `Downloads/zanado` on both platforms: Windows writes directly to the user's Downloads folder; Android publishes through MediaStore into public `Download/zanado/`. The original app-private sandbox was deliberately relocated (MVP 1.1).

**Why.** Users expect transferred files where they can find them — a hidden sandbox feels like a black box and forces a manual export step for every file. MediaStore on API 29+ needs no storage permissions: app-owned contributions are readable/deletable by the app itself.

**Trade-off.** The Android storage screen can only list MediaStore-visible entries, so it is honestly framed as "files received and managed by Zanado," not a universal file browser.

---

## ADR-007 — `.part`-then-rename on every write path

**Decision.** Streamed bytes are written to a temporary `.part` file and only renamed/published after verification. Android uses MediaStore's `IS_PENDING` flag as the equivalent of the `.part` gate.

**Why.** This is the single invariant that prevents a cancelled, failed, or checksum-mismatched download from ever appearing as a completed file. A failed write leaves nothing behind; startup sweeps any stale `.part` from a killed process (only one transfer runs at a time, so any leftover is stale).

**Trade-off.** Windows cannot delete an open file, so the write stream must be closed before any error-path deletion — a subtle, tested detail.

---

## ADR-008 — Receiver-side SHA-256 verification is authoritative

**Decision.** The sender streams its file's real size + SHA-256 via response headers; the receiver hashes the bytes as they stream, verifies size and checksum against the headers, and deletes the committed file on mismatch. Sender "completed" is never treated as proof of receiver success.

**Why.** A finished HTTP stream does not guarantee the receiver got the correct bytes — transport buffering can hide a vanished receiver (device-confirmed). Only the receiver's on-disk verification can prove integrity, so the receiver's success signal is the only one the UI trusts.

**Trade-off.** The sender's success banner must be worded carefully ("the receiver may still be saving the file"); full receiver-completion acknowledgment is deferred as a future improvement.

---

## ADR-009 — Platform-specific storage behind one interface

**Decision.** `StorageRepository` (list / saveFromFile / saveStream / delete / directoryPath) is the only storage contract; `LocalStorageRepository` (Windows) and `MediaStorageRepository` (Android) implement it, selected at startup in `createStorageRepository()`.

**Why.** Windows and Android have fundamentally different storage APIs. A single interface keeps controllers, receivers, and tests platform-agnostic, and the composition root is the only place that checks the platform.

**Trade-off.** Any new storage behavior (e.g., rename, metadata) must be implemented twice, or kept out of the interface entirely.

---

## ADR-010 — Riverpod for state management

**Decision.** All transfer and storage state flows through Riverpod controllers (Notifier/AsyncNotifier).

**Why.** Transfers have many asynchronous states (hashing, waiting, streaming, verifying, terminal states) and several independent actors (sender, receiver, storage list) that must react to each other without tight coupling. Providers make dependency injection explicit and testable — including the composition-root override that keeps tests free of platform bindings.

**Trade-off.** Widget tests must respect binding invariants (e.g., `debugDefaultTargetPlatformOverride` must be reset at the end of the test body, not in a tearDown).

---

## ADR-011 — Storage list refresh via revision invalidation

**Decision.** A shared `storageListRevisionProvider` is bumped only after a successful commit (`DownloadSuccess`); the storage list watches it and reloads when it changes. The provider is `autoDispose`, so reopening the screen also rebuilds it.

**Why.** A completed transfer can happen while the storage screen is already mounted; "refresh on reopen" alone left the UI stale (device-verified in Phase 6B). A revision counter is a minimal, explicit consistency mechanism: success refreshes, failure/cancellation does not. It lives in the shared wiring layer (`lib/data/storage/storage_providers.dart`) because a features/transfer → features/storage import would cross feature internals.

**Trade-off.** A monotonically increasing counter is a coarse signal — it triggers a full re-fetch rather than a targeted insert — but the list is small, so correctness beats cleverness.

---

## ADR-012 — Android MediaStore publication off the main thread

**Decision.** The multi-GB MediaStore copy in `commitFromPath` runs on a dedicated background executor (`runPublishInBackground`) in `MainActivity.kt`, with the result posted back to the main thread via `mainHandler` and detach-safe guards.

**Why.** The synchronous copy inside the MethodChannel handler blocked the Android main thread long enough to trigger an ANR ("MainThread worked timeout") that **killed the process after the transfer had already succeeded** — a 3.56 GB receive crashed 1–2 s after completion, which looked like a false completion crash. Fixed 2026-10-28; a 3.7 GB re-test passed with no ANR. Durable rule: **MethodChannel handlers must never do multi-GB synchronous I/O on the main thread.**

**Trade-off.** The staging/checksum/MediaStore algorithm was unchanged; only the threading moved. Release verification still requires physical-device testing of large files, since the failure mode is invisible to unit tests.

---

## ADR-013 — Platform-decided adaptive layouts

**Decision.** Layout composition is chosen by `defaultTargetPlatform` — desktop composition on Windows, stacked touch layout on Android — with window width only tuning details inside the Windows layout (`ZanadoLayout.wideFormBreakpoint = 480`, content column `maxContentWidth = 720`).

**Why.** Android and Windows have different interaction models (touch vs. keyboard/clipboard), so the platform is a more reliable signal than width alone; a wide Android window would still be a touch UI. Width remains the right tool for resizing the desktop composition.

**Trade-off.** Two layout compositions to maintain; a mid-size window on Windows follows the desktop composition rather than collapsing to mobile.

---

## ADR-014 — Defer media playback; core is transfer

**Decision.** The original MVP 5 milestone (library + media playback with `just_audio`/`video_player`) was moved to future improvements (2026-10-27). The MVP 5 slot was re-allocated to UX refinement and observable integrity verification.

**Why.** The app's core product is reliable transfer; playback is secondary convenience and would have added dependency/platform risk before the core was proven. When the player milestone starts, it will be built on Android content URIs (`ACTION_OPEN_DOCUMENT` per-file selection) — no folder scan, no `MANAGE_EXTERNAL_STORAGE`, no copy-import-before-play — so the storage screen stays an honest "files received and managed by Zanado" list rather than a media library.

**Trade-off.** v1.0 ships no player; the "Open with Zanado" / `ACTION_VIEW` entry point is likewise parked.

---

## ADR-015 — Interrupted transfer stops everything

**Decision.** An interrupted transfer must fail cleanly everywhere: the receiver aborts with a connection failure, all partial artifacts (`.part`, pending MediaStore entries) are removed, and the sender never claims receiver success. The receiver additionally enforces a 30 s idle timeout on stalled connections.

**Why.** Half-killed state (a phantom file in Downloads, a stuck busy screen, a permanently listening server) is the worst failure mode for a transfer app — device testing (RC-06/RC-08) showed the kill-app and Wi-Fi-loss scenarios are the common ones, not graceful shutdowns.

**Trade-off.** Receiver-side cleanup is aggressive by design; a resumed transfer would need to build on top of the `.part` offset model (see future-improvements #3).

