import 'package:flutter_test/flutter_test.dart';
import 'package:nur/features/nas/nas_service.dart';
import 'package:nur/features/nas/nas_widgets.dart';

void main() {
  test('normalizeHubUrl adds the scheme and the hub port', () {
    expect(normalizeHubUrl('192.168.1.50'), 'http://192.168.1.50:8770');
    expect(normalizeHubUrl(' raspberrypi.local:9000/ '), 'http://raspberrypi.local:9000');
    expect(normalizeHubUrl('http://raspberrypi.local/api/v1'), 'http://raspberrypi.local:8770');
    expect(normalizeHubUrl(''), '');
  });

  test('formatBytes uses decimal units', () {
    expect(formatBytes(null), '-');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1500), '1.5 KB');
    expect(formatBytes(1204847328), '1.2 GB');
    expect(formatBytes(320e9, digits: 0), '320 GB');
  });

  test('formatUptime', () {
    expect(formatUptime(null), '-');
    expect(formatUptime(59), '0m');
    expect(formatUptime(5 * 3600 + 7 * 60), '5h 7m');
    expect(formatUptime(3 * 86400 + 4 * 3600), '3d 4h');
  });
}
