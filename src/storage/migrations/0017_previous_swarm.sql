ALTER TABLE `executions` ADD `failureKind` text;--> statement-breakpoint
ALTER TABLE `executions` ADD `failureDetail` text;--> statement-breakpoint
ALTER TABLE `executions` ADD `exitCode` integer;--> statement-breakpoint
ALTER TABLE `executions` ADD `signal` text;--> statement-breakpoint
ALTER TABLE `executions` ADD `hostFreeMemMb` integer;--> statement-breakpoint
ALTER TABLE `executions` ADD `hostLoad` real;