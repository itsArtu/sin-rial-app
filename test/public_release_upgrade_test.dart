import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  // Run this test with each prior pubspec version, then 3.6.2+113.
  // Flutter reserves FLUTTER_BUILD_NAME/NUMBER: change the staging pubspec
  // for the matrix rather than passing those names through --dart-define.
  const installedBuild = int.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: 113,
  );
  const release = UpdateInfo(
    version: '3.6.2',
    build: 113,
    apkUrl:
        'https://github.com/itsArtu/sin-rial-app/releases/download/'
        'v3.6.2%2B113/sin-rial-3.6.2-build113.apk',
  );

  test('Build $installedBuild only offers build 113 when it is newer', () {
    expect(release.isNewer, installedBuild < release.build);
    expect(release.hasDownload, isTrue);
    expect(
      UpdateService.endpoint?.path,
      '/repos/itsArtu/sin-rial-app/releases/latest',
    );
  });

  test('Candidate tag advances public and local builds through 112', () {
    final latest = parseReleaseVersion('v3.6.2+113');
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
      'v3.6.1+106',
      'v3.6.1+110',
      'v3.6.1+111',
      'v3.6.1+112',
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
