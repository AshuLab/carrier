import { z } from 'zod';
import { defaults } from './load.ts';
import { configSchema } from './schema.ts';

type JsonSchema = { required?: string[]; properties?: Record<string, JsonSchema> };

// The file is merged over `defaults` before the schema sees it, so what has a default is not required of the user.
function optionalWhereDefaulted(schema: JsonSchema, base: Record<string, unknown>) {
  schema.required = schema.required?.filter((key) => !(key in base));
  for (const [key, value] of Object.entries(base)) {
    const child = schema.properties?.[key];
    if (child && typeof value === 'object' && value !== null) optionalWhereDefaulted(child, value as Record<string, unknown>);
  }
  return schema;
}

/** JSON Schema of the config file as the user writes it, for editors and for agents that write it. */
export const userConfigJsonSchema = () => optionalWhereDefaulted(z.toJSONSchema(configSchema, { io: 'input' }) as JsonSchema, defaults);
