import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  // Run with prior pubspec versions and 106 to test the candidate updater.
  const installedBuild = int.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: 106,
  );
  const release = UpdateInfo(
    version: '3.6.1',
    build: 106,
    apkUrl:
        'https://github.com/itsArtu/sin-rial-app/releases/download/'
        'v3.6.1%2B106/sin-rial-3.6.1-build106.apk',
  );

  test('Build $installedBuild only offers build 106 when it is newer', () {
    expect(release.isNewer, installedBuild < release.build);
    expect(release.hasDownload, isTrue);
    expect(
      UpdateService.endpoint?.path,
      '/repos/itsArtu/sin-rial-app/releases/latest',
    );
  });

  test('Candidate tag advances public and local builds through 105', () {
    final latest = parseReleaseVersion('v3.6.1+106');
    expect(latest.version, release.version);
    expect(latest.build, release.build);
    for (final tag in [
      'v3.2.2+89',
      'v3.5.0+97',
      'v3.5.0+98',
      'v3.5.1+99',
      'v3.5.1+100',
      'v3.5.2+101',
      'v3.6.0+102',
      'v3.6.0+103',
      'v3.6.0+104',
      'v3.6.0+105',
    ]) {
      final previous = parseReleaseVersion(tag);
      expect(latest.build, greaterThan(previous.build));
      expect(
        compareVersionNames(latest.version, previous.version),
        greaterThanOrEqualTo(0),
      );
    }
  });
}
