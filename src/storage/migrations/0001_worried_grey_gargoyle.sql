ALTER TABLE `epics` ADD `status` text DEFAULT 'queued' NOT NULL;--> statement-breakpoint
ALTER TABLE `epics` ADD `queuedAt` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `epics_repo_issue` ON `epics` (`repo`,`issue`);