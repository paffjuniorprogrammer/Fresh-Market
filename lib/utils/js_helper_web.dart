// ignore_for_file: avoid_web_libraries_in_flutter
// ignore: deprecated_member_use
import 'dart:js' as js;

abstract class JsHelper {
  static void setOnAppInstallable(void Function() callback) {
    js.context['onAppInstallable'] = callback;
  }

  static Future<bool> triggerAppInstall() async {
    final result = await js.context.callMethod('triggerAppInstall');
    return result == true;
  }
}
