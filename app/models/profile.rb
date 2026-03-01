class Profile < ApplicationRecord
  include HasAvatar

  HEART_EMOJIS = [
    "01_dewdrop_heart",
    "02_spring_heart",
    "03_hunter_heart",
    "04_woods_heart",
    "05_seafoam_heart",
    "06_fern_heart",
    "08_moss_heart",
    "09_bramble_heart",
    "10_wild_heart",
    "11_aqua_heart",
    "12_ocean_heart",
    "13_storm_heart",
    "14_abyss_heart",
    "15_ice_heart",
    "16_cornflower_heart",
    "18_azure_heart",
    "19_nightsky_heart",
    "20_mist_heart",
    "21_lavender_heart",
    "22_violet_heart",
    "23_aubegine_heart",
    "24_inky_heart",
    "25_shadow_heart",
    "26_blossom_heart",
    "28_burgundy_heart",
    "29_arcane_heart",
    "30_void_heart",
    "31_vulnerable_heart",
    "32_filthy_heart",
    "33_passionate_heart",
    "34_blackened_heart",
    "35_princess_heart",
    "36_red_heart",
    "38_murder_heart",
    "39_dawn_heart",
    "40_peach_heart",
    "41_fawn_heart",
    "42_fur_heart",
    "43_soil_heart",
    "50cadbury_heart",
    "50maroon_heart",
    "50sunshine_heart"
  ].freeze

  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :groups, through: :group_profiles

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true
  validates :created_at, comparison: { less_than_or_equal_to: -> { Time.current + 1.minute }, message: "can't be in the future" }, allow_nil: true, if: :created_at_changed?
  validate :heart_emojis_are_valid

  def to_param
    uuid
  end

  def heart_emoji_display_name(heart)
    heart.sub(/\A\d+_?/, "").tr("_", " ")
  end

  private

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end

  def heart_emojis_are_valid
    return if heart_emojis.blank?
    invalid = heart_emojis - HEART_EMOJIS
    errors.add(:heart_emojis, "contains invalid hearts: #{invalid.join(', ')}") if invalid.any?
  end
end
