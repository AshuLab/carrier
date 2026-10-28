CREATE TABLE `sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`agent` text NOT NULL,
	`harness` text NOT NULL,
	`folder` text NOT NULL,
	`title` text,
	`options` text,
	`nativeId` text,
	`state` text DEFAULT 'idle' NOT NULL,
	`pid` integer,
	`pgid` integer,
	`createdAt` integer NOT NULL,
	`lastActiveAt` integer NOT NULL,
	`archived` integer DEFAULT false NOT NULL
);
