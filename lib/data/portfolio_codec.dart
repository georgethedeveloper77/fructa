import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

import 'models/holding.dart';

/// Raised when an imported file is not a Fructa backup (wrong magic header).
class NotAFructaBackup implements Exception {
  const NotAFructaBackup();
}

/// Raised when the supplied recovery code cannot decrypt the file. In AES-GCM
/// this is indistinguishable from a corrupted file: both fail the auth tag.
class BadRecoveryCode implements Exception {
  const BadRecoveryCode();
}

/// One serialization for every backup target. Supabase, Drive appDataFolder and
/// the encrypted export all carry the identical `{schema, holdings}` payload, so
/// a backup written by one path restores through any other.
///
/// The plain payload is used as-is by Supabase and by the Drive appDataFolder
/// copy (private to the app, protected by the Google account boundary). The
/// encrypted container is used only for the portable export, which leaves every
/// trust boundary and therefore never travels in the clear.
class PortfolioCodec {
  PortfolioCodec._();

  static const schema = 1;

  static Map<String, dynamic> buildPayload(List<Holding> holdings) => {
        'schema': schema,
        'holdings': holdings.map((h) => h.toMap()).toList(),
      };

  static List<Holding> parsePayload(Map<String, dynamic> data) =>
      ((data['holdings'] as List?) ?? const [])
          .map((e) => Holding.fromMap((e as Map).cast<String, dynamic>()))
          .toList();

  // Encrypted container --------------------------------------------------------
  // Byte layout, self describing so a future reader can validate before trying
  // to decrypt:
  //
  //   MAGIC(4) 'FRC1' | VERSION(1) | SALT(16) | NONCE(12) | MAC(16) | CIPHERTEXT
  //
  // Key derivation is PBKDF2-HMAC-SHA256 over the recovery code with a random
  // per-file salt, so two exports of the same portfolio never produce the same
  // bytes and a leaked file cannot be dictionary attacked cheaply. The code is
  // already high entropy (machine generated), so the iteration count is a floor,
  // not the only thing standing between an attacker and the data.
  static const _magic = <int>[0x46, 0x52, 0x43, 0x31]; // 'FRC1'
  static const _version = 1;
  static const _saltLen = 16;
  static const _nonceLen = 12;
  static const _macLen = 16;
  static const _iterations = 120000;
  static const _headerLen = 4 + 1 + _saltLen + _nonceLen + _macLen;

  static final _gcm = AesGcm.with256bits();
  static final _rng = Random.secure();

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  static Future<SecretKey> _deriveKey(String code, List<int> salt) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code.trim().toUpperCase())),
      nonce: salt,
    );
  }

  static Future<Uint8List> encodeEncrypted(
    List<Holding> holdings,
    String code,
  ) async {
    final plain = utf8.encode(jsonEncode(buildPayload(holdings)));
    final salt = _randomBytes(_saltLen);
    final nonce = _randomBytes(_nonceLen);
    final key = await _deriveKey(code, salt);
    final box = await _gcm.encrypt(plain, secretKey: key, nonce: nonce);

    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..add(salt)
      ..add(nonce)
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    return out.toBytes();
  }

  static Future<List<Holding>> decodeEncrypted(
    Uint8List bytes,
    String code,
  ) async {
    if (bytes.length < _headerLen) throw const NotAFructaBackup();
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) throw const NotAFructaBackup();
    }

    var off = 4 + 1; // past magic + version
    final salt = bytes.sublist(off, off + _saltLen);
    off += _saltLen;
    final nonce = bytes.sublist(off, off + _nonceLen);
    off += _nonceLen;
    final mac = bytes.sublist(off, off + _macLen);
    off += _macLen;
    final cipher = bytes.sublist(off);

    final key = await _deriveKey(code, salt);
    final List<int> plain;
    try {
      plain = await _gcm.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw const BadRecoveryCode();
    }

    final data = (jsonDecode(utf8.decode(plain)) as Map).cast<String, dynamic>();
    return parsePayload(data);
  }
}
