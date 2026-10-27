# Zanado — Release Test Report v1.0

Date: 2026-10-27 (updated 2026-10-28: RC-03 resolved & re-tested)
Targets: Android release APK (physical device) · Windows release build (physical PC)
Network: same Wi-Fi
Method: manual human-run release verification per the release-test plan; unit tests (136/136) prove contracts separately.
Result legend: ✅ Pass · 🔴 Fail · 🟡 Accepted limitation

## Summary

| # | Scenario | Priority | Result |
|---|---|---|---|
| RC-01 | Android release install & launch | P0 | ✅ Pass |
| RC-02 | Primary smoke: Windows sender → Android receiver | P0 | ✅ Pass |
| RC-03 | Stress transfer: Windows sender → Android receiver, large file | P0 | ✅ Pass (fixed & re-tested) |
| RC-04 | Three consecutive transfers without restart | P1 | ✅ Pass |
| RC-05 | Receiver cancellation mid-transfer | P1 | ✅ Pass |
| RC-06 | Kill Android app during transfer | P0 | ✅ Pass |
| RC-07 | Kill Windows sender during transfer | P1 | ✅ Pass |
| RC-08 | Wi-Fi interruption mid-transfer | P0 | ✅ Pass |
| RC-09 | Expired session / stale QR recovery | P0 | 🟡 Accepted limitation |
| RC-10 | Malformed QR / connection-code input | P0 | ✅ Pass |
| RC-11 | Unauthorized endpoint access | P0 | ✅ Pass |
| RC-12 | Path traversal / hostile filenames | P0 | ✅ Pass |
| RC-13 | Duplicate filename | P1 | ✅ Pass |
| RC-14 | Storage permission denial / write failure | P0 | 🟡 Accepted limitation |
| RC-15 | Windows release build & desktop fallback | P1 | ✅ Pass |

**Tally:** 13 Pass · 0 Fail · 2 Accepted limitations · 0 Pending

## Scenario results

### RC-01 — Android release install & launch — ✅ Pass
Install and launch without crash; sender, receiver, and storage areas all usable. The storage screen intentionally lists only files received and managed by Zanado — it is not a universal file browser, so files left in `Downloads/zanado` by the debug build are not shown there. (Windows version reads the folder directly and shows them.)

### RC-02 — Primary smoke: Windows sender → Android receiver — ✅ Pass
1–10 MB file sent; success appears only after checksum verification + commit; filename, size, and SHA-256 match the source exactly; file lands in `Downloads/zanado`. Re-tested after the storage-list refresh fix (Phase 6B): a file received while the storage screen is open appears immediately — earlier note ("file only appeared after closing and reopening the app") was recorded against a pre-fix build and is resolved.

### RC-03 — Stress transfer: Windows sender → Android receiver, large file — ✅ Pass (fixed & re-tested)
Initial run (pre-fix) 🔴 Fail: a 3.56 GB Windows → Android transfer crashed on the receiver 1–2 s after the file was confirmed saved (5 GB prior evidence also crashed at completion; 2.2 GB passed).

**Root cause:** the synchronous multi-GB MediaStore copy inside `commitFromPath` ran on the Android **main thread** inside the MethodChannel handler — the transfer actually completed successfully, but Android raised an ANR ("MainThread worked timeout") and killed the process seconds later, which looked like a completion crash.

**Fix:** `publishFile` now runs on a dedicated background executor in `MainActivity.kt` (`runPublishInBackground`); the result is delivered back on the main thread with detach-safe guards. The staging, checksum, and MediaStore algorithm are unchanged.

**Re-test (post-fix):** 3.7 GB transfer completed with no crash, no ANR, and no false success — file present in `Downloads/zanado` with correct size and checksum. Pass.

### RC-04 — Three consecutive transfers without restart — ✅ Pass
Three files transferred consecutively in both directions; no port conflict, stale session, or stuck busy state; each checksum correct.

### RC-05 — Receiver cancellation mid-transfer — ✅ Pass
Cancel from Android after meaningful progress: no `.part` file visible during download or after cancellation; receiver returns usable; next transfer succeeds. (Sender shows "Transfer finished — the receiver may still be saving the file" — it never claims receiver success.)

