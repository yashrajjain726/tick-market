import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/tick_app.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: paletteBackground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TickApp());
}
