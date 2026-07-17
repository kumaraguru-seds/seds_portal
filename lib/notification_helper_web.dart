// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

void requestWebNotificationPermission() {
  try {
    js.context.callMethod('eval', ["""
      if (Notification.permission === 'default') {
        Notification.requestPermission();
      }
    """]);
  } catch (_) {}
}

void showWebNotification(String title, String body) {
  try {
    js.context.callMethod('eval', ["""
      if (Notification.permission === 'granted') {
        new Notification("${title.replaceAll('"', '\\"')}", {
          body: "${body.replaceAll('"', '\\"')}",
          icon: "app_logo.png"
        });
      }
    """]);
  } catch (_) {}
}
