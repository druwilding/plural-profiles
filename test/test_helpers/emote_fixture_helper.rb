# Helpers available inside fixture ERB for the emote fixtures. They use the
# heart images in db/emotes/hearts/ (one file per emote, named after it), the
# same ones production imported and db/seeds.rb imports.
module EmoteFixtureHelper
  EMOTE_IMAGES = Rails.root.join("db/emotes/hearts")

  # [[name, code], ...] for every fixture emote image, in name order.
  def emote_fixture_names
    Dir[EMOTE_IMAGES.join("*.webp")].sort.map do |path|
      name = File.basename(path, ".webp")
      [ name, Emote.default_code(name) ]
    end
  end

  # Like ActiveStorage::FixtureSet.blob, which only reads files directly in
  # test/fixtures/files: uploads the emote's image to the test service and
  # returns the blob's fixture attributes.
  def emote_image_blob(name)
    blob = ActiveStorage::Blob.new(filename: "#{name}.webp", key: ActiveStorage::Blob.generate_unique_secure_token)
    EMOTE_IMAGES.join("#{name}.webp").open do |io|
      blob.unfurl(io)
      blob.upload_without_unfurling(io)
    end
    blob.attributes.transform_values { |value| value.is_a?(Hash) ? value.to_json : value }.compact.to_json
  end
end

ActiveRecord::FixtureSet.context_class.include(EmoteFixtureHelper)
