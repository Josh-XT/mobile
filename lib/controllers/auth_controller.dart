import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart'; // Use ChangeNotifier instead of GetxController
import 'package:http/http.dart' as http;
import '../services/config_service.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart'; // The newly ported service

// Using ChangeNotifier for state management to integrate with Provider
class AuthController with ChangeNotifier {
  final ConfigService _configService;
  final SettingsService _settingsService;
  late final AuthService _authService; // The service handling browser flow

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  List<Map<String, dynamic>> _oauthProviders = [];
  List<Map<String, dynamic>> get oauthProviders => _oauthProviders;

  bool _isProvidersLoading = false;
  bool get isProvidersLoading => _isProvidersLoading;

  // Constructor requiring the services
  AuthController(this._configService, this._settingsService) {
    // Initialize AuthService with the base URI from ConfigService
    _authService = AuthService(baseUri: _configService.agixtServer);
    _initializeController();

    // Listen for server config changes to update AuthService and fetch providers
    _configService.addListener(_handleConfigChange);
  }

  @override
  void dispose() {
    _configService.removeListener(_handleConfigChange);
    _authService.dispose(); // Dispose the OAuth service
    super.dispose();
  }

  void _handleConfigChange() {
    print("[AuthController] Config changed. Updating AuthService URI and fetching providers.");
    _authService.updateBaseUri(_configService.agixtServer);
    // Re-fetch providers if the server is configured
    if (_configService.isConfigured) {
      fetchOAuthProviders();
    } else {
      _oauthProviders = [];
      _isLoggedIn = false; // Log out if server config is lost
      _setError(''); // Clear errors
      notifyListeners();
    }
  }

  Future<void> _initializeController() async {
    print("[AuthController] Initializing...");
    await _restoreSavedToken();
    // Fetch providers initially if server is configured
    if (_configService.isConfigured) {
       await fetchOAuthProviders();
    }
  }

  Future<void> _restoreSavedToken() async {
    print("[AuthController] Attempting to restore saved token...");
    final savedJwt = await _settingsService.getJwt();
    print("[AuthController] Retrieved JWT from secure storage: ${savedJwt == null ? 'null' : 'present'}");

    if (savedJwt != null && savedJwt.isNotEmpty) {
      // Basic check if token looks like a JWT (optional, could add jwt_decoder)
      if (savedJwt.split('.').length == 3) {
         print("[AuthController] Restoring token and setting logged in state.");
        _isLoggedIn = true;
      } else {
         print("[AuthController] Invalid JWT format found in storage. Clearing.");
         await _settingsService.clearJwt();
         _isLoggedIn = false;
      }
    } else {
      print("[AuthController] No valid token found.");
      _isLoggedIn = false;
    }
    notifyListeners(); // Notify about login state change
  }

  // Saves the JWT using SettingsService
  Future<void> _saveToken(String jwt) async {
    print("[AuthController] Saving JWT to secure storage.");
    await _settingsService.saveJwt(jwt);
    _isLoggedIn = true;
    notifyListeners();
  }

  // Clears the JWT using SettingsService
  Future<void> logout() async {
    print("[AuthController] Logging out and clearing token.");
    await _settingsService.clearJwt();
    _isLoggedIn = false;
    _oauthProviders = []; // Clear providers on logout
    _setError(''); // Clear errors
    notifyListeners();
  }

  // Check login status (primarily based on token presence)
  Future<bool> checkLoginStatus() async {
     await _restoreSavedToken(); // Ensure state is up-to-date
     return _isLoggedIn;
  }

  // Helper to set loading state
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  // Helper to set error message
  void _setError(String errorMessage) {
    if (_error != errorMessage) {
      _error = errorMessage;
      notifyListeners();
    }
  }

  // --- OAuth Methods ---

  Future<void> fetchOAuthProviders() async {
    if (!_configService.isConfigured) {
      print("[AuthController] Server not configured. Cannot fetch OAuth providers.");
      _oauthProviders = [];
      notifyListeners();
      return;
    }

    _isProvidersLoading = true;
    _setError('');
    notifyListeners();

    final url = Uri.parse('${_configService.agixtServer}/v1/oauth');
    final Map<String, String> headers = {'Accept': 'application/json'};
    // Add Authorization header ONLY if already logged in (linking accounts scenario)
    final currentJwt = await _settingsService.getJwt();
    if (currentJwt != null && currentJwt.isNotEmpty) {
       headers['Authorization'] = 'Bearer $currentJwt';
    }


    try {
      print("[AuthController] Fetching OAuth providers from: $url");
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 15));

