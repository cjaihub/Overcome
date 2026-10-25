import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_infographics.dart';
import 'progress_repository.dart';
import 'recovery_plan.dart';

/// Renders any AI-generated or curated [FormTemplate] with brand styling,
/// one question at a time, with a live infographic reflecting the answer.
class TemplateFormScreen extends ConsumerStatefulWidget {
  const TemplateFormScreen({super.key, required this.formId});
  final String formId;

  @override
  ConsumerState<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends ConsumerState<TemplateFormScreen> {
  final _answers = <String, dynamic>{};
  int _i = 0;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planProvider).value;
    final form = plan?.forms.where((f) => f.id == widget.formId).firstOrNull;
    if (form == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final field = form.fields[_i];
    final last = _i == form.fields.length - 1;
    final answered = _answers[field.id] != null && _answers[field.id].toString().isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(form.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (_i + 1) / form.fields.length),
            duration: Brand.motion,
            builder: (_, v, _) =>
                LinearProgressIndicator(value: v, color: form.color, backgroundColor: Colors.transparent),
          ),
        ),
      ),
      body: AuroraBackground(
        accent: form.color,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: Brand.motion,
                  child: ListView(
                    key: ValueKey(_i),
                    padding: const EdgeInsets.all(24),
                    children: [
                      ScreenHeader(
                        visual: _visualFor(form, field),
                        title: field.label,
                        description:
                            field.hint ?? (_i == 0 ? form.description : 'Question ${_i + 1} of ${form.fields.length}'),
                      ),
                      const SizedBox(height: 28),
                      _input(field, form.color).animate().fadeIn(delay: 250.ms),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    if (_i > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: IconButton.filledTonal(
                          onPressed: () => setState(() => _i--),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Expanded(
                      child: GradientButton(
                        label: last ? 'Save check-in' : 'Next',
                        loading: _saving,
                        gradient: Brand.gradientFor(form.accent),
                        onPressed: (answered || !field.required)
                            ? () => last ? _submit(form) : setState(() => _i++)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visualFor(FormTemplate form, FormFieldSpec field) {
    final v = _answers[field.id];
    return switch (field.type) {
      FieldType.scale || FieldType.number => RingGauge(
        progress: v is num ? (v - field.min) / (field.max - field.min) : 0,
        color: form.color,
        size: 130,
        center: AnimatedCounter(value: v is num ? v.toDouble() : 0, style: Theme.of(context).textTheme.displaySmall),
      ),
      FieldType.multi => BubbleCloud(items: (v as List?)?.cast<String>() ?? const [], height: 130),
      _ => AnimatedStepIcon(icon: form.iconData, color: form.color, motion: StepIconMotion.breathe),
    };
  }

  Widget _input(FormFieldSpec f, Color color) {
    void set(dynamic v) => setState(() => _answers[f.id] = v);
    final v = _answers[f.id];
    switch (f.type) {
      case FieldType.scale:
        return Column(
          children: [
            Slider(
              value: (v as num? ?? (f.min + f.max) / 2).toDouble(),
              min: f.min.toDouble(),
              max: f.max.toDouble(),
              divisions: (f.max - f.min).toInt(),
              activeColor: color,
              onChanged: (x) {
                HapticFeedback.selectionClick();
                set(x.round());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${f.min}', style: Theme.of(context).textTheme.labelMedium),
                Text('${f.max}', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ],
        );
      case FieldType.number:
        return TextFormField(
          initialValue: v?.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '${f.min} – ${f.max}'),
          onChanged: (s) => set(num.tryParse(s)),
        );
      case FieldType.text:
        return TextFormField(
          initialValue: v as String?,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Write freely — this is private'),
          onChanged: set,
        );
      case FieldType.boolean:
        return Row(
          children: [
            for (final (label, val) in const [('Yes', true), ('No', false)])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ChoiceChip(
                    label: Center(child: Text(label)),
                    selected: v == val,
                    onSelected: (_) => set(val),
                  ),
                ),
              ),
          ],
        );
      case FieldType.choice:
        return RadioGroup<String>(
          groupValue: v as String?,
          onChanged: set,
          child: Column(
            children: [for (final o in f.options) RadioListTile<String>(value: o, title: Text(o), activeColor: color)],
          ),
        );
      case FieldType.multi:
        final sel = (v as List?)?.cast<String>() ?? const <String>[];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final o in f.options)
              FilterChip(
                label: Text(o),
                selected: sel.contains(o),
                onSelected: (on) => set(on ? [...sel, o] : sel.where((s) => s != o).toList()),
              ),
          ],
        );
    }
  }

  Future<void> _submit(FormTemplate form) async {
    setState(() => _saving = true);
    try {
      await ref.read(progressRepositoryProvider).submit(form, _answers);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in saved. Well done.')));
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
