import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory('build/performance')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: (data) => writeResponseData(
    data == null
        ? null
        : (Map<String, dynamic>.from(data)..remove('screenshots')),
    destinationDirectory: 'build/performance',
    testOutputFilename: 'results',
  ),
);
