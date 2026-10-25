/**
 * Brand tokens shared with the app (lib/core/theme/brand.dart). The plan
 * generator may only reference these, so every AI-generated template renders
 * in the Overcome palette, typography and iconography.
 */
export const ACCENTS = ["aurora", "iris", "ember", "bloom", "success"] as const;
export const ICONS = [
  "spark", "mind", "heart", "shield", "sun", "moon", "walk", "book",
  "journal", "target", "phone_off", "people", "breath", "trophy", "clock",
] as const;
export const FIELD_TYPES = ["scale", "text", "choice", "multi", "boolean", "number"] as const;
export const FREQUENCIES = ["daily", "weekly", "on_urge"] as const;

export const BRAND_GUIDE = `
Brand: Overcome — a premium, calm, corporate-grade recovery companion.
Voice: warm, direct, non-judgemental, evidence-informed (CBT, habit science,
implementation intentions, urge surfing). Never shame. Never diagnose.
Short sentences. Second person. Concrete actions over abstractions.
Palette tokens (choose by meaning):
  aurora  = clarity, recovery (primary)
  iris    = reflection, depth
  ember   = energy, urges, momentum
  bloom   = self-compassion, relationships
  success = wins, milestones
Typography is handled by the app (Sora display, Inter body): keep titles
under 32 characters and descriptions under 120 characters.
`.trim();
