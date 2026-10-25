/**
 * Seeds curated, approved templates so the onboarding agent can reuse them
 * instead of generating. `npm run seed`
 */
import { FieldValue, db } from "../src/core";
import { type Plan, parsePlan } from "../src/plan";

const dailyCheckIn = {
  id: "daily_check_in",
  title: "Daily check-in",
  description: "Sixty seconds to notice how today went.",
  icon: "sun",
  accent: "aurora",
  frequency: "daily",
  fields: [
    { id: "wellbeing", label: "How are you feeling overall?", type: "scale", options: [], min: 0, max: 10, hint: "0 = awful, 10 = great", required: true },
    { id: "kept_commitment", label: "Did you keep today's commitment?", type: "boolean", options: [], min: 0, max: 10, hint: "", required: true },
    { id: "hardest_moment", label: "When was it hardest?", type: "choice", options: ["Morning", "Midday", "Evening", "Late night", "It was easy"], min: 0, max: 10, hint: "", required: true },
    { id: "win", label: "One win from today", type: "text", options: [], min: 0, max: 10, hint: "Big or small — it counts.", required: false },
  ],
} as const;

const urgeLog = {
  id: "urge_log",
  title: "Urge log",
  description: "Catch the urge, name it, ride it out.",
  icon: "breath",
  accent: "ember",
  frequency: "on_urge",
  fields: [
    { id: "intensity", label: "How strong is the urge?", type: "scale", options: [], min: 0, max: 10, hint: "Notice it without acting on it.", required: true },
    { id: "trigger", label: "What set it off?", type: "choice", options: ["Boredom", "Stress", "Loneliness", "Notification", "Tiredness", "Other"], min: 0, max: 10, hint: "", required: true },
    { id: "helped", label: "What are you doing instead?", type: "multi", options: ["Breathing", "Walk", "Water", "Called someone", "Read a page", "Phone in another room"], min: 0, max: 10, hint: "", required: false },
  ],
} as const;

function plan(habit: string): Plan {
  return parsePlan({
    title: `Reclaim focus from ${habit.toLowerCase()}`,
    summary:
      "A 9-week programme that starts with awareness, builds friction around the habit and replaces it with what matters to {name}.",
    icon: "target",
    accent: "aurora",
    phases: [
      { title: "Notice", weeks: 2, focus: "See your patterns clearly without judging them.", actions: ["Log every urge for 7 days", "Turn off all non-human notifications", "Check in each evening"] },
      { title: "Add friction", weeks: 3, focus: "Make the habit harder and the alternatives easier.", actions: ["Move tempting apps off the home screen", "Phone charges outside the bedroom", "Use a 10-minute delay before opening apps"] },
      { title: "Replace", weeks: 2, focus: "Fill reclaimed time with your goals.", actions: ["Schedule your commitment minutes daily", "Pick one book from the library", "Tell someone you trust about your plan"] },
      { title: "Sustain", weeks: 2, focus: "Protect your progress and plan for setbacks.", actions: ["Write your relapse plan", "Review your weekly trend", "Celebrate a milestone"] },
    ],
    forms: [dailyCheckIn, urgeLog],
    affirmations: [
      "Urges peak and pass. I can wait ten minutes.",
      "My attention is mine to give.",
      "Progress, not perfection.",
      "Every check-in is a vote for who I'm becoming.",
      "I choose presence over the scroll.",
    ],
  });
}

async function main() {
  const habits = ["Social media", "Short videos", "Gaming", "News scrolling"];
  const batch = db.batch();
  for (const habit of habits) {
    for (const band of ["mild", "moderate", "high"]) {
      for (const coach of ["storyteller", "teacher", "motivator"]) {
        const signature = [habit.toLowerCase().replace(/[^a-z0-9]+/g, "_"), band, coach].join("|");
        batch.set(db.doc(`templates/curated_${signature.replace(/\|/g, "__")}`), {
          signature,
          status: "approved",
          plan: plan(habit),
          uses: 0,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
  }
  await batch.commit();
  console.log("Seeded curated templates");
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
