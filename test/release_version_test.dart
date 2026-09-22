import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  test('Release 2.2 tag preserves the Android build number', () {
    final version = parseReleaseVersion('v2.2.0+64');
    expect(version.version, '2.2.0');
    expect(version.build, 64);
    expect(compareVersionNames(version.version, '2.1.13'), greaterThan(0));
  });

  test('Installed 3.0 does not offer itself or an older release', () {
    const current = UpdateInfo(version: '3.0', build: 69, apkUrl: 'app.apk');
    const previous = UpdateInfo(version: '2.2.3', build: 67, apkUrl: 'old.apk');
    const next = UpdateInfo(version: '3.0.1', build: 70, apkUrl: 'next.apk');
    expect(current.isNewer, isFalse);
    expect(previous.isNewer, isFalse);
    expect(next.isNewer, isTrue);
  });
}
