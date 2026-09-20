import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/services/update_service.dart';

void main() {
  test('isNewer compares semantic versions', () {
    expect(UpdateService.isNewer('0.6.0', '0.5.1'), isTrue);
    expect(UpdateService.isNewer('0.5.2', '0.5.1'), isTrue);
    expect(UpdateService.isNewer('1.0', '0.9.9'), isTrue);
    expect(UpdateService.isNewer('0.5.1', '0.5.1'), isFalse);
    expect(UpdateService.isNewer('0.5.0', '0.5.1'), isFalse);
    expect(UpdateService.isNewer('0.5.1+600', '0.5.1'), isFalse);
  });

  test('pickDownloadUrl chooses the platform asset', () {
    final assets = [
      {
        'name': 'app-arm64-v8a-release.apk',
        'browser_download_url': 'https://example/arm64.apk',
      },
      {
        'name': 'app-armeabi-v7a-release.apk',
        'browser_download_url': 'https://example/v7a.apk',
      },
      {
        'name': 'photoatlas-linux-x86_64.tar.gz',
        'browser_download_url': 'https://example/linux.tar.gz',
      },
      {
        'name': 'app-release.aab',
        'browser_download_url': 'https://example/app.aab',
      },
    ];
    expect(
      UpdateService.pickDownloadUrl('android', assets),
      'https://example/arm64.apk',
    );
    expect(
      UpdateService.pickDownloadUrl('linux', assets),
      'https://example/linux.tar.gz',
    );
    expect(
      UpdateService.pickDownloadUrl('web', assets),
      contains('/releases/latest'),
    );
  });

  test('pickDownloadUrl falls back to any apk then the release page', () {
    final onlyV7a = [
      {
        'name': 'app-armeabi-v7a-release.apk',
        'browser_download_url': 'https://example/v7a.apk',
      },
    ];
    expect(
      UpdateService.pickDownloadUrl('android', onlyV7a),
      'https://example/v7a.apk',
    );
    expect(
      UpdateService.pickDownloadUrl('android', const []),
      contains('/releases/latest'),
    );
  });
}
