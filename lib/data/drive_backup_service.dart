import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'models/holding.dart';
import 'portfolio_codec.dart';
import 'providers.dart';
import 'repositories/holdings_repository.dart';

/// Result of a Drive restore lookup. Null (not this) means no backup exists;
/// an empty [holdings] means a backup exists but held nothing.
class DriveRestore {
  final List<Holding> holdings;
  final DateTime? modifiedAt;
  const DriveRestore(this.holdings, this.modifiedAt);
  bool get isEmpty => holdings.isEmpty;
}

/// Raised when the user dismisses the Google account picker or consent screen.
/// The UI treats this as a silent no-op rather than an error toast.
class DriveCancelled implements Exception {
  const DriveCancelled();
}

/// Tier 1 of the two tier backup: a single private JSON file in the app's Drive
/// `appDataFolder`. Invisible in the user's Drive UI, readable only by this app,
/// and it survives a reinstall as long as the same Google account signs in,
/// which is exactly the phone upgrade path. The payload is the plain
/// [PortfolioCodec] payload: the Google account boundary is the privacy control
/// here, so no on device key is involved and a new phone restores with one sign
/// in and no recovery code.
///
/// Talks to the Drive v3 REST API directly with [http] rather than pulling in
/// `googleapis` and the google_sign_in auth bridge, whose v7 interaction is
/// where most of the current Drive breakage lives. All we need is a bearer
/// token for the `drive.appdata` scope, which google_sign_in hands over on its
/// own.
class DriveBackupService {
  DriveBackupService(this._holdings);

  final HoldingsRepository _holdings;

  static const _scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const _fileName = 'portfolio.json';
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _uploadApi = 'https://www.googleapis.com/upload/drive/v3';

  // Left empty on purpose. iOS resolves its client id from GIDClientID in
  // Info.plist and Android from the OAuth client matched by package name and
  // SHA-1 in the Google Cloud project, so no id needs to live in the binary. If
  // Android sign in ever returns "unregistered caller", drop the Web OAuth
  // client id into [_serverClientId] and rebuild.
  static const _iosClientId =
      '665013279649-4blh319j6qg41jpv552s84pplgv6vj7v.apps.googleusercontent.com';
  static const _serverClientId =
      '665013279649-6o4hl6mpbag4r7a7glepka2vu8d1haeg.apps.googleusercontent.com';

  bool _inited = false;
  String? _email;

  /// The connected account label, or null when not connected. Populated by any
  /// successful token fetch, so the Settings line can read it back.
  String? get email => _email;

  Future<void> _ensureInit() async {
    if (_inited) return;
    await GoogleSignIn.instance.initialize(
      clientId: _iosClientId.isEmpty ? null : _iosClientId,
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _inited = true;
  }

  /// A bearer token for the Drive scope. When [interactive] is false this only
  /// uses the silent paths and returns null if a prompt would be required, so it
  /// is safe to call at launch without throwing a picker in the user's face.
  Future<String?> _token({required bool interactive}) async {
    await _ensureInit();
    final gsi = GoogleSignIn.instance;

    GoogleSignInAccount? account = await gsi.attemptLightweightAuthentication();
    if (account == null) {
      if (!interactive || !gsi.supportsAuthenticate()) return null;
      try {
        account = await gsi.authenticate();
      } on GoogleSignInException {
        throw const DriveCancelled();
      }
    }
    // No null guard here on purpose. authenticate() returns a non-nullable
    // account and throws GoogleSignInException when the user backs out, which
    // the catch above already turns into DriveCancelled. So past this point the
    // account exists, and flow analysis knows it. The guards that used to sit
    // here were unreachable, which the analyzer reported as dead_code.

    GoogleSignInClientAuthorization? authz = await account.authorizationClient
        .authorizationForScopes(_scopes);
    if (authz == null) {
      // Silent authorization came back empty, so consent has not been given for
      // these scopes yet. Only a prompt can fix that.
      if (!interactive) return null;
      try {
        authz = await account.authorizationClient.authorizeScopes(_scopes);
      } on GoogleSignInException {
        throw const DriveCancelled();
      }
    }

    // Same reasoning: authorizeScopes() is non-nullable and throws on refusal.
    _email = account.email;
    return authz.accessToken;
  }

  /// True when a Drive token can be obtained silently (already connected).
  Future<bool> isConnected() async {
    try {
      return await _token(interactive: false) != null;
    } catch (_) {
      return false;
    }
  }

  /// Interactive connect. Returns the account label, or null if the user backed
  /// out of the picker or consent.
  Future<String?> connect() async {
    try {
      final tok = await _token(interactive: true);
      return tok == null ? null : _email;
    } on DriveCancelled {
      return null;
    }
  }

  /// Revoke this app's Drive access and forget the account.
  Future<void> disconnect() async {
    await _ensureInit();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      /* already gone */
    }
    _email = null;
  }

