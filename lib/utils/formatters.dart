String formatKg(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String kgLabel(double value) => '${formatKg(value)} kg';
String qtyLabel(double value, String unit) {
  if (unit.toLowerCase() == 'pc') {
    return '${formatKg(value)} ${value == 1 ? 'piece' : 'pieces'}';
  }
  return '${formatKg(value)} ${unit.toLowerCase()}';
}
String moneyLabel(num value) => '${value.toStringAsFixed(0)} Frw';
String orderDateLabel(DateTime? value) {
  if (value == null) {
    return 'Saved recently';
  }
  final date = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}

const _phonePattern = r'^\+?[0-9]{10,15}$';

bool isValidPhone(String value) =>
    RegExp(_phonePattern).hasMatch(value.replaceAll(RegExp(r'[^0-9+]'), ''));

String normalizedFileExtension(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  if (lastDot == -1 || lastDot == fileName.length - 1) {
    return '.png';
  }
  return fileName.substring(lastDot).toLowerCase();
}

String contentTypeForExtension(String extension) {
  switch (extension) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.png':
    default:
      return 'image/png';
  }
}
