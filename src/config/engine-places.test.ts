import { expect, test } from 'vitest';
import { enginePlacesOf } from './engine-places.ts';

test('every place of the engine is under <folder>/engine/, the socket and the database in its state folder', () => {
  expect(enginePlacesOf('/h')).toEqual({
    dir: '/h/engine',
    state: '/h/engine/state',
    socket: '/h/engine/state/control.sock',
    db: '/h/engine/state/carrier.db',
    logs: '/h/engine/logs',
    repos: '/h/engine/repos',
    reviews: '/h/engine/reviews',
    worktrees: '/h/engine/worktrees',
  });
});
