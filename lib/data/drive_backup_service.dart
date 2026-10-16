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

/// Google sign-in failed for a reason other than the user backing out, most
/// often a setup problem (the app's SHA-1 or OAuth client in Google Cloud).
/// Carries Google's own code, so the screen can say what went wrong instead
/// of doing nothing.
class DriveSignInFailed implements Exception {
  const DriveSignInFailed(this.code, this.detail);
  final String code;
  final String? detail;

  @override
  String toString() =>
      detail == null || detail!.isEmpty ? code : '$code: $detail';
}

/// Turns a Google sign-in error into the right exception: a backed-out
/// prompt is a cancel; anything else is a failure worth showing.
///
/// Android reports some setup failures as `canceled` too, with a reason such
/// as "[16] Account reauth failed" when the app's SHA-1 is not registered. So
/// a cancel only counts as the user backing out when Google gives no other
/// reason.
Exception _signInError(GoogleSignInException e) {
  final why = (e.description ?? '').trim();
  final userBackedOut =
      e.code == GoogleSignInExceptionCode.canceled &&
      (why.isEmpty || why.toLowerCase().contains('cancel'));
  return userBackedOut
      ? const DriveCancelled()
      : DriveSignInFailed(e.code.name, why.isEmpty ? null : why);
}

/// Tier 1 of the two tier backup: one JSON file, `fructa-portfolio.json`, in a
/// folder called Fructa in the user's own Drive. Visible, so the user can see
/// and download it, and replaced on every backup so there is only ever the
/// latest. The `drive.file` scope lets the app touch only files it created,
/// never the rest of the Drive, and a new phone signed in to the same account
/// finds the folder again. The payload is the plain [PortfolioCodec] payload:
/// the Google account boundary is the privacy control here.
///
/// Earlier versions kept the file hidden in the app's `appDataFolder`. That
/// one is still read, once, when no Fructa folder backup exists yet, and its
/// contents are written into the folder, so nobody loses a backup.
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
    'https://www.googleapis.com/auth/drive.file',
    // Read once, to carry the old hidden backup into the folder.
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const _legacyName = 'portfolio.json';
  static const _folderName = 'Fructa';
  static const _fileName = 'fructa-portfolio.json';
  static const _folderMime = 'application/vnd.google-apps.folder';
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
      } on GoogleSignInException catch (e) {
        throw _signInError(e);
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
      } on GoogleSignInException catch (e) {
        throw _signInError(e);
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

  /// Runs a Drive file query; the first match as (id, modifiedTime), or null.
  Future<(String, DateTime?)?> _first(
    String token,
    String q, {
    String? spaces,
  }) async {
    final uri = Uri.parse('$_api/files').replace(
      queryParameters: {
        'q': q,
        'spaces': ?spaces,
        'fields': 'files(id,modifiedTime)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '1',
      },
    );
    final res = await http.get(uri, headers: _authHeader(token));
    if (res.statusCode != 200) {
      throw Exception('drive list HTTP ${res.statusCode}');
    }
    final files = (jsonDecode(res.body) as Map)['files'] as List? ?? const [];
    if (files.isEmpty) return null;
    final f = files.first as Map;
    return (
      f['id'] as String,
      DateTime.tryParse('${f['modifiedTime'] ?? ''}')?.toLocal(),
    );
  }

  /// The Fructa folder's id, created when [create] and it does not exist.
  Future<String?> _folder(String token, {required bool create}) async {
    final found = await _first(
      token,
      "name = '$_folderName' and mimeType = '$_folderMime' and trashed = false",
    );
    if (found != null || !create) return found?.$1;
    final res = await http.post(
      Uri.parse('$_api/files').replace(queryParameters: {'fields': 'id'}),
      headers: {..._authHeader(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'name': _folderName, 'mimeType': _folderMime}),
    );
    if (res.statusCode != 200) {
      throw Exception('drive folder HTTP ${res.statusCode}');
    }
    return (jsonDecode(res.body) as Map)['id'] as String?;
  }

  /// The backup file in the Fructa folder.
  Future<(String, DateTime?)?> _file(String token, String folderId) => _first(
    token,
    "name = '$_fileName' and '$folderId' in parents and trashed = false",
  );

  /// Writes [payload] as the folder's backup file, replacing it when it exists.
  Future<DateTime?> _write(String token, String payload) async {
    final folderId = await _folder(token, create: true);
    if (folderId == null) throw Exception('drive folder missing');
    final existing = await _file(token, folderId);

    final http.Response res;
    if (existing != null) {
      res = await http.patch(
        Uri.parse('$_uploadApi/files/${existing.$1}').replace(
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
        'parents': [folderId],
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

  Future<String> _download(String token, String id) async {
    final res = await http.get(
      Uri.parse('$_api/files/$id').replace(queryParameters: {'alt': 'media'}),
      headers: _authHeader(token),
    );
    if (res.statusCode != 200) {
      throw Exception('drive download HTTP ${res.statusCode}');
    }
    return res.body;
  }

  /// Replace the backup in the Fructa folder with the current portfolio.
  /// Returns Drive's modified time, or null when no token was available (the
  /// user declined, or [interactive] is false and a prompt would be needed).
  Future<DateTime?> backup({bool interactive = true}) async {
    final String? token;
    try {
      token = await _token(interactive: interactive);
    } on DriveCancelled {
      return null;
    }
    if (token == null) return null;
    return _write(
      token,
      jsonEncode(PortfolioCodec.buildPayload(_holdings.all())),
    );
  }

  /// Read the backup: the Fructa folder's file, else the old hidden one, which
  /// is then copied into the folder. Null when not connected (and
  /// [interactive] false) or when there is no backup anywhere.
  Future<DriveRestore?> restore({bool interactive = true}) async {
    final String? token;
    try {
      token = await _token(interactive: interactive);
    } on DriveCancelled {
      return null;
    }
    if (token == null) return null;

    final folderId = await _folder(token, create: false);
    final found = folderId == null ? null : await _file(token, folderId);
    if (found != null) {
      final data = (jsonDecode(await _download(token, found.$1)) as Map)
          .cast<String, dynamic>();
      return DriveRestore(PortfolioCodec.parsePayload(data), found.$2);
    }

    final legacy = await _first(
      token,
      "name = '$_legacyName'",
      spaces: 'appDataFolder',
    );
    if (legacy == null) return null;
    final body = await _download(token, legacy.$1);
    // Carry it into the folder, so the next phone finds it there.
    await _write(token, body);
    final data = (jsonDecode(body) as Map).cast<String, dynamic>();
    return DriveRestore(PortfolioCodec.parsePayload(data), legacy.$2);
  }
}

final driveBackupServiceProvider = Provider<DriveBackupService>(
  (ref) => DriveBackupService(ref.read(holdingsRepositoryProvider)),
);

/// Last successful Drive sync time (session state; drives the Drive line in the
/// backup sheet, mirroring [lastBackupProvider] for the Supabase path).
final lastDriveSyncProvider = StateProvider<DateTime?>((ref) => null);
