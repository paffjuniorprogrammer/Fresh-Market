import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:potato_app/utils/js_helper_stub.dart'
    if (dart.library.js) 'package:potato_app/utils/js_helper_web.dart';

class PwaService {
  static final PwaService instance = PwaService._();
  PwaService._();

  final _installableController = StreamController<bool>.broadcast();
  Stream<bool> get installableStream => _installableController.stream;
  
  bool _isInstallable = false;
  bool get isInstallable => _isInstallable;

  void init() {
    if (!kIsWeb) return;

    JsHelper.setOnAppInstallable(() {
      _isInstallable = true;
      _installableController.add(true);
    });
  }

  Future<bool> triggerInstall() async {
    if (!kIsWeb) return false;
    
    try {
      final result = await JsHelper.triggerAppInstall();
      if (result == true) {
        _isInstallable = false;
        _installableController.add(false);
        return true;
      }
    } catch (e) {
      debugPrint('PWA Install Error: $e');
    }
    return false;
  }
}
