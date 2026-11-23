CREATE TABLE `project_sizes` (
	`folder` text PRIMARY KEY NOT NULL,
	`bytes` integer NOT NULL,
	`parts` text NOT NULL,
	`measuredAt` integer NOT NULL
);
