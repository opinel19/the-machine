import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/theme.dart';
import 'src/ui/machine_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MachineApp());
}

class MachineApp extends StatelessWidget {
  const MachineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Machine',
      debugShowCheckedModeBanner: false,
      theme: machineTheme(),
      home: const MachineScreen(),
    );
  }
}
