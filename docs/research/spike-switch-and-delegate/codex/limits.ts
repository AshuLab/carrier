import { App, tmp } from './lib.ts';
import { rmSync } from 'node:fs';
const folder = tmp('cdxb-');
const app = new App('limits', folder);
try {
  await app.init();
  const r = await app.request('account/rateLimits/read', {});
  const strip = (o: any): any => (o && typeof o === 'object' ? Object.fromEntries(Object.entries(o).filter(([k]) => !/email|account|user|id$/i.test(k)).map(([k, v]) => [k, strip(v)])) : o);
  console.log(JSON.stringify(strip(r), null, 1).slice(0, 2500));
} finally { await app.close(); rmSync(folder, { recursive: true, force: true }); }
