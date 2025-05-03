import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import '../services/auth_service.dart';
import 'home_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (email.isEmpty || otp.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both email and 6-digit code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${const String.fromEnvironment('AGIXT_SERVER', defaultValue: 'https://api.agixt.dev')}/v1/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'token': otp,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['url'] != null) {
          final String loginUrl = responseData['url'];
          final String jwt = loginUrl.split('?token=')[1];
          
          // Store the JWT
          await AuthService.storeJWT(jwt);
          
          // Navigate to the home page
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const MyHomePage()),
            );
          }
        } else {
          setState(() {
            _errorMessage = 'Invalid response format from server';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Login failed: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loginWithOAuth(String providerName, String authorizationUrl, String clientId, String redirectUri) async {
    try {
      final result = await FlutterWebAuth.authenticate(
        url: authorizationUrl,
        callbackUrlScheme: redirectUri.split('://')[0],
      );

      final token = Uri.parse(result).queryParameters['code'];
      if (token != null) {
        // Handle the token (e.g., send it to your backend for validation)
        await AuthService.storeJWT(token);

        // Navigate to the home page
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MyHomePage()),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'OAuth login failed: No token received';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'OAuth login error: $e';
      });
    }
  }

  void _navigateToRegistration() async {
    final appUri = const String.fromEnvironment('APP_URI', defaultValue: 'https://agixt.dev');
    final url = Uri.parse(appUri);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $appUri')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appName = const String.fromEnvironment('APP_NAME', defaultValue: 'AGiXT');
    
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
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              decoration: const InputDecoration(
                labelText: '6-digit Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pin),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 8),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _login,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _navigateToRegistration,
              child: const Text('Need an account? Register here'),
            ),
            const SizedBox(height: 16),
            Text(
              'Or login with:',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loginWithOAuth(
                'Google',
                'https://accounts.google.com/o/oauth2/auth',
                'your-google-client-id',
                'your-app-scheme://callback',
              ),
              icon: const Icon(Icons.login),
              label: const Text('Login with Google'),
            ),
            ElevatedButton.icon(
              onPressed: () => _loginWithOAuth(
                'GitHub',
                'https://github.com/login/oauth/authorize',
                'your-github-client-id',
                'your-app-scheme://callback',
              ),
              icon: const Icon(Icons.login),
              label: const Text('Login with GitHub'),
            ),
          ],
        ),
      ),
    );
  }
}