import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import 'book.dart';

/// Thrown when the user has no active trial, subscription or purchase.
class NotEntitledException implements Exception {
  const NotEntitledException();
  @override
  String toString() => 'Subscribe or purchase this book to continue.';
}

/// Fetches book metadata and — for entitled users — decrypts protected
/// content **in memory only**. Nothing decrypted is ever written to disk,
/// and no file path or share intent is ever exposed to the UI.
class LibraryRepository {
  LibraryRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<List<Book>> watchBooks() => _db
      .collection('books')
      .where('published', isEqualTo: true)
      .orderBy('order')
      .snapshots()
      .map((q) => q.docs.map(Book.fromDoc).toList());

  Stream<Book?> watchBook(String id) => _db.doc('books/$id').snapshots().map((d) => d.exists ? Book.fromDoc(d) : null);

  Future<BookAccess> access(String bookId) async {
    try {
      final res = await _functions.httpsCallable('getBookAccess').call<Map<String, dynamic>>({'bookId': bookId});
      final d = res.data;
      return BookAccess(
        key: base64Decode(d['key'] as String),
        pdfUrl: d['pdfUrl'] as String?,
        transcriptUrl: d['transcriptUrl'] as String?,
        chapters: [
          for (final c in (d['chapters'] as List? ?? const []))
            AudioChapter(title: (c as Map)['title'] as String, url: c['url'] as String),
        ],
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') throw const NotEntitledException();
      rethrow;
    }
  }

  /// File layout produced by `functions/scripts/encrypt-book.ts`:
  /// `[12-byte nonce][ciphertext][16-byte GCM tag]`.
  Future<Uint8List> decryptFrom(String url, List<int> key) async => decryptBlob(await _download(url), key);

  /// Authenticated decryption: any tampering with the file fails the GCM tag.
  static Future<Uint8List> decryptBlob(Uint8List bytes, List<int> key) async {
    if (bytes.length < 28) throw const FormatException('Corrupt content');
    final box = SecretBox(
      bytes.sublist(12, bytes.length - 16),
      nonce: bytes.sublist(0, 12),
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  }

  Future<List<TranscriptLine>> transcript(BookAccess access) async {
    if (access.transcriptUrl == null) return const [];
    final raw = await decryptFrom(access.transcriptUrl!, access.key);
    final list = jsonDecode(utf8.decode(raw)) as List;
    return [for (final l in list) TranscriptLine.fromMap(Map<String, dynamic>.from(l as Map))];
  }

  Future<Uint8List> _download(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Download failed (${res.statusCode})');
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  /// Rewrites a passage in the chosen narrator persona (premium AI mode).
  Future<String> narrate({required String bookId, required String passage, required String persona}) async {
    final res = await _functions
        .httpsCallable('narratePassage', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
        .call<Map<String, dynamic>>({'bookId': bookId, 'passage': passage, 'persona': persona});
    return res.data['script'] as String;
  }
}

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider)),
);

final booksProvider = StreamProvider<List<Book>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(libraryRepositoryProvider).watchBooks();
});

final bookProvider = StreamProvider.family<Book?, String>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchBook(id),
);
