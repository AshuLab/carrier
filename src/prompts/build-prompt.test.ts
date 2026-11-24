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

test('the fix of an epic with several reviewers tells the author that it decides when two reviewers contradict each other, and says so in its summary', () => {
  expect(stageLines(task('fix', { round: 1, blockers: [{ id: 'B1', title: 'use a map', reviewer: 'reviewer' }, { id: 'B1', title: 'use a list', reviewer: 'reviewer-2' }, { title: 'no id', reviewer: 'reviewer-2' }] }))).toMatchInlineSnapshot(`
    [
      "Invoke /code-resolve on PR #7, answering every finding of the last review and fixing what applies.",
      "Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.",
      "Blockers of the last review:",
      "- reviewer:B1: use a map",
      "- reviewer-2:B1: use a list",
      "- reviewer-2: no id",
      "When the blockers of two reviewers contradict each other, you decide: say in your summary which one you did not follow and why, because the reviewers read your summary in their next round.",
    ]
  `);
});

test('the review of an epic with several reviewers tells the reviewer to judge only the blockers it is given by id and to leave the threads it did not open; one reviewer is told nothing of it', () => {
  expect(stageLines({ ...task('review', { round: 2, severalReviewers: true, blockers: [{ id: 'B1', title: 'use a map' }, { title: 'no id' }] }), reviewer: 'reviewer-2' })).toMatchInlineSnapshot(`
    [
      "Review PR #7, round 2. First confirm the PR head is aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; if it is not, return needs_human.",
      "Invoke /code-review against the epic's spec and tickets, checking that earlier findings were fixed and nothing regressed, then publish the findings with /code-post.",
      "Blockers of the previous round (id and title):",
      "- B1: use a map",
      "- (no id): no id",
      "Give every blocker you return a short stable id. When a finding above persists, reuse its id; never reuse an id for a different finding. List in "resolved" the ids of the blockers above that are now fixed.",
      "Other reviewers publish on this pull request too, and two of you may share one account: judge only the blockers you are given above, by id (by title when one has no id), and leave alone the review threads you did not open.",
      "Findings that do not stop approval (what you would post as a nitpick or a suggestion) are observations: list them in "observations" of a completed result, each with a title, a link when you have one, and a short stable id by the same rule as blockers (reuse it when the finding persists; never reuse an id for a different finding). Leave the field out when there are none.",
      "Return changes_requested with the blockers if there are any. Return completed only if the review is conclusive, there are no blockers and the repo's verifications are confirmed on that same commit. If the review is inconclusive (missing context, cannot verify), return needs_human.",
    ]
  `);
  const one = buildPrompt(task('review', { round: 2, blockers: [{ id: 'B1', title: 'use a map' }, { title: 'no id' }] }));
  expect(one).not.toContain('leave alone the review threads');
  expect(one).not.toContain('Other reviewers');
});

// --- the lead reviewer's prompt ---

const leadTask = (context: Partial<AgentTask['context']> = {}, over: Partial<AgentTask> = {}): AgentTask => ({ ...task('lead', context), reviewer: 'lead', ...over });
const summaries = [{ reviewer: 'reviewer' as const, summary: 'All the tickets are covered.' }, { reviewer: 'reviewer-2' as const, summary: 'The migration is reversible.' }];

test('lead prompt', () => {
  expect(buildPrompt(leadTask({ round: 2, reviewerSummaries: summaries }))).toMatchInlineSnapshot(`
    "You are the lead reviewer of the final integration PR of epic #3 in AshuLab/carrier. Execution exec-1, stage lead.
    Nobody answers questions during this run: decide, and use needs_human when you cannot.
    Apply the repo's own rules (its docs, agent instructions and conventions) to choose and evaluate tests, CI and blockers. Do not assume commands from other repos.
    Review PR #7 as the final reviewer: the reviewers of this epic agreed on it, and nobody reviews after you. First confirm the PR head is aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; if it is not, return needs_human.
    What the reviewers concluded, by reviewer:
    - reviewer: All the tickets are covered.
    - reviewer-2: The migration is reversible.
    Invoke /code-review against the epic's spec and tickets, taking what the reviewers concluded into account and checking that nothing regressed, then publish the findings with /code-post.
    When you find no blocker, give the pull request its formal approval with your own identity (gh pr review 7 --approve), and say in "approval" of the result whether you submitted it, with the link of the review when you have one.
    The approval is not required: when you cannot give it, return "approval" with "submitted" false and the epic goes on all the same.
    Give every blocker you return a short stable id (for example "token-expiry").
    Findings that do not stop approval (what you would post as a nitpick or a suggestion) are observations: list them in "observations" of a completed result, each with a title, a link when you have one and a short stable id. Leave the field out when there are none.
    Return changes_requested with the blockers if there are any. Return completed only if the review is conclusive, there are no blockers and the repo's verifications are confirmed on that same commit. If the review is inconclusive (missing context, cannot verify), return needs_human.
    Before finishing, write exactly one JSON object to /r/exec-1.json. That path is also in the environment variable CARRIER_RESULT_PATH: write to "$CARRIER_RESULT_PATH" instead of retyping it, because a path with one segment missing is a result nobody reads. Repeat executionId, repo, epic and stage as given. Allowed outputs:
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "lead",
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
      ],
      "approval": {
        "submitted": true,
        "url": "https://github.com/AshuLab/carrier/pull/7#pullrequestreview-789"
      }
    }
    \`\`\`
    \`\`\`json
    {
      "executionId": "exec-1",
      "repo": "AshuLab/carrier",
      "epic": 3,
      "stage": "lead",
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
      "stage": "lead",
      "summary": "<one or two sentences for the next agent of this epic: what you did and concluded>",
      "outcome": "needs_human",
      "reason": "<why a person has to step in>"
    }
    \`\`\`
    verification.ci is "absent" when the repo has no CI; say so in evidence."
  `);
});

