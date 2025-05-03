import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_page.dart'; // Ensure this path is correct
import 'screens/login_screen.dart';
import 'controllers/auth_controller.dart';
import 'services/chat_service.dart';
import 'services/config_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services (ConfigService loads env in constructor now)
  final configService = ConfigService();
  final settingsService = SettingsService();
  // await settingsService.init(); // Removed - SettingsService doesn't have init()

  // AuthController depends on ConfigService and SettingsService
  final authController = AuthController(configService, settingsService);
  // ChatService depends on ConfigService and SettingsService
  final chatService = ChatService(configService, settingsService);

  runApp(
    MultiProvider(
      providers: [
        // Use ChangeNotifierProvider for services/controllers that notify listeners
        ChangeNotifierProvider<ConfigService>.value(value: configService),
        ChangeNotifierProvider<AuthController>.value(value: authController),
        // Use simple Provider for services that don't notify or are singletons
        Provider<SettingsService>.value(value: settingsService),
        Provider<ChatService>.value(value: chatService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Access ConfigService via Provider - listen might be needed if title changes dynamically
    final configService = Provider.of<ConfigService>(context);

    return MaterialApp(
      title: configService.appName, // Use configured name or default
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
         brightness: Brightness.dark,
         colorScheme: ColorScheme.fromSeed(
             seedColor: Colors.deepPurple, brightness: Brightness.dark),
         useMaterial3: true,
       ),
       themeMode: ThemeMode.system, // Or ThemeMode.light, ThemeMode.dark
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Ensure the widget is still mounted before proceeding
    if (!mounted) return;

    // Use AuthController to check login status
    final authController = Provider.of<AuthController>(context, listen: false);
    // checkLoginStatus internally calls _restoreSavedToken which updates isLoggedIn
    bool loggedIn = await authController.checkLoginStatus();

    // JWT validation is implicitly handled by backend calls.
    // If token is expired/invalid, API calls will fail, leading back to login.
    // We don't need an explicit client-side expiration check here.

    // Ensure the widget is still mounted before navigating
    if (!mounted) return;

    if (loggedIn) {
      print("[AuthCheckScreen] User is logged in. Navigating to MyHomePage.");
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MyHomePage()), // Correct class name
      );
    } else {
      print("[AuthCheckScreen] User is not logged in. Navigating to LoginScreen.");
      // No need to explicitly call logout here, checkLoginStatus handles state.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator while checking auth state
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
