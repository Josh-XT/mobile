import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:http/http.dart' as http;

// Renamed from OAuthService to AuthService to match existing project structure
// This service handles the browser interaction part of OAuth and PKCE.
// The exchange of the code for a token happens in AuthController.

class OAuthResult {
  final String code;
  final String providerName;
  final String state;
  final String redirectUri; // Add redirectUri

  OAuthResult({
    required this.code,
    required this.providerName,
    required this.state,
    required this.redirectUri, // Add to constructor
  });
}

class AuthService {
  HttpServer? _server;
  final int _port = 8080; // Or choose a different available port
  final String _redirectPath = '/oauth/callback'; // Standard callback path
  Completer<OAuthResult>? _completer;
  String _baseUri; // To fetch PKCE challenge from backend

  // Constructor accepts the AGiXT server base URI
  AuthService({required String baseUri}) : _baseUri = baseUri;

  // Method to update baseUri if server config changes
  void updateBaseUri(String newUri) {
    _baseUri = newUri;
    print("[AuthService] Base URI updated to: $_baseUri");
  }

  // Generate a random string for state (if not using backend PKCE state)
  String _generateRandomString(int length) {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final rnd = Random.secure();
    return List.generate(length, (index) => chars[rnd.nextInt(chars.length)]).join();
  }

  // Generate PKCE code challenge (Not used if backend provides it)
  // String _generateCodeChallenge(String codeVerifier) {
  //   final bytes = utf8.encode(codeVerifier);
  //   final digest = sha256.convert(bytes);
  //   // Base64Url encoding without padding
  //   return base64Url.encode(digest.bytes).replaceAll('=', '');
  // }

  // Starts a local server to listen for the OAuth redirect
  Future<void> _startServer(String providerName, String expectedState, String redirectUri) async {
    if (_server != null) {
      await _stopServer(); // Ensure previous server is stopped
    }

    final router = Router();

    // Define the handler for the redirect URI
    Future<Response> handleRedirect(Request request) async {
      final code = request.url.queryParameters['code'];
      final stateReceived = request.url.queryParameters['state'];

      print("[AuthService] Redirect received. Code: ${code != null && code.isNotEmpty ? 'Present' : 'Missing'}, State: ${stateReceived ?? 'Missing'}");
      print("[AuthService] Expected State: $expectedState");

      // Validate received state matches expected state
      if (stateReceived != expectedState) {
        print("[AuthService] State mismatch error. Received: $stateReceived");
        _completer?.completeError(Exception('OAuth failed: Invalid state received.'));
        await _stopServer();
        return Response.forbidden(
          '<html><body><h1>Authentication Failed</h1><p>State mismatch. Please try again.</p></body></html>',
          headers: {'content-type': 'text/html'},
        );
      }

      if (code != null && code.isNotEmpty) {
        // Successfully received code
        print("[AuthService] Received valid authorization code. State validated.");
        _completer?.complete(OAuthResult(
          code: code,
          providerName: providerName,
          state: stateReceived!, // State is validated above
          redirectUri: redirectUri, // Include redirectUri in the result
        ));
        await _stopServer(); // Stop server after handling redirect

        // Return a simple success page
        return Response.ok(
          '<html><body><h1>Authentication Successful!</h1><p>You can close this window and return to the app.</p></body></html>',
          headers: {'content-type': 'text/html'},
        );
      } else {
        // Handle error case from provider
        final error = request.url.queryParameters['error'];
        final errorDescription = request.url.queryParameters['error_description'];
        print("[AuthService] OAuth error received: $error - $errorDescription");
        _completer?.completeError(
            Exception('OAuth failed: ${error ?? 'Unknown error'} - ${errorDescription ?? 'No description'}'));
        await _stopServer();
        return Response.internalServerError(
          body: '<html><body><h1>Authentication Failed</h1><p>${errorDescription ?? error ?? 'Unknown error'}</p></body></html>',
          headers: {'content-type': 'text/html'},
        );
      }
    }

    // Assign the handler function to the router
    router.get(_redirectPath, handleRedirect);

    try {
      // Use IPv4 loopback address explicitly for better compatibility
      _server = await shelf_io.serve(router, InternetAddress.loopbackIPv4, _port);
      print('[AuthService] OAuth redirect server listening on http://${_server!.address.host}:${_server!.port}');
    } catch (e) {
      print("[AuthService] Error starting shelf server: $e");
      final errorMsg = "Failed to start local server for OAuth redirect. Port $_port might be in use.";
      _completer?.completeError(Exception(errorMsg));
      // Don't rethrow here, let the completer handle the error propagation
    }
  }