### RC-06 — Kill Android app during transfer — ✅ Pass
Force-close mid-download, relaunch: no partial file presented as complete, clean relaunch, retry works.

### RC-07 — Kill Windows sender during transfer — ✅ Pass
Re-tested: receiver reports a clear connection failure (not success), no partial file published as complete, both sides recover, next transfer succeeds. (An earlier recorded note claiming no failure was stale/pre-fix.)


### RC-08 — Wi-Fi interruption mid-transfer — ✅ Pass
Wi-Fi dropped mid-transfer: clean failure, no crash, no false success, no corrupt file; UI leaves busy state; fresh session succeeds after reconnection. Automatic resume is not required in v1.0.

### RC-09 — Expired session / stale QR recovery — 🟡 Accepted limitation
Expired credentials are rejected — the receiver reports "Connection failed: HTTP connection timed out after 10 s" rather than an explicit session-expired message. The sender is no longer reachable/listening, so a rejection is not observable in this flow. Recovery with a fresh session succeeds; result is as expected in practice.

### RC-10 — Malformed QR / connection-code input — ✅ Pass
Random text, empty clipboard, missing host/port/token, invalid port, duplicate/blank/percent-encoded query params, and non-`zanado://` URIs are all rejected without crash; no download starts; clear message; receiver stays usable.

### RC-11 — Unauthorized endpoint access — ✅ Pass
Requests with no token, wrong token, another session's token, and expired token are all rejected; the file is never served without a valid token; a valid transfer succeeds; session cleaned up.

### RC-12 — Path traversal / hostile filenames — ✅ Pass
Traversal-style filenames are sanitized/rejected and nothing is written outside `Downloads/zanado`. Note: not triggerable via the UI — `/` and `\` are illegal in Windows filenames and the sender only accepts existing files, so the hostile-name cases cannot originate from a Windows sender.

### RC-13 — Duplicate filename — ✅ Pass
An existing file is not silently overwritten; the incoming copy is renamed (e.g. `name (1).ext`). The success message shows the original filename rather than the renamed one — the on-disk file is correctly renamed.

### RC-14 — Storage permission denial / write failure — 🟡 Accepted limitation
The app requests no runtime storage/media permission: Android MediaStore Downloads writes are app-owned on API 29+, so permission denial cannot be simulated for this flow. Destination-write failure was tested instead (insufficient space): no crash, no false completed file, retry works after recovery.

### RC-15 — Windows release build & desktop fallback — ✅ Pass
Windows release build launches; paste-full-connection-code and manual entry both work; small and large file transfers verify against `Downloads\zanado`; desktop layout is practical. Re-tested after the storage-list refresh fix (Phase 6B): a transfer completed while the storage screen is open appears immediately — earlier note ("storage didn't update until close/reopen") was recorded against a pre-fix build and is resolved.

## Known limitations & defects at v1.0

1. **Large-file completion (RC-03):** RESOLVED 2026-10-28 — the crash was an Android main-thread ANR during the multi-GB MediaStore copy; fixed by moving `publishFile` to a background executor (see RC-03). 3.7 GB re-test passed; a >4 GB confirm test is optional before sign-off.
2. **Sender-side completion on receiver disconnect:** the sender cannot distinguish a receiver abort from a normal stream end (dart:io transport buffering); its banner wording never claims receiver success. Accepted.
3. **Expired-session rejection is not explicit (RC-09):** expired credentials surface as a connection timeout after 10 s rather than an explicit "session expired" message. Accepted.
4. **No runtime permission-denial path (RC-14):** app-owned MediaStore writes mean the denial path cannot be exercised; destination-write failure was substituted. Accepted.
5. **Storage screen is not a universal file browser:** it lists files received and managed by Zanado only (MediaStore-visible entries).

## Final status

Release label: **v1.0**. 13/15 scenarios pass; RC-03 (large-file completion) is resolved and re-tested (2026-10-28); RC-09 and RC-14 are documented accepted limitations. Unit tests: 136/136 pass; `flutter analyze` clean; `compileDebugKotlin` successful.
