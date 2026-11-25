ALTER TABLE "projects" ADD COLUMN "production_ci_status" text DEFAULT 'unknown' NOT NULL;--> statement-breakpoint
ALTER TABLE "projects" ADD COLUMN "production_ci_url" text;