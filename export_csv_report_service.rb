class Training::ExportCSVReportService < ApplicationService
  require 'csv'
  def initialize(users, training_user_exams)
    @users = users
    @training_user_exams = training_user_exams
  end

  def call
    file = CSV.generate(headers: true) do |csv|
      headers = [''] + csv_data.pluck('User').uniq.flatten
      csv << headers
      refactor_data = hash_refactor(csv_data)
      refactor_data.each do |data|
        csv << data['Module name']
        csv << (['Video Status'] + data['Video Status'])
        csv << (['Exam status'] + data['Exam status'])
        csv << (['Finished at'] + data['Finished at'])
        csv << []
      end
    end
  rescue StandardError => e
    OpenStruct.new(success?: false, payload: {}, error: e, data: csv_data)
  else
    OpenStruct.new(success?: true, payload: file, error: nil)
  end

  private

  # NOTE: The hash had to be converted into group by key ('Module name'). so basically same `Module name` key is merge to gether with the single key.
  def hash_refactor(hash)
    hash.group_by { |key| key['Module name'] }.map do |_, val|
      val.inject do |hash_1, hash_2|
        hash_1.merge(hash_2) do |key, key_2, key_3|
          key == 'Module name' ? key_2 : key_2 + key_3
        end
      end
    end
  end

  def user_exam_status(user_exam)
    if user_exam.present?
      if !user_exam.finished?
        'In Progress'
      elsif user_exam.pass?
        'Passed'
      else
        'Failed'
      end
    else
      '-'
    end
  end

  def exam_details(user_exam)
    status = user_exam_status(user_exam)
    finished_at = if user_exam.present?
                    user_exam.finished_at.present? ? user_exam.finished_at.to_s : '-'
                  else
                    '-'
                  end
    { status: status, finished_at: finished_at }
  end

  def video_status(user_id, video_id)
    user_video = Training::UserVideo.find_by(video_id: video_id, user_id: user_id)
    status = if user_video.present?
               (user_video&.finished? ? 'Completed' : 'Not Started')
             else
               'Not Started'
             end

    { status: status }
  end

  def csv_data
    modules = []
    @users.each do |user|
      traning_videos = Training::Video.where(active: true).order(:title)
      traning_videos.each do |video|
        user_exam = @training_user_exams.find_by(user: user, exam: video.exam)
        video_details = video_status(user.id, video.id)
        exam_details = exam_details(user_exam)
        modules << {
          'User' => [user.name_or_email],
          'Module name' => [video.title],
          'Video Status' => [video_details[:status]],
          'Exam status' => [exam_details[:status]],
          'Finished at' => [exam_details[:finished_at]]
        }
      end
    end
    modules
  end
end
