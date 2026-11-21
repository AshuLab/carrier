CREATE TABLE `usage_scan_files` (
	`path` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`version` integer NOT NULL,
	`size` integer NOT NULL,
	`mtimeMs` real NOT NULL,
	`offset` integer NOT NULL,
	`guard` text NOT NULL,
	`state` text NOT NULL
);
