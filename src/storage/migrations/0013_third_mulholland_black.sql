CREATE TABLE `execution_events` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`executionId` text NOT NULL,
	`at` integer NOT NULL,
	`kind` text NOT NULL,
	`callId` text,
	`agentId` text,
	`tool` text,
	`arg` text,
	`summary` text,
	`status` text,
	`durationMs` integer,
	`payload` text,
	FOREIGN KEY (`executionId`) REFERENCES `executions`(`executionId`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `execution_events_execution` ON `execution_events` (`executionId`,`id`);