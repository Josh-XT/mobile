import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'home_page.dart';

// Provider data model
class OAuthProvider {
  final String name;
  final String scopes;
  final String authorize;
  final String clientId;
  final bool pkceRequired;

  OAuthProvider({
    required this.name,
    required this.scopes, 
    required this.authorize,
    required this.clientId,
    required this.pkceRequired,
  });

  factory OAuthProvider.fromJson(Map<String, dynamic> json) {
    return OAuthProvider(
      name: json['name'],
      scopes: json['scopes'],
      authorize: json['authorize'],
      clientId: json['client_id'],
      pkceRequired: json['pkce_required'],
    );
  }
}

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
  bool _loadingProviders = true;
  List<OAuthProvider> _oauthProviders = [];

  @override
  void initState() {
    super.initState();
    _loadOAuthProviders();
  }

  Future<void> _loadOAuthProviders() async {
    setState(() {
      _loadingProviders = true;
    });
    
    try {
      final server = const String.fromEnvironment('AGIXT_SERVER', defaultValue: 'https://api.agixt.dev');
      final response = await http.get(Uri.parse('$server/v1/oauth'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> providersJson = data['providers'] ?? [];
        
        setState(() {
          _oauthProviders = providersJson
              .map((provider) => OAuthProvider.fromJson(provider))
              .where((provider) => provider.clientId.isNotEmpty)
              .toList();
          _oauthProviders.sort((a, b) => a.name.compareTo(b.name));
          _loadingProviders = false;
        });
      } else {
        setState(() {
          _loadingProviders = false;
          _errorMessage = 'Failed to load OAuth providers: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loadingProviders = false;
        _errorMessage = 'Error loading OAuth providers: $e';
      });
    }
  }

  // Get icon based on provider name
  IconData _getIconForProvider(String providerName) {
    final name = providerName.toLowerCase();
    
    switch (name) {
      case 'google':
        return Icons.android;
      case 'github':
        return Icons.code;
      case 'microsoft':
        return Icons.window;
      case 'x':
      case 'twitter':
        return Icons.flutter_dash;  // Using flutter_dash as a placeholder for X/Twitter
      case 'discord':
        return Icons.discord;
      case 'amazon':
        return Icons.shopping_cart;
      default:
        return Icons.login;
    }
  }

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
      final appUri = const String.fromEnvironment('APP_URI', defaultValue: 'https://agixt.dev');
      final actualRedirectUri = '$appUri/user/close/${providerName.toLowerCase()}';
      
      // Build the complete OAuth URL with all necessary parameters
      final authUrl = Uri.parse(authorizationUrl).replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': actualRedirectUri,
        'response_type': 'code',
        'scope': 'openid profile email',
      });
      
      // Launch the URL in the external browser
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        
        setState(() {
          _errorMessage = null;
          _isLoading = true;
        });
        
        // Show a dialog that explains to check the browser and return to the app
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Completing Login'),
              content: const Text(
                'Please complete the authentication in your browser.\n\n'
                'After logging in, return to this app.'
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _isLoading = false;
                    });
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    // Prompt user to enter JWT manually
                    _showJwtInputDialog();
                  },
                  child: const Text('I\'ve Logged In'),
                ),
              ],
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Could not open the authentication page';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'OAuth login error: $e';
        _isLoading = false;
      });
    }
  }

  // Dialog to enter JWT manually after OAuth flow completes in browser
  Future<void> _showJwtInputDialog() async {
    final TextEditingController jwtController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Authentication Token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'After successful login, copy the token from the browser and paste it here.'
            ),
            const SizedBox(height: 16),
            TextField(
              controller: jwtController,
              decoration: const InputDecoration(
                labelText: 'Authentication Token',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _isLoading = false;
              });
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final jwt = jwtController.text.trim();
              if (jwt.isNotEmpty) {
                await AuthService.storeJWT(jwt);
                Navigator.of(context).pop();
                
                // Navigate to the home page
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const MyHomePage()),
                  );
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
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
            
            // OAuth providers section
            if (_oauthProviders.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Or sign in with:',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_loadingProviders)
                const Center(child: CircularProgressIndicator())
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _oauthProviders.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final provider = _oauthProviders[index];
                    final displayName = provider.name.substring(0, 1).toUpperCase() + provider.name.substring(1);
                    
                    return ElevatedButton.icon(
                      onPressed: () => _loginWithOAuth(
                        provider.name,
                        provider.authorize,
                        provider.clientId,
                        'com.agixt.mobile://callback',
                      ),
                      icon: Icon(_getIconForProvider(provider.name)),
                      label: Text('Continue with $displayName'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}