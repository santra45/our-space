import 'package:flutter/foundation.dart';

class RouteRequests extends ChangeNotifier {
  String? _pending;
  int _serial = 0;

  String? get pending => _pending;

  int get serial => _serial;

  void open(String route) {
    final clean = route.trim();
    if (clean.isEmpty) return;
    _pending = clean;
    _serial++;
    notifyListeners();
  }

  String? takeWhere(bool Function(String route) test) {
    final route = _pending;
    if (route == null || !test(route)) return null;
    _pending = null;
    return route;
  }

  String? takePrefixed(String prefix) {
    final route = takeWhere((route) => route.startsWith(prefix));
    return route?.substring(prefix.length);
  }
}
