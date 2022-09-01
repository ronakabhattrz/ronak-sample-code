class Training::Video < ApplicationRecord
  audited

  belongs_to :video_category
  has_many :user_videos, dependent: :destroy
  has_many :users, through: :user_videos, class_name: 'User', source: :user
  has_one :exam, class_name: 'Training::Exam', dependent: :restrict_with_exception

  before_create :assign_uuid_id

  counter_culture :video_category, column_name: proc { |model| model.active? ? 'active_video_count' : nil }

  validates :embed_url, presence: true, uniqueness: { case_sensitive: false }
  validates :embed_url,
            format: { with: %r{\Ahttps://player\.vimeo\.com/video/\d+\z}, message: 'not a valid Vimeo URL' }, allow_blank: true
  validates :duration, presence: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :title, presence: true
  validates :description, presence: true

  scope :active, -> { where(active: true) }

  def title_and_category
    "#{title} (Category: #{video_category.name})"
  end

end
