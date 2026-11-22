import 'package:app_links/app_links.dart';

// Thin wrapper around `app_links` so incoming invite URLs are easy to test.
class DeepLinkService {
  const DeepLinkService();

  Future<Uri?> getInitialUri() async {
    try {
      return await AppLinks().getInitialLink();
    } catch (_) {
      return null;
    }
  }

  Stream<Uri> uriStream() {
    try {
      return AppLinks().uriLinkStream;
    } catch (_) {
      return const Stream<Uri>.empty();
    }
  }
}
