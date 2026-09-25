import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AES-GCM encryption for sensitive SQLite values. The per-install key is kept
/// in Android Keystore / iOS Keychain via flutter_secure_storage.
class LocalDataCipher {
  LocalDataCipher._(this._key);

  static const _keyName = 'roadguard.local.data-key.v1';
  static const _textPrefix = 'rgenc1:';
  static const _photoMagic = [0x52, 0x47, 0x45, 0x31]; // RGE1
  static const _storage = FlutterSecureStorage();
  static final _algorithm = AesGcm.with256bits();
  final SecretKey _key;

  static Future<LocalDataCipher> load() async {
    var encoded = await _storage.read(key: _keyName);
    if (encoded == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      encoded = base64Encode(bytes);
      await _storage.write(key: _keyName, value: encoded);
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) throw StateError('Local data key is invalid.');
    return LocalDataCipher._(SecretKey(bytes));
  }

  bool isEncryptedText(String value) => value.startsWith(_textPrefix);
  bool isEncryptedBytes(List<int> value) {
    if (value.length < _photoMagic.length) return false;
    for (var i = 0; i < _photoMagic.length; i++) {
      if (value[i] != _photoMagic[i]) return false;
    }
    return true;
  }

  Future<String> encryptText(String value) async {
    if (isEncryptedText(value)) return value;
    final box = await _algorithm.encrypt(utf8.encode(value), secretKey: _key);
    return _textPrefix + base64Encode(_pack(box));
  }

  Future<String> decryptText(String value) async {
    if (!isEncryptedText(value)) return value; // Upgrade legacy local rows.
    final bytes = base64Decode(value.substring(_textPrefix.length));
    final box = _unpack(bytes, 12);
    return utf8.decode(await _algorithm.decrypt(box, secretKey: _key));
  }

  Future<List<int>> encryptBytes(List<int> value) async {
    if (isEncryptedBytes(value)) return value;
    final box = await _algorithm.encrypt(value, secretKey: _key);
    return [..._photoMagic, ..._pack(box)];
  }

  Future<List<int>> decryptBytes(List<int> value) async {
    if (!isEncryptedBytes(value)) return value;
    final box = _unpack(value.sublist(_photoMagic.length), 12);
    return await _algorithm.decrypt(box, secretKey: _key);
  }

  List<int> _pack(SecretBox box) => [
    ...box.nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ];

  SecretBox _unpack(List<int> bytes, int nonceSize) {
    const macSize = 16;
    if (bytes.length < nonceSize + macSize) {
      throw const FormatException('Encrypted local data is incomplete.');
    }
    return SecretBox(
      bytes.sublist(nonceSize, bytes.length - macSize),
      nonce: bytes.sublist(0, nonceSize),
      mac: Mac(bytes.sublist(bytes.length - macSize)),
    );
  }
}
