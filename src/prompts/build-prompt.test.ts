import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { parseCallerResult } from '../execution/caller-result.ts';
import { resolveSkills, solveSkills, type ResolvedSkills } from '../config/skills.ts';
import { buildPrompt } from './build-prompt.ts';
import { signatureOf } from './persona.ts';

const pr = { number: 7, headSha: 'a'.repeat(40) };
const task = (stage: AgentTask['stage'], context: Partial<AgentTask['context']> = {}, harness: AgentTask['harness'] = 'claude'): AgentTask => ({
  executionId: 'exec-1',
  repo: 'AshuLab/carrier',
  epic: 3,
  stage,
  profile: 'bot',
  harness,
  model: 'm',
  workspace: '/w',
  resultPath: '/r/exec-1.json',
  timeoutMs: null,
  context: { previousSummaries: [], ...(stage !== 'ship' && { pr }), ...context },
});

test('ship prompt', () => {
  expect(buildPrompt(task('ship'))).toMatchInlineSnapshot(`
    "You are the author of the final integration PR of epic #3 in AshuLab/carrier. Execution exec-1, stage ship.
    Nobody answers questions during this run: decide, and use needs_human when you cannot.
    Apply the repo's own rules (its docs, agent instructions and conventions) to choose and evaluate tests, CI and blockers. Do not assume commands from other repos.
    Invoke /ship for epic #3 and tell it to worktree this epic, whatever mode the repo's solve.md has: the epic must live in its own git worktree. Leave the final integration PR open.
    Never merge the final PR: a person tests it and decides the merge.
    The epic's design artifacts (spec, ADRs, glossary) must already be on the remote, on the epic branch or the base branch. Do not look for uncommitted files in other directories of this machine. If the epic refers to a spec or ADR that is not there, return needs_human naming what is missing.
    Before finishing, write exactly one JSON object to /r/exec-1.json. That path is also in the environment variable CARRIER_RESULT_PATH: write to "$CARRIER_RESULT_PATH" instead of retyping it, because a path with one segment missing is a result nobody reads. Repeat executionId, repo, epic and stage as given. Allowed outputs:
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "ship",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "completed",
      "pr": {
        "number": 1,
        "headSha": "0000000000000000000000000000000000000000"
      },
      "verification": {
        "ci": "passed",
        "evidence": "<one line: which verifications you ran and their result>"
      }
    }
    \`\`\`
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "ship",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "needs_human",
      "reason": "<why a person has to step in>"
    }
    \`\`\`
    Replace pr.number and pr.headSha with the real final PR and its current head (take the head from gh pr view --json headRefOid). A failing CI is not a completed result.
    verification.ci is "absent" when the repo has no CI; say so in evidence."
  `);
});

test('review prompt', () => {
  expect(buildPrompt(task('review', { round: 2 }))).toMatchInlineSnapshot(`
    "You are the reviewer of the final integration PR of epic #3 in AshuLab/carrier. Execution exec-1, stage review.
    Nobody answers questions during this run: decide, and use needs_human when you cannot.
    Apply the repo's own rules (its docs, agent instructions and conventions) to choose and evaluate tests, CI and blockers. Do not assume commands from other repos.
    Review PR #7, round 2. First confirm the PR head is aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; if it is not, return needs_human.
    Invoke /code-review against the epic's spec and tickets, checking that earlier findings were fixed and nothing regressed, then publish the findings with /code-post.
    Give every blocker you return a short stable id (for example "token-expiry"), so a later round can say whether it persists or was fixed.
    Findings that do not stop approval (what you would post as a nitpick or a suggestion) are observations: list them in "observations" of a completed result, each with a title, a link when you have one, and a short stable id by the same rule as blockers (reuse it when the finding persists; never reuse an id for a different finding). Leave the field out when there are none.
    Return changes_requested with the blockers if there are any. Return completed only if the review is conclusive, there are no blockers and the repo's verifications are confirmed on that same commit. If the review is inconclusive (missing context, cannot verify), return needs_human.
    Before finishing, write exactly one JSON object to /r/exec-1.json. That path is also in the environment variable CARRIER_RESULT_PATH: write to "$CARRIER_RESULT_PATH" instead of retyping it, because a path with one segment missing is a result nobody reads. Repeat executionId, repo, epic and stage as given. Allowed outputs:
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "review",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "completed",
      "pr": {
        "number": 7,
        "headSha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      },
      "verification": {
        "ci": "passed",
        "evidence": "<one line: which verifications you confirmed on this commit>"
      },
      "observations": [
        {
          "id": "<stable-id>",
          "title": "<non-blocking finding>",
          "url": "https://github.com/AshuLab/carrier/pull/7#discussion_r456"
        }
      ]
    }
    \`\`\`
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "review",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "changes_requested",
      "pr": {
        "number": 7,
        "headSha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      },
      "blockers": [
        {
          "id": "<stable-id>",
          "title": "<blocker>",
          "url": "https://github.com/AshuLab/carrier/pull/7#discussion_r123"
        }
      ],
      "resolved": [
        "<id of an earlier blocker that is now fixed>"
      ]
    }
    \`\`\`
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "review",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "needs_human",
      "reason": "<why a person has to step in>"
    }
    \`\`\`
    verification.ci is "absent" when the repo has no CI; say so in evidence."
  `);
});