test('the lead is told it is the final reviewer, is given the summaries of the reviewers and is asked for the formal approval and to say in the result whether it submitted it', () => {
  const lines = stageLines(leadTask({ round: 2, reviewerSummaries: summaries }));
  expect(lines[0]).toContain('as the final reviewer');
  expect(lines).toContain('What the reviewers concluded, by reviewer:');
  expect(lines).toContain('- reviewer: All the tickets are covered.');
  expect(lines).toContain('- reviewer-2: The migration is reversible.');
  expect(lines.join('\n')).toContain('formal approval with your own identity');
  expect(lines.join('\n')).toContain('"approval"');
  expect(stageLines(leadTask()).join('\n')).not.toContain('What the reviewers concluded');
  expect(buildPrompt(leadTask()).split('\n')[0]).toContain('You are the lead reviewer of the final integration PR');
});

test('the lead\'s examples pass the contract for the lead stage, and the completed one shows the approval; a review\'s does not', () => {
  const t = leadTask();
  const examples = [...buildPrompt(t).matchAll(/```json\n([\s\S]*?)\n```/g)].map((m) => m[1]!);
  expect(examples).toHaveLength(3);
  for (const raw of examples) expect(parseCallerResult(raw, { executionId: t.executionId, repo: t.repo, epic: t.epic, stage: 'lead' })).toMatchObject({ ok: true });
  expect(examples[0]).toContain('"approval"');
  expect(examples[1]).toContain('"stage": "lead"');
  expect(buildPrompt(task('review'))).not.toContain('"approval"');
});

test('a lead whose profile is the author\'s is told GitHub refuses that approval, and signs what it publishes as the lead; one with its own profile is told the approval is not required', () => {
  const shared = buildPrompt(leadTask({}, { sharedIdentity: true, persona: { name: 'Atlas' } }));
  expect(shared).toContain('does not let an account approve its own pull request');
  expect(shared).toContain('🤖 Lead reviewer [Atlas] via Carrier');
  const own = buildPrompt(leadTask({}, { sharedIdentity: false }));
  expect(own).not.toContain('does not let an account approve');
  expect(own).toContain('The approval is not required');
  expect(own).not.toContain('via Carrier');
});

test('the lead invokes the skill resolved for it, with / or $ by harness, and what no level names for it comes from the review skill', () => {
  const skills = { ...resolveSkills(solveSkills), lead: { review: { name: 'my-lead', named: true }, publish: { name: 'my-lead-post', named: true } } };
  expect(stageLines(withSkills(leadTask(), skills))[1]).toBe('Invoke /my-lead against the epic\'s spec and tickets, taking what the reviewers concluded into account and checking that nothing regressed, then publish the findings with /my-lead-post.');
  expect(stageLines(withSkills(leadTask({}, { harness: 'codex' }), skills))[1]).toContain('Invoke $my-lead against');
  expect(stageLines(withSkills(leadTask(), { ...skills, lead: { review: { name: 'my-lead', named: true }, publish: null } })).join('\n')).not.toContain('then publish');
  expect(stageLines(leadTask()).join('\n')).toContain('Invoke /code-review against'); // no skills saved: Solve's defaults, the review's
  expect(stageLines(withSkills(leadTask(), named)).join('\n')).toContain('Invoke /my-review against');
});

test('the lead prompt names no repo-specific command', () => {
  expect(buildPrompt(leadTask({ reviewerSummaries: summaries }))).not.toMatch(/\b(pnpm|npm|yarn|vitest|jest|pytest|make)\b/);
});
