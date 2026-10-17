import { userConfigJsonSchema } from '../../config/json-schema.ts';

export function schemaCommand() {
  process.stdout.write(`${JSON.stringify(userConfigJsonSchema(), null, 2)}\n`);
}
