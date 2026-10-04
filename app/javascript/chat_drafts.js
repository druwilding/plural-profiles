// Unsent chat messages, kept per account and channel in localStorage so
// they survive going to another channel or server and coming back, a reload,
// or closing the tab.
//
// A key is "chat-draft:<user id>:<channel uuid>" (the composer's
// data-draft-key holds the part after "chat-draft:"), so one account never
// sees another's drafts in a shared browser, and signing out can clear just
// that account's.
//
// Storage can be switched off or full. Every function copes, and save says
// whether it worked.
const PREFIX = "chat-draft:"

export function loadDraft(key) {
  try {
    return localStorage.getItem(PREFIX + key) || ""
  } catch {
    return ""
  }
}

// An empty body removes the draft. False if it couldn't be kept.
export function saveDraft(key, body) {
  try {
    body ? localStorage.setItem(PREFIX + key, body) : localStorage.removeItem(PREFIX + key)
    return true
  } catch {
    return false
  }
}

export function clearDraft(key) {
  saveDraft(key, "")
}

export function clearDraftsForUser(userId) {
  try {
    const prefix = `${PREFIX}${userId}:`
    Object.keys(localStorage).filter(key => key.startsWith(prefix)).forEach(key => localStorage.removeItem(key))
  } catch { /* nothing kept to clear */ }
}
