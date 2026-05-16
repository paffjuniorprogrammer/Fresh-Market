abstract class JsHelper {
  static void setOnAppInstallable(void Function() callback) {}
  static Future<bool> triggerAppInstall() async => false;
  static void setOnAppUpdateAvailable(void Function() callback) {}
  static void reloadApp() {}
}