test('fix prompt', () => {
  expect(buildPrompt(task('fix', { round: 1, blockers: [{ title: 'null deref', url: 'https://github.com/AshuLab/carrier/pull/7#r1' }, { title: 'no test' }] }))).toMatchInlineSnapshot(`
    "You are the author of the final integration PR of epic #3 in AshuLab/carrier. Execution exec-1, stage fix.
    Nobody answers questions during this run: decide, and use needs_human when you cannot.
    Apply the repo's own rules (its docs, agent instructions and conventions) to choose and evaluate tests, CI and blockers. Do not assume commands from other repos.
    Invoke /code-resolve on PR #7, answering every finding of the last review and fixing what applies.
    Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.
    Blockers of the last review:
    - null deref (https://github.com/AshuLab/carrier/pull/7#r1)
    - no test
    Before finishing, write exactly one JSON object to /r/exec-1.json. That path is also in the environment variable CARRIER_RESULT_PATH: write to "$CARRIER_RESULT_PATH" instead of retyping it, because a path with one segment missing is a result nobody reads. Repeat executionId, repo, epic and stage as given. Allowed outputs:
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "fix",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "completed",
      "pr": {
        "number": 7,
        "headSha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      },
      "verification": {
        "ci": "passed",
        "evidence": "<one line: which verifications you ran and their result>"
      }
    }
    \`\`\`
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "fix",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "needs_human",
      "reason": "<why a person has to step in>"
    }
    \`\`\`
    Replace pr.number and pr.headSha with the real final PR and its current head (take the head from gh pr view --json headRefOid). A failing CI is not a completed result.
    verification.ci is "absent" when the repo has no CI; say so in evidence."
  `);
});

test('fix prompt with observations', () => {
  const prompt = buildPrompt(task('fix', { round: 1, observations: [{ id: 'naming', title: 'Rename helper', url: 'https://github.com/AshuLab/carrier/pull/7#r2' }, { title: 'Typo in comment' }] }));
  expect(prompt).toContain('Invoke /code-resolve on PR #7');
  expect(prompt).toContain('Observations of the last review:\n- Rename helper (https://github.com/AshuLab/carrier/pull/7#r2)\n- Typo in comment');
  expect(prompt).toContain('Reply on each thread');
  expect(prompt).toContain('Leave every thread open');
  expect(prompt).toContain('Never merge the final PR.');
  expect(prompt).not.toContain('Blockers of the last review');
});

test('an empty observations list keeps the blockers prompt', () => {
  const blockers = [{ title: 'no test' }];
  expect(buildPrompt(task('fix', { observations: [], blockers }))).toBe(buildPrompt(task('fix', { blockers })));
});

test('verifyStateFirst and previous summaries are added only when present', () => {
  const plain = buildPrompt(task('review'));
  expect(plain).not.toContain('verify what is already done');
  expect(plain).not.toContain('Summaries of the previous turns');
  const rebuilt = buildPrompt(task('review', { verifyStateFirst: true, previousSummaries: ['first round found X', 'fix answered X'] }));
  expect(rebuilt).toContain('verify what is already done');
  expect(rebuilt).toContain('1. first round found X\n2. fix answered X');
});

test('codex invokes skills with $ and claude with /', () => {
  expect(buildPrompt(task('ship', {}, 'codex'))).toContain('$ship');
  expect(buildPrompt(task('ship'))).toContain('/ship');
});

test.each(['ship', 'review', 'fix'] as const)('every JSON example in the %s prompt passes parseCallerResult', (stage) => {
  const t = task(stage);
  const examples = [...buildPrompt(t).matchAll(/```json\n([\s\S]*?)\n```/g)].map((m) => m[1]!);
  expect(examples).toHaveLength(stage === 'review' ? 3 : 2);
  for (const raw of examples) {
    expect(parseCallerResult(raw, { executionId: t.executionId, repo: t.repo, epic: t.epic, stage })).toMatchObject({ ok: true });
  }
});

test.each(['ship', 'review', 'fix'] as const)('the %s prompt names no repo-specific command', (stage) => {
  expect(buildPrompt(task(stage))).not.toMatch(/\b(pnpm|npm|yarn|vitest|jest|pytest|make)\b/);
});

