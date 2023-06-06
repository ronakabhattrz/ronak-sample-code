class Training::CSVReportsController < AuthenticatedController
  before_action :fetch_data, only: [:create]
  before_action :authorize_csv_report, only: [:create, :download]

  # POST /training/csv_reports
  def create
    Training::ExportCSVReportJob.perform_later(@all_users_ids, @training_user_exams_ids, @training_report)
    redirect_to training_reports_path, success: 'CSV generation has started. You will receive an email notification with the results.'
  end

  def download
    send_data(csv_report.download, filename: csv_report.label.to_s, type: 'text/csv', disposition: 'attachment')
  end

  private

  def fetch_data
    @all_users_ids = current_company.users.pluck(:id)
    @training_user_exams_ids = policy_scope(Training::UserExam).most_recent.pluck(:id)
    @training_report = policy_scope(Training::Report).find_or_create_by(user: current_user, company: current_company)
  end

  def authorize_csv_report
    authorize %i[training csv_report]
  end

  def csv_report
    current_user.training_report.file
  end
end