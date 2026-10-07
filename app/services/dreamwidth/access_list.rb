module Dreamwidth
  # One of a journal's access filters, as offered for custom security.
  AccessList = Data.define(:id, :name) do
    def self.from_api(hash)
      new(id: hash.fetch("id"), name: hash.fetch("name"))
    end
  end
end
