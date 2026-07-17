import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CryptoHelper {
  static const String _prefPrivateKey = 'e2ee_private_key';
  static const String _prefPublicKey = 'e2ee_public_key';

  // Generate RSA Key Pair (2048-bit)
  static pc.AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAKeyPair() {
    final secureRandom = pc.SecureRandom('Fortuna')
      ..seed(pc.KeyParameter(
        Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256))),
      ));

    final keyGen = RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    final public = pair.publicKey as RSAPublicKey;
    final private = pair.privateKey as RSAPrivateKey;

    return pc.AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(public, private);
  }

  // Convert RSAPublicKey to Base64 Modulus-Exponent JSON String
  static String publicKeyToPem(RSAPublicKey key) {
    final map = {
      'modulus': key.modulus.toString(),
      'exponent': key.publicExponent.toString(),
    };
    return base64.encode(utf8.encode(json.encode(map)));
  }

  // Parse RSAPublicKey from Base64 Modulus-Exponent String
  static RSAPublicKey publicKeyFromPem(String pem) {
    final decoded = json.decode(utf8.decode(base64.decode(pem)));
    final modulus = BigInt.parse(decoded['modulus']);
    final exponent = BigInt.parse(decoded['exponent']);
    return RSAPublicKey(modulus, exponent);
  }

  // Convert RSAPrivateKey to Base64 String
  static String privateKeyToPem(RSAPrivateKey key) {
    final map = {
      'modulus': key.modulus.toString(),
      'privateExponent': key.privateExponent.toString(),
      'p': key.p?.toString() ?? '',
      'q': key.q?.toString() ?? '',
    };
    return base64.encode(utf8.encode(json.encode(map)));
  }

  // Parse RSAPrivateKey from Base64 String
  static RSAPrivateKey privateKeyFromPem(String pem) {
    final decoded = json.decode(utf8.decode(base64.decode(pem)));
    final modulus = BigInt.parse(decoded['modulus']);
    final privateExponent = BigInt.parse(decoded['privateExponent']);
    final pStr = decoded['p'];
    final qStr = decoded['q'];
    final p = pStr.isNotEmpty ? BigInt.parse(pStr) : null;
    final q = qStr.isNotEmpty ? BigInt.parse(qStr) : null;
    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  // Initialize and retrieve RSA key pair for the user
  static Future<Map<String, String>> getOrGenerateKeys() async {
    final prefs = await SharedPreferences.getInstance();
    String? privPem = prefs.getString(_prefPrivateKey);
    String? pubPem = prefs.getString(_prefPublicKey);

    if (privPem == null || pubPem == null) {
      final pair = generateRSAKeyPair();
      privPem = privateKeyToPem(pair.privateKey);
      pubPem = publicKeyToPem(pair.publicKey);

      await prefs.setString(_prefPrivateKey, privPem);
      await prefs.setString(_prefPublicKey, pubPem);
    }

    return {
      'private': privPem,
      'public': pubPem,
    };
  }

  // RSA Encrypt a message (symmetric key) with a public key
  static String rsaEncrypt(String plaintext, String recipientPublicKeyPem) {
    final publicKey = publicKeyFromPem(recipientPublicKeyPem);
    final encrypter = enc.Encrypter(enc.RSA(publicKey: publicKey));
    final encrypted = encrypter.encrypt(plaintext);
    return encrypted.base64;
  }

  // RSA Decrypt a message (symmetric key) with the private key
  static String rsaDecrypt(String ciphertextBase64, String myPrivateKeyPem) {
    final privateKey = privateKeyFromPem(myPrivateKeyPem);
    final encrypter = enc.Encrypter(enc.RSA(privateKey: privateKey));
    final decrypted = encrypter.decrypt(enc.Encrypted.fromBase64(ciphertextBase64));
    return decrypted;
  }

  // AES-256 Symmetric Encryption
  static String aesEncrypt(String plaintext, String keyString) {
    final keyBytes = enc.Key.fromUtf8(keyString.padRight(32).substring(0, 32));
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return encrypted.base64;
  }

  // AES-256 Symmetric Decryption
  static String aesDecrypt(String ciphertextBase64, String keyString) {
    final keyBytes = enc.Key.fromUtf8(keyString.padRight(32).substring(0, 32));
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.cbc));
    try {
      final decrypted = encrypter.decrypt(enc.Encrypted.fromBase64(ciphertextBase64), iv: iv);
      return decrypted;
    } catch (e) {
      return "[Decryption Error: Invalid symmetric key]";
    }
  }

  // Generate a random 32-character alphanumeric key (AES Room Key)
  static String generateRandomAESKey() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(32, (index) => chars[rand.nextInt(chars.length)]).join();
  }
}
