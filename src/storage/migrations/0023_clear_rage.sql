CREATE INDEX `executions_epic` ON `executions` (`epicId`,`startedAt`);--> statement-breakpoint
CREATE INDEX `execution_events_kind` ON `execution_events` (`executionId`,`kind`,`id`);