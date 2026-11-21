CREATE TABLE "cron_jobs" (
	"id" serial PRIMARY KEY NOT NULL,
	"project_id" integer NOT NULL,
	"name" text NOT NULL,
	"command" text DEFAULT 'unknown' NOT NULL,
	"schedule" text DEFAULT 'unknown' NOT NULL,
	"last_status" text DEFAULT 'unknown' NOT NULL,
	"last_duration" integer,
	"last_execution_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "deployments" (
	"id" serial PRIMARY KEY NOT NULL,
	"project_id" integer NOT NULL,
	"commit_sha" text,
	"status" text DEFAULT 'running' NOT NULL,
	"triggered_by" text DEFAULT 'web' NOT NULL,
	"duration_seconds" integer,
	"log" text DEFAULT '' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "github_pull_requests" (
	"id" serial PRIMARY KEY NOT NULL,
	"project_id" integer NOT NULL,
	"number" integer NOT NULL,
	"title" text NOT NULL,
	"state" text NOT NULL,
	"is_renovate" boolean DEFAULT false NOT NULL,
	"draft" boolean DEFAULT false NOT NULL,
	"author_login" text,
	"head_ref" text,
	"base_ref" text,
	"html_url" text,
	"opened_at" timestamp with time zone,
	"closed_at" timestamp with time zone,
	"merged_at" timestamp with time zone,
	"github_updated_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "job_executions" (
	"id" serial PRIMARY KEY NOT NULL,
	"cron_job_id" integer NOT NULL,
	"status" text DEFAULT 'unknown' NOT NULL,
	"duration" integer,
	"log" text DEFAULT '' NOT NULL,
	"executed_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "projects" (
	"id" serial PRIMARY KEY NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	"kind" text DEFAULT 'app' NOT NULL,
	"vps_path" text NOT NULL,
	"repo_url" text,
	"production_branch" text DEFAULT 'master' NOT NULL,
	"staging_branch" text DEFAULT 'staging',
	"production_url" text,
	"grafana_app_value" text,
	"umami_website_id" text,
	"has_deploy_script" boolean DEFAULT false NOT NULL,
	"has_status_script" boolean DEFAULT false NOT NULL,
	"cron_monitoring_enabled" boolean DEFAULT false NOT NULL,
	"maintenance_mode" boolean DEFAULT false NOT NULL,
	"last_commit_deployed" text,
	"latest_commit_available" text,
	"commits_behind" integer DEFAULT 0 NOT NULL,
	"staging_commits_ahead" integer DEFAULT 0 NOT NULL,
	"staging_commits_behind" integer DEFAULT 0 NOT NULL,
	"umami_visitors_24h" integer DEFAULT 0 NOT NULL,
	"umami_pageviews_24h" integer DEFAULT 0 NOT NULL,
	"umami_bounce_rate" integer DEFAULT 0 NOT NULL,
	"umami_sync_error" text,
	"umami_synced_at" timestamp with time zone,
	"vps_synced_at" timestamp with time zone,
	"github_synced_at" timestamp with time zone,
	"cron_synced_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "cron_jobs" ADD CONSTRAINT "cron_jobs_project_id_projects_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "deployments" ADD CONSTRAINT "deployments_project_id_projects_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "github_pull_requests" ADD CONSTRAINT "github_pull_requests_project_id_projects_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "job_executions" ADD CONSTRAINT "job_executions_cron_job_id_cron_jobs_id_fk" FOREIGN KEY ("cron_job_id") REFERENCES "public"."cron_jobs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "cron_jobs_project_name_unique" ON "cron_jobs" USING btree ("project_id","name");--> statement-breakpoint
CREATE INDEX "deployments_project_created_idx" ON "deployments" USING btree ("project_id","created_at");--> statement-breakpoint
CREATE INDEX "deployments_created_idx" ON "deployments" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "deployments_status_idx" ON "deployments" USING btree ("status");--> statement-breakpoint
CREATE UNIQUE INDEX "github_prs_project_number_unique" ON "github_pull_requests" USING btree ("project_id","number");--> statement-breakpoint
CREATE INDEX "github_prs_project_state_idx" ON "github_pull_requests" USING btree ("project_id","state");--> statement-breakpoint
CREATE INDEX "github_prs_renovate_state_idx" ON "github_pull_requests" USING btree ("is_renovate","state");--> statement-breakpoint
CREATE INDEX "job_executions_cron_executed_idx" ON "job_executions" USING btree ("cron_job_id","executed_at");--> statement-breakpoint
CREATE UNIQUE INDEX "projects_slug_unique" ON "projects" USING btree ("slug");--> statement-breakpoint
CREATE UNIQUE INDEX "projects_vps_path_unique" ON "projects" USING btree ("vps_path");--> statement-breakpoint
CREATE INDEX "projects_kind_idx" ON "projects" USING btree ("kind");--> statement-breakpoint
CREATE INDEX "projects_umami_website_id_idx" ON "projects" USING btree ("umami_website_id");