      print("[AuthController] OAuth providers response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);

        if (decodedBody is Map<String, dynamic> &&
            decodedBody.containsKey('providers') &&
            decodedBody['providers'] is List) {

          // Filter and map providers similar to source controller
          final List<Map<String, dynamic>> providers = List<Map<String, dynamic>>.from(
            decodedBody['providers'].map((item) {
              if (item is Map<String, dynamic>) {
                // Ensure required fields are present and client_id is not empty
                 if ((item['name']?.isNotEmpty ?? false) &&
                     (item['authorize']?.isNotEmpty ?? false) &&
                     (item['client_id']?.isNotEmpty ?? false)) {
                    // Default pkce_required to false if null
                    bool pkceRequired = item["pkce_required"] ?? false;
                    // Source logic: Force PKCE for Google. Re-evaluate if needed.
                    // if (item["name"]?.toLowerCase() == "google") {
                    //   pkceRequired = true;
                    // }
                    return {
                      "name": item["name"],
                      "scopes": item["scopes"] ?? "", // Default scopes to empty string if null
                      "authorize": item["authorize"],
                      "client_id": item["client_id"],
                      "pkce_required": pkceRequired,
                    };
                 } else {
                    print("Warning: Skipping OAuth provider due to missing name, authorize url, or client_id: $item");
                    return null; // Mark for removal
                 }
              } else {
                print("Warning: Unexpected item type in OAuth providers list: $item");
                return null; // Mark for removal
              }
            }).where((item) => item != null) // Remove null entries
          );

          _oauthProviders = providers;
          print("[AuthController] Loaded ${_oauthProviders.length} valid OAuth providers.");

        } else {
          throw Exception("Unexpected response format for OAuth providers. Got: ${response.body}");
        }
      } else {
         throw Exception("Failed to load OAuth providers: ${response.statusCode} ${response.reasonPhrase}");
      }
    } catch (e) {
      print("[AuthController] Error fetching OAuth providers: $e");
      _setError('Failed to load OAuth providers: ${e.toString()}');
      _oauthProviders = [];
    } finally {
      _isProvidersLoading = false;
      notifyListeners();
    }
  }

  // Renamed from loginWithOAuth to match previous structure better
  Future<bool> signInWithOAuth(Map<String, dynamic> provider) async {
    if (!_configService.isConfigured) {
      _setError('Server not configured.');
      return false;
    }

    _setError('');
    _setLoading(true);

    try {
      // Validate provider data (already filtered in fetchOAuthProviders)
      final String providerName = provider['name'];
      final String authorizationUrl = provider['authorize'];
      final String clientId = provider['client_id'];
      final String scopes = provider['scopes'];
      final bool pkceRequired = provider['pkce_required'];

      // Define additional parameters if needed (e.g., for Google refresh token)
      Map<String, String> additionalParams = {};
      if (providerName.toLowerCase() == 'google') {
        additionalParams['access_type'] = 'offline';
        additionalParams['prompt'] = 'consent';
      }

      // 1. Start browser flow using AuthService
      print("[AuthController] Starting OAuth flow for $providerName via AuthService...");
      final OAuthResult oauthResult = await _authService.authenticate(
        authorizationUrl: authorizationUrl,
        clientId: clientId,
        scopes: scopes,
        providerName: providerName,
        pkceRequired: pkceRequired,
        additionalParams: additionalParams,
      );

      print("[AuthController] AuthService returned code. Exchanging with backend...");
      print("[AuthController] State JWT length: ${oauthResult.state.length}");

      // 2. Exchange code with backend
      final backendUrl = Uri.parse('${_configService.agixtServer}/v1/oauth2/${oauthResult.providerName}');
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-OAuth-Provider': oauthResult.providerName.toLowerCase(),
        // Add existing token if linking account
         if (_isLoggedIn) 'Authorization': 'Bearer ${await _settingsService.getJwt()}',
      };
      final body = jsonEncode({
        'code': oauthResult.code,
        'state': oauthResult.state, // Send state received from backend PKCE/AuthService
        'redirect_uri': oauthResult.redirectUri, // Send the actual redirect URI used
        'referrer': oauthResult.redirectUri, // Source used this, keeping it
      });

      print("[AuthController] Posting code to backend: $backendUrl");
      // print("[AuthController] Request body: $body"); // Avoid logging sensitive info like code/state

      final response = await http.post(backendUrl, headers: headers, body: body)
          .timeout(const Duration(seconds: 45));

      print("[AuthController] Backend exchange response status: ${response.statusCode}");
      // print("[AuthController] Backend response body: ${response.body}"); // Avoid logging token

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);

        // Handle account linking success (if user was already logged in)
         if (_isLoggedIn && responseData.containsKey('detail') && responseData['detail'].contains("connected successfully")) {
           print("[AuthController] OAuth provider ${oauthResult.providerName} linked successfully.");
           _setError('Account linked successfully!'); // Use error field for status message
           _setLoading(false);
           return true; // Indicate success, but stay on login page? Or navigate? TBD by UI logic.
         }

        // Handle new login: Extract token
        String? extractedToken;
        if (responseData.containsKey('token') && responseData['token'] != null) {
          extractedToken = responseData['token'];
          // Remove "Bearer " prefix if present, as SettingsService likely expects raw token
          if (extractedToken!.startsWith('Bearer ')) {
            extractedToken = extractedToken.substring(7);
          }
        } else if (responseData.containsKey('detail') && responseData['detail'] != null) {
          // Try extracting from magic link in 'detail' (source project fallback)
          try {
             final uri = Uri.parse(responseData['detail']);
             extractedToken = uri.queryParameters['token']?.trim();
          } catch (_) { /* Ignore parsing errors */ }
        }

        if (extractedToken != null && extractedToken.isNotEmpty) {
          print("[AuthController] Successfully exchanged code for token.");
          await _saveToken(extractedToken); // Save token and set logged in state
          _setLoading(false);
          return true; // Indicate successful login
        } else {
          throw Exception('Token not found in backend response.');
        }
      } else {
        // Handle backend error during code exchange
        String errorMessage = 'Failed to exchange OAuth code with backend.';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['detail'] ?? errorMessage;
        } catch (_) {
           errorMessage = "${response.statusCode}: ${response.reasonPhrase ?? 'Unknown backend error'}";
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      print("[AuthController] OAuth Error: $e");
      _setError(e.toString());
      // Don't logout if the error occurred during an attempt to link accounts
      // if (!_isLoggedIn) { // This logic might be flawed, reconsider if needed
      //    await logout(); // Ensure logged out state on failure
      // }
      _setLoading(false);
      _authService.dispose(); // Clean up OAuth service state on error
      return false;
    } finally {
       // Ensure loading is always set to false, even if errors occur before setting it
       if (_isLoading) {
          _setLoading(false);
       }
    }
  }
}