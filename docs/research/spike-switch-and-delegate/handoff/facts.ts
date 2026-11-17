// Invented projects: the facts that the seed conversation spreads over its turns, and the six recall questions per project.
export type FactSet = {
  id: string;
  turns: { text?: string; paste?: { title: string; fact?: string; seed: number }; }[];
  /** `where` says in which part of the handoff the answer lives, by construction: first message, a pasted spec, a late message, or the middle (left out). */
  questions: { key: string; where: 'included' | 'omitted'; source: string; ask: string; right: RegExp[] }[];
};

// a small seeded generator, so that the filler is the same every run
const rng = (seed: number) => () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32);
const nouns = ['gauge', 'technician', 'schedule', 'record', 'export', 'dashboard', 'operator', 'report', 'queue', 'window', 'pier', 'checklist', 'sensor', 'archive', 'form', 'registry', 'notice', 'shift', 'handover', 'template'];
const verbs = ['is stored', 'must be reviewed', 'is rendered', 'is validated', 'may be exported', 'is signed off', 'is shown', 'is rotated', 'must be logged', 'is merged'];
const quals = ['before the end of the shift', 'in the order it was created', 'without blocking the operator', 'when the user opens the screen', 'as plain text', 'using the shared template', 'once per working day', 'under the same reference', 'and the previous value is kept', 'unless the operator cancels it'];

/** About `size` characters of plausible spec prose with `fact` as one sentence about 55% of the way in. */
export function filler(title: string, size: number, seed: number, fact?: string) {
  const r = rng(seed);
  const pick = <T,>(a: T[]) => a[Math.floor(r() * a.length)]!;
  const sentence = () => `The ${pick(nouns)} ${pick(verbs)} ${pick(quals)}, and the ${pick(nouns)} ${pick(verbs)} ${pick(quals)}.`;
  const paragraphs: string[] = [];
  let n = 0;
  let placed = fact === undefined;
  let clause = 1;
  while (n < size) {
    if (!placed && n > size * 0.55) {
      paragraphs.push(`${title}.${clause++}  ${fact}`);
      placed = true;
    } else {
      paragraphs.push(`${title}.${clause++}  ${Array.from({ length: 3 + Math.floor(r() * 3) }, sentence).join(' ')}`);
    }
    n = paragraphs.join('\n\n').length;
  }
  return `Section ${title}: Operating rules\n\n${paragraphs.join('\n\n')}`;
}

export const SET1: FactSet = {
  id: 'quillfinch',
  turns: [
    { text: 'I am starting a small project called Quillfinch. It is a tool for the harbour authority of Port Veyra that schedules the calibration of tide gauges. The project owner is Odalys Prewitt. Reply with one short sentence.' },
    { text: 'Decision: we store everything in SQLite, in a single file. We looked at Postgres and rejected it, because the laptops that the technicians carry out on the piers have no network. Acknowledge in one short sentence.' },
    { paste: { title: '3', seed: 31, fact: 'Implementers note: the calibration interval for gauge model TG-440 is 19 days, and it cannot be set per harbour.' } },
    { paste: { title: '4', seed: 41, fact: 'An alert is raised when the drift of a gauge passes 7.3 mm over a single interval.' } },
    { paste: { title: '5', seed: 51, fact: 'The on-call rotation changes every Monday at 06:40 local time.' } },
    { paste: { title: '6', seed: 61, fact: 'The nightly export job is named kelp-sync-0415 and writes one file per harbour.' } },
    { text: 'Small thing: the demo for the harbour board runs on port 8421. Reply with one short sentence.' },
    { text: 'We agreed that the first release is tagged v0.3.7-tern. Reply with one short sentence.' },
  ],
  questions: [
    { key: 'A', where: 'included', source: 'first message', ask: 'Who is the project owner of Quillfinch?', right: [/Odalys/i, /Prewitt/i] },
    { key: 'F', where: 'included', source: 'newest pasted spec (turn 6)', ask: 'What is the name of the nightly export job?', right: [/kelp-sync-0415/i] },
    { key: 'G', where: 'included', source: 'last message', ask: 'What is the tag of the first release?', right: [/v0\.3\.7-tern/i] },
    { key: 'B', where: 'omitted', source: 'turn 2 (decision and rejected option)', ask: 'Which database option did we reject, and why?', right: [/postgres/i, /(network|offline|pier)/i] },
    { key: 'C', where: 'omitted', source: 'pasted spec of turn 3', ask: 'What is the calibration interval for gauge model TG-440?', right: [/19\s*days?/i] },
    { key: 'D', where: 'omitted', source: 'pasted spec of turn 4', ask: 'At what drift does a gauge raise an alert?', right: [/7\.3\s*mm/i] },
  ],
};

export const SET2: FactSet = {
  id: 'brambleglass',
  turns: [
    { text: 'I am starting a small project called Brambleglass. It is a booking app for the beekeepers of the Hollin Fen cooperative, to reserve shared extractors. The project owner is Tobias Reinholt. Reply with one short sentence.' },
    { text: 'Decision: the API is plain REST with JSON. We looked at GraphQL and rejected it, because the cooperative volunteers who maintain it only know REST. Acknowledge in one short sentence.' },
    { paste: { title: '3', seed: 32, fact: 'Implementers note: a hive inspection form holds at most 23 frames per box, and the form refuses more.' } },
    { paste: { title: '4', seed: 42, fact: 'The swarm alert radius is 4.6 km around the reporting apiary.' } },
    { paste: { title: '5', seed: 52, fact: 'Extractor bookings are released for the week every Sunday at 21:15 local time.' } },
    { paste: { title: '6', seed: 62, fact: 'The weekly rollup job is named mead-rollup-2310 and emails one summary per member.' } },
    { text: 'Small thing: the cooperative newsletter goes out on port 7733 of the test mailer. Reply with one short sentence.' },
    { text: 'We agreed that the first release is tagged v1.2.0-drone. Reply with one short sentence.' },
  ],
  questions: [
    { key: 'A', where: 'included', source: 'first message', ask: 'Who is the project owner of Brambleglass?', right: [/Tobias/i, /Reinholt/i] },
    { key: 'F', where: 'included', source: 'newest pasted spec (turn 6)', ask: 'What is the name of the weekly rollup job?', right: [/mead-rollup-2310/i] },
    { key: 'G', where: 'included', source: 'last message', ask: 'What is the tag of the first release?', right: [/v1\.2\.0-drone/i] },
    { key: 'B', where: 'omitted', source: 'turn 2 (decision and rejected option)', ask: 'Which API style did we reject, and why?', right: [/graphql/i, /(volunteer|only know|know REST|REST)/i] },
    { key: 'C', where: 'omitted', source: 'pasted spec of turn 3', ask: 'How many frames does a hive inspection form hold at most per box?', right: [/\b23\b/] },
    { key: 'D', where: 'omitted', source: 'pasted spec of turn 4', ask: 'What is the radius of the swarm alert?', right: [/4\.6\s*km/i] },
  ],
};

export const pasteText = (p: { title: string; fact?: string; seed: number }) =>
  `Here is section ${p.title} of the spec. Reply with one short sentence: only the title of the section, nothing else.\n\n\`\`\`\`pasted\n${filler(p.title, 9400, p.seed, p.fact)}\n\`\`\`\``;
