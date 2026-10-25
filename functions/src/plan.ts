import { z } from "zod";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { ACCENTS, BRAND_GUIDE, FIELD_TYPES, FREQUENCIES, ICONS } from "./brand";
import { ANTHROPIC_API_KEY, generateJson } from "./ai";
import { FieldValue, db } from "./core";

// ---------- Schema (shared by Claude structured output and validation) ----------

const Field = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*$/),
  label: z.string().max(90),
  type: z.enum(FIELD_TYPES),
  options: z.array(z.string()),
  min: z.number(),
  max: z.number(),
  hint: z.string().max(140),
  required: z.boolean(),
});

const Form = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*$/),
  title: z.string().max(40),
  description: z.string().max(140),
  icon: z.enum(ICONS),
  accent: z.enum(ACCENTS),
  frequency: z.enum(FREQUENCIES),
  fields: z.array(Field).min(2).max(8),
});

export const Plan = z.object({
  title: z.string().max(40),
  summary: z.string().max(400),
  icon: z.enum(ICONS),
  accent: z.enum(ACCENTS),
  phases: z
    .array(z.object({ title: z.string().max(32), weeks: z.number().int().min(1).max(8), focus: z.string().max(160), actions: z.array(z.string().max(120)).min(2).max(5) }))
    .min(3)
    .max(5),
  forms: z.array(Form).min(2).max(4),
  affirmations: z.array(z.string().max(120)).min(5).max(10),
});
export type Plan = z.infer<typeof Plan>;

