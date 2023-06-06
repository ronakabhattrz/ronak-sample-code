require 'dry/monads/result'

class Training::ExportCSVReportService < ApplicationService
  require 'csv'

  include Dry::Monads::Result::Mixin

  def initialize(users, training_user_exams)
    @users = users
    @training_user_exams = training_user_exams
  end

  def call
    file = CSV.generate(headers: true) do |csv|
      csv << headers

      refactor_data.each do |data|
        csv << data['Module name']
        csv << (['Video Status'] + data['Video Status'])
        csv << (['Exam status'] + data['Exam status'])
        csv << (['Finished at'] + data['Finished at'])
        csv << []
      end
    end

    Success(file)
  rescue StandardError => e
    Failure(error: e, data: csv_data)
  end

  private

  def headers
    [''] + csv_data.pluck('User').uniq.flatten
  end

  def refactor_data
    csv_data.group_by { |key| key['Module name'] }.map do |_, val|
      val.reduce do |hash_1, hash_2|
        hash_1.merge(hash_2) do |key, key_2, key_3|
          key == 'Module name' ? key_2 : key_2 + key_3
        end
      end
    end
  end

  def csv_data
    modules = []
    @users.each do |user|
      Training::Video.where(active: true).order(:title).each do |video|
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

  def video_status(user_id, video_id)
    user_video = Training::UserVideo.find_by(video_id: video_id, user_id: user_id)

    status = if user_video.present?
               user_video.finished? ? 'Completed' : 'Not Started'
             else
               'Not Started'
             end

    { status: status }
  end

  def exam_details(user_exam)
    status = if user_exam.present?
               if user_exam.finished?
                 'Passed'
               else
                 'Failed'
               end
             else
               '-'
             end

    finished_at = user_exam.present? && user_exam.finished_at.present? ? user_exam.finished_at.to_s : '-'

    { status: status, finished_at: finished_at }
  end
end