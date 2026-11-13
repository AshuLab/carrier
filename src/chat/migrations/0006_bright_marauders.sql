CREATE TABLE `usage_price_overrides` (
	`model` text PRIMARY KEY NOT NULL,
	`mode` text NOT NULL,
	`aliasModel` text,
	`inputUsdPerMillion` real,
	`cachedInputUsdPerMillion` real,
	`cacheWriteUsdPerMillion` real,
	`outputUsdPerMillion` real,
	`updatedAt` integer NOT NULL
);
