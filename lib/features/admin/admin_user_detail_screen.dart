import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import 'admin_repository.dart';

/// Per-user analytics: usage counters, recovery trend and an activity log.
class AdminUserDetailScreen extends ConsumerWidget {
  const AdminUserDetailScreen({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(adminRepositoryProvider);
    final text = Theme.of(context).textTheme;
    return StreamBuilder<AdminUserRow?>(
      stream: repo.watchUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final p = u.profile;
        return Scaffold(
          appBar: AppBar(title: Text(u.name)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.phone, style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text('Role: ${p['role'] ?? '—'} · Coach: ${p['coachStyle'] ?? '—'}'),
                    Text('Habits: ${(p['habits'] as List?)?.join(', ') ?? '—'}'),
                    Text('Severity: ${p['severity'] ?? '—'} (${p['severityBand'] ?? ''})'),
                    Text('Entitlement: ${_entitlement(u.data['entitlement'] as Map?)}'),
                  ],
                ),
              ),
              const SectionTitle('Usage'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in const [
                    'app_open',
                    'session_seconds',
                    'pdf_page_view',
                    'book_open',
                    'audio_play',
                    'audio_complete',
                    'ai_narration',
                    'form_submit',
                    'capture_attempt',
                  ])
                    Chip(label: Text('${k.replaceAll('_', ' ')}: ${u.stat(k)}')),
                ],
              ),
              const SectionTitle('Recovery trend'),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: repo.watchCheckIns(uid),
                builder: (context, s) {
                  final pts = [
                    for (final c in (s.data ?? const []).reversed)
                      if (c['mood'] is num) (c['mood'] as num).toDouble(),
                  ];
                  return GlassCard(
                    child: pts.isEmpty
                        ? const Text('No scored check-ins yet')
                        : TrendChart(points: pts, color: Brand.iris),
                  );
                },
              ),
              const SectionTitle('Activity log'),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: repo.watchEvents(uid),
                builder: (context, s) => Column(
                  children: [
                    for (final e in s.data ?? const <Map<String, dynamic>>[])
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.circle, size: 8, color: Brand.aurora),
                        title: Text((e['type'] as String? ?? '').replaceAll('_', ' ')),
                        subtitle: Text(
                          (e['props'] as Map?)?.entries.map((x) => '${x.key}: ${x.value}').join(' · ') ?? '',
                        ),
                        trailing: Text(
                          (e['at'] as Timestamp?) == null
                              ? ''
                              : DateFormat('d MMM HH:mm').format((e['at'] as Timestamp).toDate()),
                          style: text.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _entitlement(Map? e) {
    if (e == null) return 'none';
    String fmt(Object? t) => t is Timestamp ? DateFormat('d MMM y').format(t.toDate()) : '—';
    return 'trial → ${fmt(e['trialEndsAt'])}, premium → ${fmt(e['premiumUntil'])}, books: ${(e['ownedBooks'] as List?)?.length ?? 0}';
  }
}
