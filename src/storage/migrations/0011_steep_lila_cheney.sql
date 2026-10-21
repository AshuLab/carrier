CREATE TABLE `epic_slices` (
	`epicId` integer NOT NULL,
	`number` integer NOT NULL,
	`title` text NOT NULL,
	`state` text NOT NULL,
	`blockedBy` text NOT NULL,
	`assignee` text,
	`prNumber` integer,
	`closedAt` integer,
	`readAt` integer NOT NULL,
	`truncated` integer DEFAULT false NOT NULL,
	PRIMARY KEY(`epicId`, `number`)
);
