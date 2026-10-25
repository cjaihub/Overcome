import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/brand.dart';

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.category,
    required this.coverUrl,
    required this.accent,
    required this.pages,
    required this.audioMinutes,
    required this.hasPdf,
    required this.hasAudio,
    required this.featured,
    this.productId,
    this.rating = 0,
  });

  final String id;
  final String title;
  final String author;
  final String description;
  final String category;
  final String coverUrl;
  final String accent;
  final int pages;
  final int audioMinutes;
  final bool hasPdf;
  final bool hasAudio;
  final bool featured;

  /// Store product id when the book can also be bought on its own.
  final String? productId;
  final double rating;

  Color get color => Brand.accent(accent);

  factory Book.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Book(
      id: d.id,
      title: m['title'] as String? ?? '',
      author: m['author'] as String? ?? '',
      description: m['description'] as String? ?? '',
      category: m['category'] as String? ?? 'General',
      coverUrl: m['coverUrl'] as String? ?? '',
      accent: m['accent'] as String? ?? 'aurora',
      pages: (m['pages'] as num?)?.toInt() ?? 0,
      audioMinutes: (m['audioMinutes'] as num?)?.toInt() ?? 0,
      hasPdf: m['hasPdf'] as bool? ?? true,
      hasAudio: m['hasAudio'] as bool? ?? false,
      featured: m['featured'] as bool? ?? false,
      productId: m['productId'] as String?,
      rating: (m['rating'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Time-aligned text used for read-along highlighting and AI narration.
class TranscriptLine {
  const TranscriptLine({required this.text, required this.startMs, required this.endMs, required this.chapter});
  final String text;
  final int startMs;
  final int endMs;
  final int chapter;

  factory TranscriptLine.fromMap(Map<String, dynamic> m) => TranscriptLine(
    text: m['text'] as String,
    startMs: (m['start'] as num).toInt(),
    endMs: (m['end'] as num).toInt(),
    chapter: (m['chapter'] as num?)?.toInt() ?? 0,
  );
}

class AudioChapter {
  const AudioChapter({required this.title, required this.url});
  final String title;
  final String url;
}

/// Short-lived access grant from the `getBookAccess` function.
class BookAccess {
  const BookAccess({required this.key, required this.pdfUrl, required this.transcriptUrl, required this.chapters});
  final List<int> key;
  final String? pdfUrl;
  final String? transcriptUrl;
  final List<AudioChapter> chapters;
}
