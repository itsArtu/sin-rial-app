import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  // Run with pubspec versions 89, 97, 98, 99 and 100 to test the real updater.
  const installedBuild = int.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: 100,
  );
  const release = UpdateInfo(
    version: '3.5.1',
    build: 100,
    apkUrl:
        'https://github.com/itsArtu/sin-rial-app/releases/download/'
        'v3.5.1%2B100/sin-rial-3.5.1-build100.apk',
  );

  test('Build $installedBuild only offers build 100 when it is newer', () {
    expect(release.isNewer, installedBuild < release.build);
    expect(release.hasDownload, isTrue);
    expect(
      UpdateService.endpoint?.path,
      '/repos/itsArtu/sin-rial-app/releases/latest',
    );
  });

  test('Published tag advances public and local builds through 99', () {
    final latest = parseReleaseVersion('v3.5.1+100');
    expect(latest.version, release.version);
    expect(latest.build, release.build);
    for (final tag in ['v3.2.2+89', 'v3.5.0+97', 'v3.5.0+98', 'v3.5.1+99']) {
      final previous = parseReleaseVersion(tag);
      expect(latest.build, greaterThan(previous.build));
      expect(
        compareVersionNames(latest.version, previous.version),
        greaterThanOrEqualTo(0),
      );
    }
  });
}