test('the review prompt carries the previous blockers from round two and none in round one', () => {
  const round1 = buildPrompt(task('review', { round: 1 }));
  expect(round1).not.toContain('Blockers of the previous round');
  expect(round1).toContain('Give every blocker you return a short stable id');
  const round2 = buildPrompt(task('review', { round: 2, blockers: [{ id: 'token-expiry', title: 'Token expiry is not checked' }, { title: 'No test' }] }));
  expect(round2).toContain('Blockers of the previous round (id and title):\n- token-expiry: Token expiry is not checked\n- (no id): No test');
  expect(round2).toContain('reuse its id');
  expect(round2).toContain('"resolved"');
});

test('the review prompt asks for observations with the stable-id rule and its example shows the field; other stages do not', () => {
  const review = buildPrompt(task('review'));
  expect(review).toContain('nitpick or a suggestion');
  expect(review).toContain('"observations"');
  expect(review).toContain('never reuse an id for a different finding');
  expect(review).toMatch(/"outcome": "completed"[\s\S]*?"observations": \[/);
  for (const stage of ['ship', 'fix'] as const) expect(buildPrompt(task(stage))).not.toContain('observations');
});

test.each(['ship', 'review', 'fix'] as const)('the %s prompt of a Forge bot says how to recover from a 401 in gh', (stage) => {
  const prompt = buildPrompt(task(stage), { forgeAgent: 'artanis-agent' });
  expect(prompt).toContain('Your GitHub token expires about an hour after this run starts. If a `gh` call fails with 401 (Bad credentials), run it again as `agent-forge gh artanis-agent <the same arguments>` from inside the workspace. git renews its own credentials.');
  expect(prompt.split('\n')[3]).toContain('agent-forge gh artanis-agent'); // right after the ground rules
});

test.each(['ship', 'review', 'fix'] as const)('the %s prompt without a Forge agent does not mention Forge', (stage) => {
  expect(buildPrompt(task(stage))).not.toContain('agent-forge');
  expect(buildPrompt(task(stage), {})).toBe(buildPrompt(task(stage)));
});

test.each(['ship', 'review', 'fix'] as const)('the %s persona goes after the role line and before the stage; without one the prompt is unchanged', (stage) => {
  const plain = buildPrompt(task(stage)).split('\n');
  const lines = buildPrompt({ ...task(stage), persona: { name: 'Ada', prompt: 'Be strict about migrations.' } }).split('\n');
  expect(lines.slice(0, 1)).toEqual(plain.slice(0, 1));
  expect(lines.slice(1, 3)).toEqual(['Your name is Ada.', 'Be strict about migrations.']);
  expect(lines.slice(3)).toEqual(plain.slice(1));
  expect(buildPrompt({ ...task(stage), persona: { prompt: 'Only a prompt.' } }).split('\n')[1]).toBe('Only a prompt.');
  expect(buildPrompt({ ...task(stage), persona: {} })).toBe(buildPrompt(task(stage)));
});

test('the intro and the signature tell the slot of a review apart: a reviewer by its slot, the lead as the lead', () => {
  const slotted = (reviewer: NonNullable<AgentTask['reviewer']>) => ({ ...task('review'), reviewer, sharedIdentity: true, persona: { name: 'Atlas' } });
  expect(buildPrompt({ ...task('review'), reviewer: 'reviewer' })).toBe(buildPrompt(task('review')));
  expect(buildPrompt(slotted('reviewer-2')).split('\n')[0]).toContain('You are the reviewer-2 of the final integration PR');
  expect(buildPrompt(slotted('reviewer-2'))).toContain('🤖 Reviewer [Atlas] via Carrier');
  expect(buildPrompt(slotted('lead')).split('\n')[0]).toContain('You are the lead reviewer of the final integration PR');
  expect(buildPrompt(slotted('lead'))).toContain('🤖 Lead reviewer [Atlas] via Carrier');
});

test('signatureOf names the role and the persona, and leaves no brackets without a name', () => {
  expect(signatureOf('reviewer', 'Atlas')).toBe('🤖 Reviewer [Atlas] via Carrier');
  expect(signatureOf('author')).toBe('🤖 Author via Carrier');
  expect(signatureOf('author', '')).toBe('🤖 Author via Carrier');
});

test.each([['ship', 'Author'], ['review', 'Reviewer'], ['fix', 'Author']] as const)('under a shared identity the %s prompt asks for the %s signature on everything published', (stage, role) => {
  const rule = buildPrompt({ ...task(stage), sharedIdentity: true, persona: { name: 'Atlas' } }).split('\n')[2]!;
  expect(rule).toContain(`${role} [Atlas] via Carrier`);
  for (const what of ['review comments', 'pull request body', 'replies on threads', 'any other comment, issue or issue body', 'commit message', 'before any trailers']) expect(rule).toContain(what);
  expect(buildPrompt({ ...task(stage), sharedIdentity: true })).toContain(`🤖 ${role} via Carrier`);
  expect(buildPrompt({ ...task(stage), sharedIdentity: true }).split('\n')[1]).toMatch(/: 🤖 \w+ via Carrier$/);
  expect(buildPrompt({ ...task(stage), sharedIdentity: false, persona: { name: 'Atlas' } })).not.toContain('via Carrier');
  expect(buildPrompt({ ...task(stage), sharedIdentity: false })).toBe(buildPrompt(task(stage)));
});

// The lines a stage adds between the ground rules and the result contract.
const stageLines = (t: AgentTask) => {
  const lines = buildPrompt(t).split('\n').slice(3);
  return lines.slice(0, lines.findIndex((l) => l.startsWith('Before finishing')));
};
const withSkills = (t: AgentTask, skills: ResolvedSkills): AgentTask => ({ ...t, skills });
const named = resolveSkills(solveSkills, { ship: 'build', review: { review: 'my-review', publish: 'my-post' }, fix: 'my-fix' });

test('a configured ship skill is invoked and only the contract sentences are said', () => {
  expect(stageLines(withSkills(task('ship'), named))).toMatchInlineSnapshot(`
    [
      "Invoke /build for epic #3. The epic must live in its own git worktree, and the body of the final integration PR must close the epic (Closes #3). Leave the final integration PR open.",
      "Never merge the final PR: a person tests it and decides the merge.",
    ]
  `);
  expect(buildPrompt(withSkills(task('ship', {}, 'codex'), named))).toContain('Invoke $build for epic #3.');
});

test('a configured review skill and its publisher are invoked', () => {
  expect(stageLines(withSkills(task('review', { round: 2 }), named)).slice(0, 2)).toMatchInlineSnapshot(`
    [
      "Review PR #7, round 2. First confirm the PR head is aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; if it is not, return needs_human.",
      "Invoke /my-review against the epic's spec and tickets, checking that earlier findings were fixed and nothing regressed, then publish the findings with /my-post.",
    ]
  `);
});

test('a review whose publish is null does not tell the agent to publish with a second skill', () => {
  const none = resolveSkills(solveSkills, { review: { review: 'my-review', publish: null } });
  const prompt = buildPrompt(withSkills(task('review'), none));
  expect(prompt).toContain("Invoke /my-review against the epic's spec and tickets, checking that earlier findings were fixed and nothing regressed.");
  expect(prompt).not.toMatch(/publish the findings|code-post/);
});

test('a configured fix skill is invoked in both fix prompts', () => {
  const fixing = withSkills(task('fix', { blockers: [{ title: 'x' }] }), named);
  expect(stageLines(fixing)).toMatchInlineSnapshot(`
    [
      "Invoke /my-fix on PR #7, answering every finding of the last review and fixing what applies.",
      "Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.",
      "Blockers of the last review:",
      "- x",
    ]
  `);
  expect(buildPrompt(withSkills(task('fix', { observations: [{ title: 'y' }] }), named))).toContain('Invoke /my-fix on PR #7, answering the observations');
});

test('the Solve-only sentences of ship are said only with the default ship skill, the contract ones for every skill', () => {
  const solve = buildPrompt(task('ship'));
  const other = buildPrompt(withSkills(task('ship'), named));
  for (const sentence of ['solve.md', 'design artifacts']) {
    expect(solve).toContain(sentence);
    expect(other).not.toContain(sentence);
  }
  for (const sentence of ['own git worktree', 'Leave the final integration PR open', 'Never merge the final PR', 'Before finishing, write exactly one JSON object']) {
    expect(solve).toContain(sentence);
    expect(other).toContain(sentence);
  }
  expect(other).toContain('Closes #3');
});

test('with several reviewers the fix prompt shows each finding under its reviewer and the review prompt names its slot and says others publish too', () => {
  const fix = buildPrompt(task('fix', { round: 1, blockers: [{ id: 'B1', title: 'one', reviewer: 'reviewer' }, { id: 'B1', title: 'two', reviewer: 'reviewer-2' }, { title: 'three', reviewer: 'reviewer-3' }] }));
  expect(fix).toContain('- reviewer:B1: one\n- reviewer-2:B1: two\n- reviewer-3: three');
  expect(fix).toContain('contradict');
  expect(buildPrompt(task('fix', { round: 1, blockers: [{ id: 'B1', title: 'one' }] }))).not.toContain('contradict');
  const review = buildPrompt({ ...task('review', { round: 1, severalReviewers: true }), reviewer: 'reviewer-2' });
  expect(review).toContain('You are the reviewer-2 of the final integration PR');
  expect(review).toContain('Other reviewers publish on this pull request too');
  expect(buildPrompt(task('review', { round: 1 }))).not.toContain('Other reviewers publish');
});
