library;

/// Re-export of storage error types so UI/features depend on `core/errors`
/// rather than reaching into domain internals.
export '../../domain/repositories/storage_repository.dart'
    show StorageException, InvalidFileNameException;