# Generates a UUID in the same format as SecureRandom.uuid, but guaranteed
# never to contain the digit 7. Every 7 in the generated UUID is replaced
# with a randomly chosen character from the remaining hex alphabet (0–6, 8–9, a–f).
module PluralProfilesUuid
  REPLACEMENT_CHARS = %w[0 1 2 3 4 5 6 8 9 a b c d e f].freeze

  def self.generate
    SecureRandom.uuid.gsub("7") { REPLACEMENT_CHARS[SecureRandom.random_number(15)] }
  end
end
