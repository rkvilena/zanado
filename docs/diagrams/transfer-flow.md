# Transfer flow

The full lifecycle of one LAN transfer, as implemented in v1.0. Sender side follows `lib/features/transfer/transfer_controller.dart` → `lib/data/network/transfer_server.dart`; receiver side follows `lib/data/network/transfer_receiver.dart` → the storage repository.

## Sender

```mermaid
sequenceDiagram
    participant U as SenderController
    participant S as TransferServer
    participant SES as TransferSession
    participant F as Source file
    participant R as Receiver

    U->>U: pickFile — stream file, compute real sizeBytes + sha-256
    U->>SES: TransferSession.create (token minted, duration clamped 30s–30min)
    U->>S: start() — HttpServer.bind(anyIPv4, ephemeral port)
    R->>S: GET /zanado/v1/file
    S->>S: 400 version → 401 token → 403 expired → 409 second receiver → 404 file
    S-->>R: 200 + Content-Length, X-Zanado-Checksum, X-Zanado-File-Name
    S->>F: openRead() → response.addStream (backpressured)
    alt stream completes
        S->>SES: markCompleted, close listener (one-shot)
    else stream error (receiver vanished, sender stop)
        S->>S: stop(), markFailed, close listener (one-shot)
    end
    U->>U: poll sees isRunning=false → completed/failed phase
```

## Receiver

```mermaid
sequenceDiagram
    participant U as ReceiverController
    participant R as TransferReceiver
    participant S as Sender TransferServer
    participant ST as StorageRepository
    participant H as Sha256StreamSink

    U->>R: download(host, port, token)
    R->>S: GET + X-Zanado-Protocol + X-Zanado-Token (connect timeout 10s)
    alt non-200
        S-->>R: {"error": code} → DownloadFailure(rejectedBySender)
    else 200
        S-->>R: streamed body
        R->>H: tee every chunk (no buffering)
        R->>ST: saveStream(_tapped(body), name, expectedSize)
        ST->>ST: write "name.part", size check, atomic rename
        R->>R: verify sha-256(expected) == finalize()
        alt mismatch
            R->>ST: delete stored file → checksumMismatch
        else match
            R->>U: DownloadSuccess
            U->>U: storageListRevisionProvider.bump() (storage screen refreshes)
        end
    end
```

## Failure classification

`DownloadFailureKind` values: `connection` (SocketException/HttpException, including a 30 s idle timeout on a stalled connection), `protocol` (missing/malformed headers), `rejectedBySender` (401/403/404/409/400 + parsed code), `sizeMismatch`, `checksumMismatch`, `storage`.

## Invariants

- One-shot session: any terminal state closes the listener; token/port never reused.
- `.part`-then-rename: an interrupted download never appears completed.
- Sender `completed` is NOT proof of receiver success — receiver checksum verification is authoritative (transport buffering can hide a vanished receiver).
- Expiry is checked at request time only; an accepted stream always completes.
- Single-receiver enforcement via 409 while a response is being streamed.