const UNSUPPORTED = new Set(["$schema", "minLength", "maxLength", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minItems", "maxItems", "pattern"]);

/** JSON Schema for structured outputs: drops keywords the API doesn't accept
 * (limits are enforced afterwards by [parsePlan]) and closes every object. */
function apiSchema(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(apiSchema);
  if (!node || typeof node !== "object") return node;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(node)) if (!UNSUPPORTED.has(k)) out[k] = apiSchema(v);
  if (out.type === "object") out.additionalProperties = false;
  return out;
}

export const planJsonSchema = apiSchema(z.toJSONSchema(Plan)) as Record<string, unknown>;

/** Validates a plan, trimming over-long strings/arrays instead of failing. */
export function parsePlan(raw: unknown): Plan {
  const data = structuredClone(raw) as Record<string, unknown>;
  for (let attempt = 0; attempt < 5; attempt++) {
    const r = Plan.safeParse(data);
    if (r.success) return r.data;
    const fixable = r.error.issues.filter((i) => i.code === "too_big" && (i.origin === "string" || i.origin === "array"));
    if (fixable.length !== r.error.issues.length) throw r.error;
    for (const issue of fixable) {
      const key = issue.path[issue.path.length - 1] as string | number;
      const parent = issue.path.slice(0, -1).reduce<any>((o, k) => o?.[k as string | number], data);
      const max = Number((issue as { maximum: number | bigint }).maximum);
      if (parent && parent[key] != null) parent[key] = parent[key].slice(0, max);
    }
  }
  return Plan.parse(data);
}

// ---------- Profile → template signature ----------

export interface Profile {
  displayName?: string;
  identity?: string;
  role?: string;
  habits?: string[];
  dailyHours?: number;
  peakTimes?: string[];
  triggers?: string[];
  goals?: string[];
  coachStyle?: string;
  dailyMinutesGoal?: number;
  severityBand?: string;
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");

/** Templates are reusable across users who share this signature. */
export function signatureOf(p: Profile): string {
  return [slug(p.habits?.[0] ?? "general"), p.severityBand ?? "moderate", p.coachStyle ?? "teacher"].join("|");
}

/** Light, deterministic personalisation of a shared template. */
export function personalise(plan: Plan, p: Profile): Plan {
  const name = (p.displayName ?? "").split(" ")[0] || "you";
  const fill = (s: string) => s.replace(/\{name\}/g, name).replace(/\{identity\}/g, p.identity ?? "");
  return {
    ...plan,
    summary: fill(plan.summary),
    affirmations: [...(p.identity ? [p.identity] : []), ...plan.affirmations.map(fill)].slice(0, 10),
  };
}

// ---------- The agent ----------

type StepState = "running" | "done" | "skipped";
interface Step { label: string; state: StepState; detail?: string }

const SYSTEM = `You are Overcome's recovery-plan designer. You create structured, evidence-informed
programmes that help people reduce compulsive digital habits and redirect attention
to what matters to them. You are not a clinician: never diagnose, never mention
medication, and include a gentle "reach out to a professional or someone you trust"
action when severity is high. Write plan content that works for many people with
the same profile — use {name} and {identity} placeholders instead of personal details.

${BRAND_GUIDE}

Forms: always include one daily check-in whose FIRST field is a 0–10 "scale"
wellbeing question, and one "on_urge" form (id "urge_log") for logging urges
in the moment (intensity scale, trigger choice, what helped). For fields that
don't use options, return an empty array; for non-numeric fields set min 0 and max 10.`;

/**
 * Runs when the app queues `users/{uid}/agentRuns/{runId}`. Streams each
 * step back to the run document so the onboarding screen can show the agent
 * working live: profile → search existing templates → reuse or generate on
 * brand → validate → assign.
 */
export const runPlanAgent = onDocumentCreated(
  { document: "users/{uid}/agentRuns/{runId}", secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 300, memory: "512MiB" },
  async (event) => {
    const { uid } = event.params;
    const runRef = event.data!.ref;
    const steps: Step[] = [];

    const push = async (label: string, detail?: string) => {
      steps.push({ label, state: "running", detail });
      await runRef.update({ status: "running", steps });
    };
    const finish = async (detail?: string, state: StepState = "done") => {
      const s = steps[steps.length - 1];
      s.state = state;
      if (detail) s.detail = detail;
      await runRef.update({ steps });
    };

    try {
      await push("Reading your answers");
      const user = await db.doc(`users/${uid}`).get();
      const profile = (user.get("profile") ?? {}) as Profile;
      const signature = signatureOf(profile);
      await finish(`${profile.habits?.join(", ") || "general"} · ${profile.severityBand ?? "moderate"} load`);

      await push("Searching our library of proven programmes");
      const matches = await db.collection("templates").where("signature", "==", signature).limit(10).get();
      // Prefer clinician-approved templates, then the most used generated one.
      const best = matches.docs
        .filter((d) => d.get("status") !== "rejected")
        .sort((a, b) => Number(b.get("status") === "approved") - Number(a.get("status") === "approved") || (b.get("uses") ?? 0) - (a.get("uses") ?? 0))[0];

      let plan: Plan;
      let templateId: string;
      let source: "template" | "generated";

      if (best) {
        await finish(`Found “${best.get("plan.title")}”`);
        await push("Tailoring it to your goals and identity");
        plan = parsePlan(best.get("plan"));
        templateId = best.id;
        source = "template";
        await best.ref.update({ uses: FieldValue.increment(1) });
        await finish();
      } else {
        await finish("No exact match — designing a new one", "skipped");
        await push("Designing a new plan with your coach", `Coach style: ${profile.coachStyle ?? "teacher"}`);
        const generated = await generateJson<unknown>({
          system: SYSTEM,
          schema: planJsonSchema,
          prompt: `Design a recovery programme for this profile (role: ${profile.role ?? "individual"}).

Habits: ${profile.habits?.join(", ")}
Daily non-essential screen time: ${profile.dailyHours} hours
Hardest times: ${profile.peakTimes?.join(", ")}
Triggers: ${profile.triggers?.join(", ")}
Goals for reclaimed time: ${profile.goals?.join(", ")}
Daily commitment: ${profile.dailyMinutesGoal} minutes reclaimed
Severity band: ${profile.severityBand}
Coach voice: ${profile.coachStyle}`,
        });
        await finish();

        await push("Checking brand, tone and safety");
        plan = parsePlan(generated);
        const ref = await db.collection("templates").add({
          signature,
          status: "generated", // an admin can promote to "approved" or "rejected"
          plan,
          uses: 1,
          model: "claude",
          createdAt: FieldValue.serverTimestamp(),
        });
        templateId = ref.id;
        source = "generated";
        await finish("Saved for reuse");
      }

      await push("Assigning your plan");
      await db.doc(`users/${uid}/plan/current`).set({
        ...personalise(plan, profile),
        templateId,
        source,
        assignedAt: FieldValue.serverTimestamp(),
      });
      await finish();
      await runRef.update({ status: "done", source, templateId, planTitle: plan.title });
    } catch (e) {
      logger.error("Plan agent failed", e);
      await runRef.update({
        status: "error",
        steps,
        error: "We couldn't finish your plan. Your answers are saved — please retry.",
      });
    }
  },
);
