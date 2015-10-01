class Event < ActiveRecord::Base
	belongs_to :user # The organiser
	has_many :attendances, -> { order 'created_at asc' }, dependent: :destroy
	has_many :participants, -> { order 'created_at asc' }, through: :attendances, source: :user

	validates :title, presence: true
	validates :start_time, presence: true
	validates :end_time, presence: true
	validates :attendance_cap, presence: true

  before_save do
  	self.start_time = self.start_time.in_time_zone("Pacific Time (US & Canada)")
    self.end_time = self.end_time.in_time_zone("Pacific Time (US & Canada)")
	end

  def group_by_criteria
    start_time.to_date.to_s(:db)
  end
end
