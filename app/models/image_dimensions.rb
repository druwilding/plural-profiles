# Reads a *newly attached* blob's pixel dimensions from its header, without
# asking an image library to decode any pixel data (mirrors what Active
# Storage's own Vips image analyzer does). Used to reject implausibly large
# images before the async AnalyzeJob, or an on-demand variant render, has to
# touch them — a small file can still declare a huge width/height and blow
# past the worker's memory limit when something eventually processes it.
module ImageDimensions
  MAX_DECODABLE_SIZE = 2.megabytes

  # Takes the attachment proxy (e.g. `model.avatar`) rather than a blob, for
  # two reasons:
  #
  # - Only a change actually being attached in this save has anything to
  #   check — an already-stored, unchanged attachment was validated when it
  #   was first attached, so re-checking it on every unrelated save of the
  #   record would mean an extra storage read (and a decode) per save.
  # - has_one_attached only uploads a freshly-attached file to the storage
  #   service in an after_commit callback, which runs *after* our model
  #   validations do — so a just-attached blob usually isn't in storage yet.
  #   We read straight from the pending upload's own io instead.
  def self.for(attached)
    attachable = attached.record.attachment_changes[attached.name.to_s]&.attachable
    return nil if attachable.nil?

    blob = attached.blob
    return nil if blob.nil? || blob.byte_size > MAX_DECODABLE_SIZE

    data = read_bytes(attachable)
    return nil if data.nil?

    image = Vips::Image.new_from_buffer(data, "", access: :sequential)
    [image.width, image.height]
  rescue Vips::Error
    nil
  end

  def self.read_bytes(attachable)
    case attachable
    when ActiveStorage::Blob, String
      # Already uploaded: an existing blob being reassigned, or a signed ID
      # from a direct upload that completed before the form was submitted.
      resolve_blob(attachable)&.download
    when Hash
      read_and_rewind(attachable[:io] || attachable["io"])
    when Pathname
      attachable.open { |file| file.read }
    else
      read_and_rewind(attachable) if attachable.respond_to?(:read) && attachable.respond_to?(:rewind)
    end
  end
  private_class_method :read_bytes

  def self.resolve_blob(attachable)
    attachable.is_a?(ActiveStorage::Blob) ? attachable : ActiveStorage::Blob.find_signed(attachable)
  end
  private_class_method :resolve_blob

  def self.read_and_rewind(io)
    return nil if io.nil?
    io.read.tap { io.rewind }
  end
  private_class_method :read_and_rewind
end
