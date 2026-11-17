ALTER TABLE `sessions` ADD `parentSessionId` text REFERENCES sessions(id);--> statement-breakpoint
ALTER TABLE `sessions` ADD `delegationRequestId` text;--> statement-breakpoint
CREATE UNIQUE INDEX `sessions_delegation_request` ON `sessions` (`parentSessionId`,`delegationRequestId`);