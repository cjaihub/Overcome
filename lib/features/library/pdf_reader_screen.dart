import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/security/screen_security.dart';
import '../../core/security/secure_content_guard.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import 'book_detail_screen.dart';
import 'library_repository.dart';

/// Secure PDF reader. The encrypted file is downloaded and decrypted in
/// memory; the viewer offers no share, print, save, copy or open-in action,
/// and the window is capture-protected.
class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  PdfControllerPinch? _controller;
  int _page = 1;
  int _pages = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final access = await resolveAccess(context, ref, widget.bookId);
    if (access == null || access.pdfUrl == null) return;
    try {
      final bytes = await ref.read(libraryRepositoryProvider).decryptFrom(access.pdfUrl!, access.key);
      if (!mounted) return;
      setState(() => _controller = PdfControllerPinch(document: PdfDocument.openData(bytes)));
      ref.read(analyticsProvider).log(AppEvent.bookOpen, {'bookId': widget.bookId, 'mode': 'pdf'});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open this book. $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    ScreenSecurity.instance.purgeRendererCache();
    super.dispose();
  }

  void _onCapture(String kind) =>
      ref.read(analyticsProvider).log(AppEvent.captureAttempt, {'bookId': widget.bookId, 'kind': kind});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber ?? '';
    final mark = '${user?.uid.substring(0, 8)} ${phone.length > 4 ? '•••${phone.substring(phone.length - 4)}' : ''}';
    final c = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(_pages == 0 ? 'Reading' : 'Page $_page of $_pages'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.shield_rounded, color: Brand.aurora),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : c == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Decrypting securely…')],
              ),
            )
          : SecureContentGuard(
              watermark: mark,
              onCaptureAttempt: _onCapture,
              child: PdfViewPinch(
                controller: c,
                padding: 12,
                onDocumentLoaded: (doc) {
                  ScreenSecurity.instance.purgeRendererCache();
                  setState(() => _pages = doc.pagesCount);
                },
                onPageChanged: (p) {
                  setState(() => _page = p);
                  ref.read(analyticsProvider).log(AppEvent.pdfPageView, {'bookId': widget.bookId, 'page': p});
                },
              ),
            ),
      bottomNavigationBar: _pages == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _page > 1
                          ? () => c?.previousPage(duration: Brand.motion, curve: Curves.easeOut)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Slider(
                        value: _page.toDouble(),
                        min: 1,
                        max: _pages.toDouble(),
                        onChanged: (v) => setState(() => _page = v.round()),
                        onChangeEnd: (v) => c?.jumpToPage(v.round()),
                      ),
                    ),
                    IconButton(
                      onPressed: _page < _pages
                          ? () => c?.nextPage(duration: Brand.motion, curve: Curves.easeOut)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
