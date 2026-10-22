ALTER TABLE `epic_slices` ADD `prState` text;--> statement-breakpoint
ALTER TABLE `epic_slices` ADD `prMergedAt` integer;
--> statement-breakpoint
-- The cached slices predate the own-pull-request rule (some linked a sibling's or the final PR): clear them so the next poll reads them again (a cache of GitHub, nothing decides from it).
DELETE FROM `epic_slices`;
