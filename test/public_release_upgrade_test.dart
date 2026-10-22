import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  // Run with pubspec versions 89, 97 and 98 to exercise the real updater.
  const installedBuild = int.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: 98,
  );
  const release = UpdateInfo(
    version: '3.5.0',
    build: 98,
    apkUrl:
        'https://github.com/itsArtu/sin-rial-app/releases/download/'
        'v3.5.0%2B98/sin-rial-3.5.0-build98.apk',
  );

  test('Build $installedBuild only offers build 98 when it is newer', () {
    expect(release.isNewer, installedBuild < release.build);
    expect(release.hasDownload, isTrue);
    expect(
      UpdateService.endpoint?.path,
      '/repos/itsArtu/sin-rial-app/releases/latest',
    );
  });

  test('Published tag advances both public 3.2.2 and test build 97', () {
    final latest = parseReleaseVersion('v3.5.0+98');
    expect(latest.version, release.version);
    expect(latest.build, release.build);
    for (final tag in ['v3.2.2+89', 'v3.5.0+97']) {
      final previous = parseReleaseVersion(tag);
      expect(latest.build, greaterThan(previous.build));
      expect(
        compareVersionNames(latest.version, previous.version),
        greaterThanOrEqualTo(0),
      );
    }
  });
}
