module Dreamwidth
  # One of a user's icons. Each can have several keywords, and posting names
  # it by any one of them.
  Icon = Data.define(:id, :keywords, :url, :comment) do
    def self.from_api(hash)
      new(id: hash.fetch("picid"), keywords: Array(hash["keywords"]), url: hash["url"], comment: hash["comment"].to_s)
    end
  end
end