  Future<void> _stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('[AuthService] OAuth redirect server stopped.');
    }
  }

  // Initiates the OAuth authentication flow
  Future<OAuthResult> authenticate({
    required String authorizationUrl,
    required String clientId,
    required String scopes,
    required String providerName,
    bool pkceRequired = false, // Indicates if the provider *requires* PKCE
    Map<String, String> additionalParams = const {},
  }) async {
    _completer = Completer<OAuthResult>();

    // Redirect URI construction (consistent with source)
    // Note: kIsWeb handling might need adjustment if web support is added later.
    // For now, assuming mobile/desktop focus.
    final String redirectUri = 'http://127.0.0.1:$_port$_redirectPath';
    print("[AuthService] Using Redirect URI: $redirectUri");

    String state;
    String? codeChallenge;
    // Determine if PKCE should be used (backend handles generation)
    // Source logic: Disable PKCE for Google due to backend incompatibility. Check if still valid.
    // bool usePkce = pkceRequired && providerName.toLowerCase() != 'google';
    bool usePkce = pkceRequired; // Assuming backend handles PKCE correctly now, including for Google. Adjust if needed.

    print("[AuthService] Authenticate called for $providerName. PKCE Required by provider: $pkceRequired. Using PKCE: $usePkce");

    // Get PKCE challenge and state from backend if using PKCE
    if (usePkce) {
      try {
        // The backend endpoint expects the redirect_uri used by the client
        final pkceUrl = Uri.parse('$_baseUri/v1/oauth2/pkce-simple').replace(
            queryParameters: {'redirect_uri': redirectUri});

        print("[AuthService] Getting PKCE challenge from backend: $pkceUrl");
        final pkceResponse = await http.get(pkceUrl).timeout(const Duration(seconds: 10));

        if (pkceResponse.statusCode == 200) {
          final pkceData = jsonDecode(pkceResponse.body);
          codeChallenge = pkceData['code_challenge'];
          state = pkceData['state']; // This state is crucial for backend validation
          if (codeChallenge == null || state == null) {
            throw Exception('Backend PKCE response missing challenge or state.');
          }
          print("[AuthService] Got PKCE challenge and state from backend.");
          print("[AuthService] State (from backend) length: ${state.length}");
        } else {
          throw Exception('Failed to get PKCE challenge from backend (${pkceResponse.statusCode}): ${pkceResponse.body}');
        }
      } catch (e) {
        print("[AuthService] Error getting PKCE challenge: $e");
        _completer?.completeError(Exception('Failed to setup PKCE: $e'));
        return _completer!.future; // Return future that will complete with error
      }
    } else {
      // Generate a simple state if not using PKCE
      state = _generateRandomString(32);
      print("[AuthService] Generated simple state (not using PKCE).");
    }

    // Start the local redirect server (only for non-web platforms)
    if (!kIsWeb) {
      try {
        // Pass the state (either from backend or generated) for validation
        await _startServer(providerName, state, redirectUri);
      } catch (e) {
        // Error handled by _startServer completing the completer
        print("[AuthService] Failed to start server during authenticate: $e");
        // Ensure completer has error if _startServer didn't set one
        if (_completer?.isCompleted == false) {
           _completer?.completeError(e);
        }
        return _completer!.future; // Return future that will complete with error
      }
    } else {
       // Handle web platform redirect logic if needed in the future
       print("[AuthService] Web platform detected. Local server not started.");
       // Web needs a different mechanism to capture the redirect.
       // flutter_web_auth_2 might be used here if adapting fully.
       // For now, focusing on non-web as per source logic.
       _completer?.completeError(UnsupportedError("OAuth web flow not fully implemented in this port."));
       return _completer!.future;
    }


    // Build the authorization URL
    final authUri = Uri.parse(authorizationUrl).replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'scope': scopes,
        'redirect_uri': redirectUri,
        'state': state, // Use the state (from backend or generated)
        if (usePkce && codeChallenge != null) 'code_challenge': codeChallenge,
        if (usePkce) 'code_challenge_method': 'S256',
        ...additionalParams,
      },
    );
    final String authUrl = authUri.toString();

    print("[AuthService] Launching OAuth URL: $authUrl");

    // Launch the URL
    try {
      if (await canLaunchUrl(authUri)) {
        // Source used platformDefault for web, externalApplication otherwise.
        // Sticking to externalApplication for non-web focus.
        final launchMode = LaunchMode.externalApplication;
        await launchUrl(authUri, mode: launchMode);
      } else {
        throw Exception('Could not launch $authUrl');
      }
    } catch (e) {
       print("[AuthService] Error launching URL: $e");
       _completer?.completeError(e);
       if (!kIsWeb) await _stopServer(); // Stop server if URL launch fails
    }


    // Wait for the completer (redirect handled by server or timeout)
    return _completer!.future.timeout(const Duration(minutes: 5), onTimeout: () {
      print("[AuthService] OAuth flow timed out.");
      if (!kIsWeb) _stopServer();
      // Ensure completer completes with error if not already completed
      if (!_completer!.isCompleted) {
         _completer!.completeError(TimeoutException('OAuth flow timed out after 5 minutes.'));
      }
      // The throw is implicit as the future returned by timeout throws on timeout
      // if onTimeout doesn't return a value or future.
      throw TimeoutException('OAuth flow timed out after 5 minutes.');
    }).catchError((e) {
       print("[AuthService] Error during OAuth flow: $e");
       if (!kIsWeb && _server != null) _stopServer(); // Ensure server stops on any error
       // Rethrow the error to propagate it
       throw e;
    });
  }

  // Call this method to clean up the server and completer
  Future<void> dispose() async {
    await _stopServer();
    if (_completer?.isCompleted == false) {
      _completer?.completeError(Exception('OAuth flow cancelled by dispose.'));
    }
    _completer = null;
    print("[AuthService] Disposed.");
  }
}