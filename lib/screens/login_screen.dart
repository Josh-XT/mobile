import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import FontAwesome
import '../controllers/auth_controller.dart'; // Use AuthController
import '../services/config_service.dart';
import 'home_page.dart'; // Assuming MyHomePage exists

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch providers after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use listen: false as we only need to trigger this once
      final authController = Provider.of<AuthController>(context, listen: false);
      // Fetch providers only if server is configured
      if (Provider.of<ConfigService>(context, listen: false).isConfigured) {
         print("[LoginScreen] Fetching OAuth providers on init...");
         authController.fetchOAuthProviders();
      } else {
         print("[LoginScreen] Server not configured, skipping OAuth provider fetch.");
         // Optionally show a message or direct to config
      }
    });
  }

  // Helper to get FontAwesomeIcon based on provider name (from source project)
  IconData _getIconForProvider(String providerName) {
    switch (providerName.toLowerCase()) {
      case 'google':
        return FontAwesomeIcons.google;
      case 'github':
        return FontAwesomeIcons.github;
      case 'microsoft':
        return FontAwesomeIcons.microsoft;
      case 'discord':
        return FontAwesomeIcons.discord;
      case 'x': // Twitter is now X
        return FontAwesomeIcons.xTwitter;
      // Add more cases as needed
      default:
        return FontAwesomeIcons.plug; // Default icon
    }
  }

  Future<void> _signInWithProvider(BuildContext context, AuthController authController, Map<String, dynamic> provider) async {
    final success = await authController.signInWithOAuth(provider);
    if (success && mounted) {
      // Check isLoggedIn state from the controller after successful sign-in
      if (authController.isLoggedIn) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MyHomePage()),
        );
      } else {
         // This case might happen if linking was successful but didn't result in login state change
         // Error message should be shown via the Consumer below
         print("[LoginScreen] OAuth flow succeeded but user is not logged in (possibly account linking).");
      }
    }
    // Error messages are handled by the Consumer listening to authController.error
  }

  Future<void> _register() async {
    // Keep existing register logic using ConfigService
    if (!mounted) return;
    final configService = Provider.of<ConfigService>(context, listen: false);
    final appUriString = configService.appUri;

    if (appUriString.isEmpty) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Registration URL not configured.')),
         );
       }
       return;
    }

    final url = Uri.parse(appUriString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $appUriString')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer to react to AuthController changes
    return Consumer<AuthController>(
      builder: (context, authController, child) {
        // Access ConfigService for appName (listen: false is fine here)
        final configService = Provider.of<ConfigService>(context, listen: false);
        final appName = configService.appName;

        return Scaffold(
          appBar: AppBar(
            title: Text('$appName Login'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Welcome to $appName',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Server Info (Optional, similar to source project)
                 Padding(
                   padding: const EdgeInsets.only(bottom: 20.0),
                   child: Consumer<ConfigService>( // Listen to config changes
                     builder: (context, config, _) => Text(
                       'Server: ${config.agixtServer.isNotEmpty ? config.agixtServer : "Not Set"} ${config.isConfigured ? '(Connected)' : '(Not Connected)'}',
                       style: TextStyle(
                         color: config.isConfigured ? Colors.green : Colors.red,
                         fontSize: 14,
                       ),
                       textAlign: TextAlign.center,
                     ),
                   ),
                 ),


                // Error Message Display from AuthController
                if (authController.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      authController.error,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 8),

                // OAuth Provider Buttons Section
                _buildOAuthButtons(context, authController),

                const SizedBox(height: 24), // Space before register button
                TextButton(
                  // Disable button if any loading is happening
                  onPressed: authController.isLoading || authController.isProvidersLoading ? null : _register,
                  child: const Text('Need an account? Register here'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper widget updated to use AuthController state
  Widget _buildOAuthButtons(BuildContext context, AuthController authController) {
    if (authController.isProvidersLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Check if server is configured before showing "Could not load" message
    final isServerConfigured = Provider.of<ConfigService>(context, listen: false).isConfigured;

    if (authController.oauthProviders.isEmpty && !authController.isProvidersLoading) {
      return Column(
        children: [
          Text(
            isServerConfigured
                ? 'Could not load login methods. Check server logs.'
                : 'Server not configured. Please check settings.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (isServerConfigured) // Only show refresh if server is configured
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry loading providers',
              // Disable button if any loading is happening
              onPressed: authController.isLoading ? null : () => authController.fetchOAuthProviders(),
            ),
        ],
      );
    }

    // Build buttons using Wrap for better layout (from source project)
    return Column(
       children: [
         const Divider(height: 30, thickness: 1),
         Text("Or continue with:", style: Theme.of(context).textTheme.bodyMedium),
         const SizedBox(height: 15),
         Wrap(
           spacing: 15.0, // Horizontal space
           runSpacing: 10.0, // Vertical space
           alignment: WrapAlignment.center,
           children: authController.oauthProviders.map((provider) {
             final providerName = provider['name'] as String? ?? 'Unknown';
             final buttonText = providerName.toLowerCase() == 'x'
                 ? 'Continue with X' // Shorter text
                 : 'Continue with ${providerName[0].toUpperCase()}${providerName.substring(1)}';

             return ElevatedButton.icon(
               icon: FaIcon(_getIconForProvider(providerName), size: 18),
               label: Text(buttonText),
               // Disable button if any loading is happening
               onPressed: authController.isLoading ? null : () => _signInWithProvider(context, authController, provider),
               style: ElevatedButton.styleFrom(
                 foregroundColor: Colors.white, backgroundColor: Colors.blueGrey[700], // Style from source
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(8),
                 ),
                 padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
               ),
             );
           }).toList(),
         ),
          const Divider(height: 30, thickness: 1),
       ],
    );
  }
}