# Reads an attached blob's pixel dimensions from its header, without asking
# an image library to decode any pixel data (mirrors what ActiveStorage's own
# Vips image analyzer does). Used to reject implausibly large images before
# the async AnalyzeJob, or an on-demand variant render, has to touch them —
# a small file can still declare a huge width/height and blow past the
# worker's memory limit when something eventually processes it.
module ImageDimensions
  MAX_DECODABLE_SIZE = 2.megabytes

  def self.for(blob)
    return nil if blob.byte_size > MAX_DECODABLE_SIZE

    image = Vips::Image.new_from_buffer(blob.download, "", access: :sequential)
    [image.width, image.height]
  rescue Vips::Error
    nil
  end
end
