import 'package:flutter/material.dart';

import 'screens/batch_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';

class BgRemoverRoutes {
  static const String home = '/bg-remover';
  static const String editor = '/bg-remover/editor';
  static const String batch = '/bg-remover/batch';

  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const BgRemoverHomeScreen(),
        editor: (_) => const BgRemoverEditorScreen(),
        batch: (_) => const BgRemoverBatchScreen(),
      };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return _page(const BgRemoverHomeScreen(), settings);
      case editor:
        return _page(const BgRemoverEditorScreen(), settings);
      case batch:
        return _page(const BgRemoverBatchScreen(), settings);
      default:
        return null;
    }
  }

  static MaterialPageRoute<dynamic> _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => child,
    );
  }
}
