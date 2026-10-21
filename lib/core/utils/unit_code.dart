/// Hasil parse string QR yang di-scan saat loading.
///
/// QR yang dicetak modul Receiving berisi `item_code` polos (kalau
/// quantity 1) atau `item_code-U{n}` (kalau lebih dari 1, per label
/// per box). Kalau tidak ada suffix -U{n}, dianggap unit ke-1.
class ParsedUnitCode {
  final String itemCode;
  final int unitIndex;

  ParsedUnitCode({
    required this.itemCode,
    this.unitIndex = 1,
  });
}

class UnitCodeParser {
  static final _unitSuffixPattern = RegExp(r'^(.*)-U(\d+)$');

  static ParsedUnitCode parse(String rawScannedValue) {
    final value = rawScannedValue.trim();
    final match = _unitSuffixPattern.firstMatch(value);

    if (match != null) {
      final itemCode = match.group(1)!;
      final unitIndex = int.tryParse(match.group(2)!) ?? 1;

      return ParsedUnitCode(itemCode: itemCode, unitIndex: unitIndex);
    }

    return ParsedUnitCode(itemCode: value);
  }
}