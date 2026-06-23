import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routes/bg_remover_app_routes.dart';
import 'routes/bg_remover_route_names.dart';
import 'theme/bg_remover_theme.dart';

class BgRemoverApp extends StatelessWidget {
  const BgRemoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BgRemoverTheme.darkTheme,
        initialRoute: BgRemoverRouteNames.home,
        routes: BgRemoverAppRoutes.routes,
        onGenerateRoute: BgRemoverAppRoutes.onGenerateRoute,
      ),
    );
  }
}
