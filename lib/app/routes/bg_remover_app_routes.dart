import 'package:flutter/material.dart';

import '../../features/bg_remover/screens/batch_screen.dart';
import '../../features/bg_remover/screens/editor_screen.dart';
import '../../features/bg_remover/screens/home_screen.dart';
import 'bg_remover_route_names.dart';

class BgRemoverAppRoutes {
  const BgRemoverAppRoutes._();

  static Map<String, WidgetBuilder> get routes => {
        BgRemoverRouteNames.home: (_) => const BgRemoverHomeScreen(),
        BgRemoverRouteNames.editor: (_) => const BgRemoverEditorScreen(),
        BgRemoverRouteNames.batch: (_) => const BgRemoverBatchScreen(),
      };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case BgRemoverRouteNames.home:
        return _page(const BgRemoverHomeScreen(), settings);
      case BgRemoverRouteNames.editor:
        return _page(const BgRemoverEditorScreen(), settings);
      case BgRemoverRouteNames.batch:
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
