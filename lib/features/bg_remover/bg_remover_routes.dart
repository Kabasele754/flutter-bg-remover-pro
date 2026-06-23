import 'package:flutter/material.dart';

import '../../app/routes/bg_remover_app_routes.dart';
import '../../app/routes/bg_remover_route_names.dart';

/// Backward-compatible route facade for the feature layer.
/// New projects should prefer BgRemoverAppRoutes and BgRemoverRouteNames from lib/app/routes.
class BgRemoverRoutes {
  const BgRemoverRoutes._();

  static const String home = BgRemoverRouteNames.home;
  static const String editor = BgRemoverRouteNames.editor;
  static const String batch = BgRemoverRouteNames.batch;

  static Map<String, WidgetBuilder> get routes => BgRemoverAppRoutes.routes;

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return BgRemoverAppRoutes.onGenerateRoute(settings);
  }
}
