import { expect, test } from 'vitest';
import { chatConfigPathOf, chatPlacesOf, engineConfigPathOf, enginePlacesOf, providersPathOf } from './places.ts';

test('the top of the folder holds only the files a person edits', () => {
  expect([engineConfigPathOf('/h'), chatConfigPathOf('/h'), providersPathOf('/h')]).toEqual(['/h/engine.json', '/h/chat.json', '/h/providers.json']);
});

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

test('every place of the chat is under <folder>/chat/, the socket in its state folder', () => {
  expect(chatPlacesOf('/h')).toEqual({
    dir: '/h/chat',
    state: '/h/chat/state',
    socket: '/h/chat/state/chat.sock',
    logs: '/h/chat/logs',
    worktrees: '/h/chat/worktrees',
    projects: '/h/chat/projects',
    attachments: '/h/chat/attachments',
  });
});
