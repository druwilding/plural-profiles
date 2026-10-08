// Unposted journal entries, kept in this browser's localStorage and never
// sent to our server (docs/plan-journal.md, "Drafts, saved in the browser").
//
// A key is "journal-draft:<user id>:new" (the form's draft key value holds
// the part after "journal-draft:"): one draft per account, whichever journal
// it was started in. One account never sees another's drafts in a shared
// browser, and signing out can clear just that account's.
//
// A draft is { savedAt, dateChanged, fields: { name: value } }. Storage can be
// switched off or full; every function copes, and save says whether it
// worked.
const PREFIX = "journal-draft:"

export function loadDraft(key) {
  try {
    const stored = localStorage.getItem(PREFIX + key)
    return stored ? JSON.parse(stored) : null
  } catch {
    return null
  }
}

// False if it couldn't be kept.
export function saveDraft(key, draft) {
  try {
    localStorage.setItem(PREFIX + key, JSON.stringify(draft))
    return true
  } catch {
    return false
  }
}

export function clearDraft(key) {
  try {
    localStorage.removeItem(PREFIX + key)
  } catch { /* nothing kept to clear */ }
}

export function clearDraftsForUser(userId) {
  try {
    const prefix = `${PREFIX}${userId}:`
    Object.keys(localStorage).filter(key => key.startsWith(prefix)).forEach(key => localStorage.removeItem(key))
  } catch { /* nothing kept to clear */ }
}
