# frozen_string_literal: true

module Github
  class WorkflowOperations
    def initialize(client)
      @client = client
    end

    # Trigger a workflow (run specs)
    def trigger_workflow(repository, workflow_file, ref: "main")
      @client.post(
        "/repos/#{repository.full_name}/actions/workflows/#{workflow_file}/dispatches",
        { ref: ref }
      )
    end

    # Re-run failed jobs from a workflow run
    def rerun_failed_workflow(repository, run_id)
      @client.post(
        "/repos/#{repository.full_name}/actions/runs/#{run_id}/rerun-failed-jobs"
      )
    end

    # Get workflow runs for a specific branch/PR
    def get_workflow_runs(repository, branch: nil, workflow_id: nil, per_page: 10)
      path = "/repos/#{repository.full_name}/actions/runs"
      params = { per_page: per_page }
      params[:branch] = branch if branch
      params[:workflow_id] = workflow_id if workflow_id
      
      query_string = params.map { |k, v| "#{k}=#{v}" }.join("&")
      path += "?#{query_string}" if query_string.present?
      
      response = @client.get(path)
      runs = response.workflow_runs || []
      
      runs.map do |run|
        {
          id: run.id,
          name: run.name,
          status: run.status,
          conclusion: run.conclusion,
          head_branch: run.head_branch,
          created_at: run.created_at
        }
      end
    rescue Octokit::Error => e
      Rails.logger.error("Failed to get workflow runs: #{e.message}")
      []
    end
  end
end
