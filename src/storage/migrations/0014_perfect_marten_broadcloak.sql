CREATE TABLE `epic_review_threads` (
	`epicId` integer NOT NULL,
	`id` text NOT NULL,
	`position` integer NOT NULL,
	`path` text NOT NULL,
	`line` integer,
	`resolved` integer NOT NULL,
	`outdated` integer NOT NULL,
	`author` text,
	`bot` integer NOT NULL,
	`firstLine` text NOT NULL,
	`commentCount` integer NOT NULL,
	`url` text NOT NULL,
	`readAt` integer NOT NULL,
	`truncated` integer DEFAULT false NOT NULL,
	PRIMARY KEY(`epicId`, `id`)
);
--> statement-breakpoint
-- The cached pull request blocks of finished epics predate the threads: clear them so the next poll reads block and threads once (a cache of GitHub, nothing decides from it).
UPDATE `epics` SET `pr` = NULL WHERE `status` IN ('merged', 'cancelled');
