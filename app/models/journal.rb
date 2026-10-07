module Journal
  # Until Dreamwidth deploys its API fixes (#3687, #3691, #3693), only private
  # entries both read and edit safely: reading an access-locked entry fails,
  # and editing resets settings it didn't mention. So the journal lists and
  # posts private entries only. Turn this off once Dreamwidth's spec says
  # edits keep fields left out; see "Private-only mode" in
  # docs/plan-journal.md for how to check.
  PRIVATE_ONLY = true
end
