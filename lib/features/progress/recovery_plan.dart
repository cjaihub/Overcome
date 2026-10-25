import 'package:flutter/material.dart';

import '../../core/theme/brand.dart';

/// Recovery plan produced (or matched) by the AI agent. Brand fields are
/// tokens validated server side against `functions/src/brand.ts`.
class RecoveryPlan {
  const RecoveryPlan({
    required this.title,
    required this.summary,
    required this.accent,
    required this.icon,
    required this.phases,
    required this.forms,
    required this.affirmations,
    this.templateId,
  });

  final String title;
  final String summary;
  final String accent;
  final String icon;
  final List<PlanPhase> phases;
  final List<FormTemplate> forms;
  final List<String> affirmations;
  final String? templateId;

  Color get color => Brand.accent(accent);
  IconData get iconData => Brand.icon(icon);

  factory RecoveryPlan.fromMap(Map<String, dynamic> m) => RecoveryPlan(
    title: m['title'] as String? ?? 'Your plan',
    summary: m['summary'] as String? ?? '',
    accent: m['accent'] as String? ?? 'aurora',
    icon: m['icon'] as String? ?? 'spark',
    phases: [
      for (final p in (m['phases'] as List? ?? const [])) PlanPhase.fromMap(Map<String, dynamic>.from(p as Map)),
    ],
    forms: [
      for (final f in (m['forms'] as List? ?? const [])) FormTemplate.fromMap(Map<String, dynamic>.from(f as Map)),
    ],
    affirmations: (m['affirmations'] as List?)?.cast<String>() ?? const [],
    templateId: m['templateId'] as String?,
  );
}

class PlanPhase {
  const PlanPhase({required this.title, required this.weeks, required this.focus, required this.actions});
  final String title;
  final int weeks;
  final String focus;
  final List<String> actions;

  factory PlanPhase.fromMap(Map<String, dynamic> m) => PlanPhase(
    title: m['title'] as String? ?? '',
    weeks: (m['weeks'] as num?)?.toInt() ?? 1,
    focus: m['focus'] as String? ?? '',
    actions: (m['actions'] as List?)?.cast<String>() ?? const [],
  );
}

enum FieldType { scale, text, choice, multi, boolean, number }

class FormFieldSpec {
  const FormFieldSpec({
    required this.id,
    required this.label,
    required this.type,
    this.options = const [],
    this.min = 0,
    this.max = 10,
    this.hint,
    this.required = true,
  });

  final String id;
  final String label;
  final FieldType type;
  final List<String> options;
  final num min;
  final num max;
  final String? hint;
  final bool required;

  factory FormFieldSpec.fromMap(Map<String, dynamic> m) => FormFieldSpec(
    id: m['id'] as String,
    label: m['label'] as String? ?? '',
    type: FieldType.values.asNameMap()[m['type']] ?? FieldType.text,
    options: (m['options'] as List?)?.cast<String>() ?? const [],
    min: m['min'] as num? ?? 0,
    max: m['max'] as num? ?? 10,
    hint: m['hint'] as String?,
    required: m['required'] as bool? ?? true,
  );
}

/// A dynamic check-in form (daily check-in, urge log, weekly reflection …).
class FormTemplate {
  const FormTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.frequency,
    required this.fields,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final String accent;

  /// daily | weekly | on_urge
  final String frequency;
  final List<FormFieldSpec> fields;

  Color get color => Brand.accent(accent);
  IconData get iconData => Brand.icon(icon);

  factory FormTemplate.fromMap(Map<String, dynamic> m) => FormTemplate(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    description: m['description'] as String? ?? '',
    icon: m['icon'] as String? ?? 'journal',
    accent: m['accent'] as String? ?? 'aurora',
    frequency: m['frequency'] as String? ?? 'daily',
    fields: [
      for (final f in (m['fields'] as List? ?? const [])) FormFieldSpec.fromMap(Map<String, dynamic>.from(f as Map)),
    ],
  );
}
