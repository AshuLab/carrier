ALTER TABLE `chat_turns` ADD `harness` text;--> statement-breakpoint
ALTER TABLE `chat_turns` ADD `agent` text;--> statement-breakpoint
ALTER TABLE `chat_turns` ADD `nativeId` text;--> statement-breakpoint
UPDATE `chat_turns` SET `harness` = (SELECT `harness` FROM `sessions` WHERE `sessions`.`id` = `chat_turns`.`sessionId`), `agent` = (SELECT `agent` FROM `sessions` WHERE `sessions`.`id` = `chat_turns`.`sessionId`), `nativeId` = (SELECT `nativeId` FROM `sessions` WHERE `sessions`.`id` = `chat_turns`.`sessionId`);
