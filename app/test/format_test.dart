import 'package:cholo/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats paisa as taka', () {
    expect(formatMoney(12300), '৳123');
    expect(formatMoney(12350), '৳123.50');
    expect(formatMoney(12345600), '৳1,23,456');
  });

  test('formats distance and duration', () {
    expect(formatDistance(850), '850 m');
    expect(formatDistance(7800), '7.8 km');
    expect(formatDuration(20), '1 min');
    expect(formatDuration(1560), '26 min');
    expect(formatDuration(4500), '1 h 15 min');
  });

  test('normalizes Bangladeshi phone numbers like the API', () {
    expect(normalizePhone('01711-000001'), '+8801711000001');
    expect(normalizePhone('8801711000001'), '+8801711000001');
    expect(normalizePhone('+447700900123'), '+447700900123');
    expect(normalizePhone('0123456789'), isNull);
  });
}
