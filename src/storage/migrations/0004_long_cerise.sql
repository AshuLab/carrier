CREATE TABLE `executions` (
	`executionId` text PRIMARY KEY NOT NULL,
	`epicId` integer NOT NULL,
	`stage` text NOT NULL,
	`status` text DEFAULT 'running' NOT NULL,
	`sessionId` text,
	`resultPath` text NOT NULL,
	`startedAt` integer NOT NULL,
	`finishedAt` integer,
	FOREIGN KEY (`epicId`) REFERENCES `epics`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
ALTER TABLE `epics` ADD `stage` text;--> statement-breakpoint
ALTER TABLE `epics` ADD `round` integer;--> statement-breakpoint
ALTER TABLE `epics` ADD `prNumber` integer;--> statement-breakpoint
ALTER TABLE `epics` ADD `prHeadSha` text;--> statement-breakpoint
ALTER TABLE `epics` ADD `needsHumanReason` text;--> statement-breakpoint
ALTER TABLE `epics` ADD `finishedAt` integer;