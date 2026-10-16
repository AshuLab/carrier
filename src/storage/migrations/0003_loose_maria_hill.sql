ALTER TABLE `epics` ADD `startedAt` integer;--> statement-breakpoint
ALTER TABLE `epics` ADD `config` text;--> statement-breakpoint
ALTER TABLE `epics` ADD `cancelReason` text;--> statement-breakpoint
ALTER TABLE `epics` ADD `labelPending` integer DEFAULT false NOT NULL;