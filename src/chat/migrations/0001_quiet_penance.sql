CREATE TABLE `chat_events` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`sessionId` text NOT NULL,
	`at` integer NOT NULL,
	`kind` text NOT NULL,
	`data` text NOT NULL,
	FOREIGN KEY (`sessionId`) REFERENCES `sessions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `chat_events_session` ON `chat_events` (`sessionId`,`id`);--> statement-breakpoint
CREATE TABLE `chat_turns` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`sessionId` text NOT NULL,
	`startedAt` integer NOT NULL,
	`model` text,
	`outcome` text NOT NULL,
	`durationMs` integer NOT NULL,
	`toolCalls` integer NOT NULL,
	`usage` text,
	FOREIGN KEY (`sessionId`) REFERENCES `sessions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `chat_turns_session` ON `chat_turns` (`sessionId`);