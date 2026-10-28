ALTER TABLE `sessions` ADD `workspaceKind` text DEFAULT 'folder' NOT NULL;--> statement-breakpoint
ALTER TABLE `sessions` ADD `worktreeBranch` text;--> statement-breakpoint
ALTER TABLE `sessions` ADD `worktreeFrom` text;--> statement-breakpoint
ALTER TABLE `sessions` ADD `worktreeBase` text;--> statement-breakpoint
ALTER TABLE `sessions` ADD `worktreePath` text;