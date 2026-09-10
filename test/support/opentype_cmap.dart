import 'dart:typed_data';

/// Reads non-.notdef Unicode mappings from the pinned OpenType test fonts.
/// No platform font fallback or installed Python package is involved.
Set<int> openTypeUnicodeCodePoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int? cmap;
  for (var i = 0; i < data.getUint16(4); i++) {
    final record = 12 + i * 16;
    if (data.getUint32(record) == 0x636d6170) {
      cmap = data.getUint32(record + 8);
      break;
    }
  }
  if (cmap == null) throw const FormatException('Font has no cmap table');
  final result = <int>{};
  final visited = <int>{};
  for (var i = 0; i < data.getUint16(cmap + 2); i++) {
    final record = cmap + 4 + i * 8;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    if (platform != 0 && !(platform == 3 && [1, 10].contains(encoding))) {
      continue;
    }
    final table = cmap + data.getUint32(record + 4);
    if (!visited.add(table)) continue;
    final format = data.getUint16(table);
    if (format == 4) {
      final segments = data.getUint16(table + 6) ~/ 2;
      for (var segment = 0; segment < segments; segment++) {
        final end = data.getUint16(table + 14 + 2 * segment);
        final start = data.getUint16(table + 16 + 2 * segments + 2 * segment);
        final delta = data.getInt16(table + 16 + 4 * segments + 2 * segment);
        final rangeAddress = table + 16 + 6 * segments + 2 * segment;
        final range = data.getUint16(rangeAddress);
        for (var cp = start; cp <= end && cp != 0xffff; cp++) {
          var glyph = range == 0
              ? (cp + delta) & 0xffff
              : data.getUint16(rangeAddress + range + 2 * (cp - start));
          if (range != 0 && glyph != 0) glyph = (glyph + delta) & 0xffff;
          if (glyph != 0) result.add(cp);
        }
      }
    } else if (format == 12) {
      final groups = data.getUint32(table + 12);
      for (var group = 0; group < groups; group++) {
        final record = table + 16 + group * 12;
        final start = data.getUint32(record);
        final end = data.getUint32(record + 4);
        final firstGlyph = data.getUint32(record + 8);
        if (end > 0x10ffff || start > end) {
          throw const FormatException('Invalid Unicode cmap range');
        }
        for (var cp = start; cp <= end; cp++) {
          if (firstGlyph + cp - start != 0) result.add(cp);
        }
      }
    } else {
      throw FormatException('Unsupported Unicode cmap format $format');
    }
  }
  if (result.isEmpty) throw const FormatException('Font has no Unicode glyphs');
  return result;
}
