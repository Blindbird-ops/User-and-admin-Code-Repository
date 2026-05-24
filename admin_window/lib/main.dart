import 'package:admin_window/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart'; // 1. IMPORT THIS
import 'login_screen.dart';
import 'services/python_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Window Manager
  await windowManager.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await Hive.initFlutter();
  await PythonBackendService.start();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

// 3. Change Mixin to WindowListener
class _MyAppState extends State<MyApp> with WindowListener {
  
  @override
  void initState() {
    super.initState();
    // 4. Add the listener
    windowManager.addListener(this);
    
    // 5. Prevent the default close action. 
    // This allows us to run code (kill python) BEFORE the app actually closes.
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    // 6. Remove listener
    windowManager.removeListener(this);
    super.dispose();
  }

  // 7. This triggers when you click the "X" button
  @override
  void onWindowClose() async {
    print("❌ WINDOW CLOSING DETECTED");
    
    // A. Kill the Python Backend immediately
    PythonBackendService.forceKill();
    
    // B. Now actually destroy the Flutter window
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Barangay Services(BaSe) Admin Panel',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const LoginScreen(),
    );
  }
}