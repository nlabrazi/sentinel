class CronStatusJob < ApplicationJob
  queue_as :default

  def perform
    Project.find_each do |project|
      begin
        ssh = SshExecutionService.new(project)
        result = ssh.execute(project.cron_status_command)

        if result[:exit_code].zero?
          data = JSON.parse(result[:stdout])
          data.each do |job_name, attrs|
            cron_job = project.cron_jobs.find_or_initialize_by(name: job_name)
            cron_job.update!(
              command: attrs['command'] || '',
              schedule: attrs['schedule'] || '',
              last_execution_at: Time.parse(attrs['last_run']) rescue nil,
              last_status: attrs['status'],
              last_duration: attrs['duration']
            )
          end
        end
      rescue StandardError => e
        Rails.logger.error "CronStatusJob failed for #{project.slug}: #{e.message}"
      end
    end
  end
end
