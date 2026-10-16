CREATE TABLE `epic_events` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`epicId` integer NOT NULL,
	`at` integer NOT NULL,
	`type` text NOT NULL,
	`data` text NOT NULL,
	FOREIGN KEY (`epicId`) REFERENCES `epics`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
ALTER TABLE `executions` ADD `error` text;