  Map<String, String> _authHeader(String token) => {
    'Authorization': 'Bearer $token',
  };

  /// The id of the single appData backup file, or null when none exists.
  Future<String?> _findFileId(String token) async {
    final uri = Uri.parse('$_api/files').replace(
      queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name = '$_fileName'",
        'fields': 'files(id,modifiedTime)',
        'pageSize': '1',
      },
    );
    final res = await http.get(uri, headers: _authHeader(token));
    if (res.statusCode != 200) {
      throw Exception('drive list HTTP ${res.statusCode}');
    }
    final files = (jsonDecode(res.body) as Map)['files'] as List? ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map)['id'] as String?;
  }

  /// Push the current portfolio into appDataFolder, creating or overwriting the
  /// single backup file. Returns Drive's modified time on success, or null if
  /// the user declined the Google prompt.
  Future<DateTime?> backup() async {
    final String? token;
    try {
      token = await _token(interactive: true);
    } on DriveCancelled {
      return null;
    }
    if (token == null) return null;

    final payload = jsonEncode(PortfolioCodec.buildPayload(_holdings.all()));
    final existingId = await _findFileId(token);

    final http.Response res;
    if (existingId != null) {
      res = await http.patch(
        Uri.parse('$_uploadApi/files/$existingId').replace(
          queryParameters: {'uploadType': 'media', 'fields': 'id,modifiedTime'},
        ),
        headers: {
          ..._authHeader(token),
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: payload,
      );
    } else {
      const boundary = 'fructa_backup_boundary';
      final meta = jsonEncode({
        'name': _fileName,
        'parents': ['appDataFolder'],
      });
      final body =
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$meta\r\n'
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$payload\r\n'
          '--$boundary--';
      res = await http.post(
        Uri.parse('$_uploadApi/files').replace(
          queryParameters: {
            'uploadType': 'multipart',
            'fields': 'id,modifiedTime',
          },
        ),
        headers: {
          ..._authHeader(token),
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      );
    }

    if (res.statusCode != 200) {
      throw Exception('drive upload HTTP ${res.statusCode}');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return DateTime.tryParse((m['modifiedTime'] ?? '') as String)?.toLocal();
  }

  /// Read the appData backup. Null when not connected (and [interactive] false)
  /// or when no backup file exists.
  Future<DriveRestore?> restore({bool interactive = true}) async {
    final String? token;
    try {
      token = await _token(interactive: interactive);
    } on DriveCancelled {
      return null;
    }
    if (token == null) return null;

    final id = await _findFileId(token);
    if (id == null) return null;

    final res = await http.get(
      Uri.parse('$_api/files/$id').replace(queryParameters: {'alt': 'media'}),
      headers: _authHeader(token),
    );
    if (res.statusCode != 200) {
      throw Exception('drive download HTTP ${res.statusCode}');
    }
    final data = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    return DriveRestore(PortfolioCodec.parsePayload(data), null);
  }
}

final driveBackupServiceProvider = Provider<DriveBackupService>(
  (ref) => DriveBackupService(ref.read(holdingsRepositoryProvider)),
);

/// Last successful Drive sync time (session state; drives the Drive line in the
/// backup sheet, mirroring [lastBackupProvider] for the Supabase path).
final lastDriveSyncProvider = StateProvider<DateTime?>((ref) => null);
