CREATE TABLE `epics` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`repo` text NOT NULL,
	`issue` integer NOT NULL
);
