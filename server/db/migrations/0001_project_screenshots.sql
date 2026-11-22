CREATE TABLE "project_screenshots" (
	"project_id" integer PRIMARY KEY NOT NULL,
	"content_type" text DEFAULT 'image/jpeg' NOT NULL,
	"data_base64" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "projects" ADD COLUMN "screenshot_updated_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "project_screenshots" ADD CONSTRAINT "project_screenshots_project_id_projects_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE cascade ON UPDATE no action;