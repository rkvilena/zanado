/// Pure filename utilities (no I/O).
class FileNameUtils {
  FileNameUtils._();

  /// Sanitizes a user/peer-supplied filename:
  /// - strips any directory components (prevents path traversal),
  /// - removes control characters and characters invalid on Windows,
  /// - collapses whitespace, trims dots/spaces at the ends,
  /// - enforces a non-empty basename and a length limit.
  ///
  /// Returns the sanitized name (with extension preserved when present), or
  /// `null` if nothing usable remains.
  static String? sanitize(String? raw, {int maxLength = 200}) {
    if (raw == null) return null;
    var name = raw.replaceAll('\\', '/');
    final slash = name.lastIndexOf('/');
    if (slash != -1) name = name.substring(slash + 1);

    // Remove control chars and characters illegal on Windows volumes.
    name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Trailing dots/spaces are illegal on Windows.
    name = name.replaceAll(RegExp(r'[. ]+$'), '');

    if (name.isEmpty || name == '.' || name == '..') return null;

    if (name.length > maxLength) {
      final dot = name.lastIndexOf('.');
      final ext = (dot > name.length - 12 && dot != -1) ? name.substring(dot) : '';
      final base = name.substring(0, maxLength - ext.length).trim();
      name = base.isEmpty ? name.substring(0, maxLength) : base + ext;
    }
    return name.isEmpty ? null : name;
  }

  /// Splits `photo.jpg` into `('photo', '.jpg')` (extension includes the dot;
  /// empty string when the name has no usable extension).
  static (String, String) splitExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return (name, '');
    return (name.substring(0, dot), name.substring(dot));
  }

  /// Returns `photo (1).jpg` for `('photo', '.jpg')` and copy index 1.
  static String withCopySuffix(String base, String ext, int index) =>
      '$base ($index)$ext';
}