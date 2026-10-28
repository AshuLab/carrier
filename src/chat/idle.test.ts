import { expect, test, vi } from 'vitest';
import { FakeClock } from '../orchestration/fake.ts';
import { idleExit } from './idle.ts';

const minute = 60_000;
function setup(live = () => 0) {
  const clock = new FakeClock();
  const exit = vi.fn(async () => {});
  return { clock, exit, idle: idleExit({ clock, live, exit }) };
}

test('with no client and no session the host exits a minute after it started', async () => {
  const { clock, exit } = setup();
  await clock.advance(minute - 1);
  expect(exit).not.toHaveBeenCalled();
  await clock.advance(1);
  expect(exit).toHaveBeenCalledTimes(1);
});

test('a client keeps it up, and the minute counts from the moment the last one leaves', async () => {
  const { clock, exit, idle } = setup();
  await clock.advance(30_000);
  idle.joined();
  idle.joined();
  await clock.advance(10 * minute);
  idle.left();
  await clock.advance(10 * minute);
  expect(exit).not.toHaveBeenCalled();
  idle.left();
  await clock.advance(minute - 1);
  expect(exit).not.toHaveBeenCalled();
  await clock.advance(1);
  expect(exit).toHaveBeenCalledTimes(1);
});

test('a live session keeps it up, and the minute counts from the recheck that finds none', async () => {
  let live = 1;
  const { clock, exit, idle } = setup(() => live);
  await clock.advance(10 * minute);
  expect(exit).not.toHaveBeenCalled();
  live = 0;
  idle.recheck();
  await clock.advance(minute);
  expect(exit).toHaveBeenCalledTimes(1);
});

test('stop cancels the countdown', async () => {
  const { clock, exit, idle } = setup();
  idle.stop();
  await clock.advance(5 * minute);
  expect(exit).not.toHaveBeenCalled();
});
