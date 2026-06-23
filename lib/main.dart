import 'package:bg_remover_app/app/routes/bg_remover_app_routes.dart';
import 'package:bg_remover_app/app/routes/bg_remover_route_names.dart' show BgRemoverRouteNames;
import 'package:bg_remover_app/app/theme/bg_remover_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



void main() {
  runApp(const ProviderScope(child: ExampleApp()));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BgRemoverTheme.darkTheme,
      initialRoute: BgRemoverRouteNames.home,
      routes: BgRemoverAppRoutes.routes,
      onGenerateRoute: BgRemoverAppRoutes.onGenerateRoute,
    );
  }
}
