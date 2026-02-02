import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/app_controller.dart';
import 'services/file_host_config_store_flutter.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const HostConsoleApp());
}

class HostConsoleApp extends StatelessWidget {
  const HostConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FileHostConfigStoreFlutter>(
          create: (_) => FileHostConfigStoreFlutter(),
        ),
        ChangeNotifierProxyProvider<FileHostConfigStoreFlutter, AppController>(
          create: (ctx) => AppController(store: ctx.read<FileHostConfigStoreFlutter>()),
          update: (ctx, store, previous) => previous ?? AppController(store: store),
        ),
      ],
      child: MaterialApp(
        title: 'iTermRemote Host',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5D3A)),
        ),
        home: const HomePage(),
      ),
    );
  }
}

