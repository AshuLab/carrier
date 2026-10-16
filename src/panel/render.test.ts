import { expect, test } from 'vitest';
import { renderPanel, type PanelEpic, type PanelSnapshot } from './render.ts';

const now = 1_000_000_000;
const epic = (over: Partial<PanelEpic> = {}): PanelEpic => ({
  repo: 'acme/web',
  issue: 12,
  status: 'running',
  stage: 'ship',
  round: null,
  maxReviews: 5,
  blockers: 0,
  stageSince: now - 185_000,
  lastActivityAt: now - 12_000,
  issueUrl: 'https://github.com/acme/web/issues/12',
  prUrl: null,
  lastError: null,
  needsHumanReason: null,
  ...over,
});
const snapshot = (over: Partial<PanelSnapshot> = {}): PanelSnapshot => ({ now, slots: { busy: 0, total: 3 }, queue: [], epics: [], ...over });

test('empty queue', () => {
  expect(renderPanel(snapshot()).join('\n')).toMatchInlineSnapshot(`"carrier  slots 0/3  cola 0"`);
});

test('queued epics in order next to the busy slots', () => {
  const lines = renderPanel(
    snapshot({
      slots: { busy: 1, total: 3 },
      queue: [
        { repo: 'acme/api', issue: 7 },
        { repo: 'acme/web', issue: 30 },
      ],
      epics: [epic()],
    }),
  );
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 1/3  cola 2: acme/api#7, acme/web#30
    acme/web#12  ship  blockers 0  en etapa 3m 05s  actividad hace 12s
      issue https://github.com/acme/web/issues/12"
  `);
});

test('epic in review with blockers, round, PR link and no output yet', () => {
  const lines = renderPanel(
    snapshot({
      slots: { busy: 1, total: 1 },
      epics: [epic({ stage: 'review', round: 2, blockers: 3, prUrl: 'https://github.com/acme/web/pull/40', lastActivityAt: null, stageSince: now - 7_380_000 })],
    }),
  );
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 1/1  cola 0
    acme/web#12  review  ronda 2/5  blockers 3  en etapa 2h 03m  sin actividad
      issue https://github.com/acme/web/issues/12  PR https://github.com/acme/web/pull/40"
  `);
});

test('needs_human shows the reason', () => {
  const lines = renderPanel(
    snapshot({ epics: [epic({ status: 'needs_human', stage: 'review', round: 5, blockers: 2, needsHumanReason: 'límite de revisiones: la ronda 5 de 5 sigue con cambios pedidos' })] }),
  );
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 0/3  cola 0
    acme/web#12  NEEDS HUMAN  ronda 5/5  blockers 2  en etapa 3m 05s  actividad hace 12s
      issue https://github.com/acme/web/issues/12
      motivo: límite de revisiones: la ronda 5 de 5 sigue con cambios pedidos"
  `);
});

test('epic with a last error', () => {
  const lines = renderPanel(snapshot({ epics: [epic({ lastError: 'el proceso del agente terminó con error' })] }));
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 0/3  cola 0
    acme/web#12  ship  blockers 0  en etapa 3m 05s  actividad hace 12s
      issue https://github.com/acme/web/issues/12
      error: el proceso del agente terminó con error"
  `);
});
