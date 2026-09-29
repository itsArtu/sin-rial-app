import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  test('Release 2.2 tag preserves the Android build number', () {
    final version = parseReleaseVersion('v2.2.0+64');
    expect(version.version, '2.2.0');
    expect(version.build, 64);
    expect(compareVersionNames(version.version, '2.1.13'), greaterThan(0));
  });

  test('Installed 3.1 does not offer itself or an older release', () {
    const current = UpdateInfo(version: '3.1', build: 74, apkUrl: 'app.apk');
    const previous = UpdateInfo(version: '2.2.3', build: 67, apkUrl: 'old.apk');
    const tested = UpdateInfo(version: '3.0', build: 73, apkUrl: 'tested.apk');
    const next = UpdateInfo(version: '3.1.1', build: 75, apkUrl: 'next.apk');
    expect(current.isNewer, isFalse);
    expect(previous.isNewer, isFalse);
    expect(tested.isNewer, isFalse);
    expect(next.isNewer, isTrue);
  });

  test('Stable 3.1 tag is newer than published 2.x and 3.0 versions', () {
    final latest = parseReleaseVersion('v3.1+74');
    expect(latest.version, '3.1');
    expect(latest.build, 74);
    for (final tag in ['v2.1.13+63', 'v2.2.2+66', 'v3.0+71', 'v3.0+73']) {
      final previous = parseReleaseVersion(tag);
      expect(latest.build, greaterThan(previous.build));
      expect(
        compareVersionNames(latest.version, previous.version),
        greaterThan(0),
      );
    }
    expect(
      UpdateService.endpoint?.path,
      '/repos/itsArtu/sin-rial-app/releases/latest',
    );
  });
}
