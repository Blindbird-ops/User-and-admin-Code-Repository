import 'dart:io'; // Needed for internet check
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 1. Run the app IMMEDIATELY. Do not await Firebase here.
  runApp(const DependencyLoader());
}

// 2. Create a widget to handle initialization
class DependencyLoader extends StatefulWidget {
  const DependencyLoader({super.key});

  @override
  State<DependencyLoader> createState() => _DependencyLoaderState();
}

class _DependencyLoaderState extends State<DependencyLoader> {
  // State variables
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // A. Check for Internet Connection first
      // This looks up google.com to verify actual data connectivity
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        
        // B. Internet is good, Initialize Firebase
        await Firebase.initializeApp();
        
        // C. Register Background Handler
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        
        // D. Initialize Notification Service
        await NotificationService.initialize();

        // Success!
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      }
    } on SocketException catch (_) {
      // Handle No Internet specific error
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = "No Internet Connection.\nPlease check your settings.";
        });
      }
    } catch (e) {
      // Handle other errors
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = "Error initializing app: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 3. SHOW DIFFERENT SCREENS BASED ON STATUS

    // If there is an error (No Internet), show this screen
    if (_hasError) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 80, color: Colors.grey),
                const SizedBox(height: 20),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Reset state and try again
                    setState(() {
                      _hasError = false;
                      _errorMessage = '';
                    });
                    _initializeApp();
                  },
                  child: const Text("Retry"),
                )
              ],
            ),
          ),
        ),
      );
    }

    // If initialized successfully, show the main app
    if (_isInitialized) {
      return const MyApp();
    }

    // Otherwise, show a Loading Splash Screen
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Flutter Role-Based App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
      },
    );
  }
}