import { Controller } from "@hotwired/stimulus"
import { loadDraft, saveDraft, clearDraft } from "chat_drafts"

// Owns the whole "posting as" + message composer area. Enter sends the
// message, Shift+Enter inserts a newline. It also live-previews Tupperbox-
// style proxying: as you type, if the message matches one of your profiles'
// or groups' chat_bracket_before/chat_bracket_after (e.g. "guy:" ... or
// "{" ... "}"), the "Posting as" pill swaps to that profile/group's
// avatar/name — purely client-side, never touches the stored default. The
// real match happens again server-side on send (Chat::ProxyResolver.resolve),
// this is just a preview.
//
// It also keeps an unsent message as a draft for its channel (see
// chat_drafts.js), so going somewhere else and coming back doesn't lose it.
// The textarea's data-draft-key says which draft is its own.
//
// Usage: wrap the whole `.composer` block with data: { controller: "composer" },
// with data-composer-target="form"/"textarea" on the message form/textarea,
// "triggerAvatar"/"triggerName"/"triggerPronouns" on the posting-as pill's
// avatar/name/pronouns, and "option" (plus data-prefix/data-suffix/data-name)
// on each profile/group in the posting-as picker.
export default class extends Controller {
  static targets = [ "form", "textarea", "triggerAvatar", "triggerName", "triggerPronouns", "option" ]

  // Rather than caching the "default" trigger HTML once in connect(), track
  // it via Stimulus's target lifecycle callbacks below — switching who's
  // posting via the picker turbo_stream-replaces just the trigger (see
  // Chat::ChannelDefaultPostablesController#update), which doesn't reconnect
  // this controller, so a one-time connect()-time cache would go stale the
  // moment you switched and then kept typing: the next keystroke with no
  // bracket match would revert the pill to whoever was selected when the
  // page first loaded, not the one you just switched to.
  // Target[Connected] fires on every genuine node replacement (including
  // ours) but not on the preview's in-place innerHTML mutations below, so
  // the cache only ever reflects the real, server-confirmed default.
  triggerAvatarTargetConnected(element) {
    this.defaultAvatarHTML = element.innerHTML
  }

  triggerNameTargetConnected(element) {
    this.defaultNameHTML = element.innerHTML
  }

  triggerPronounsTargetConnected(element) {
    this.defaultPronounsHTML = element.innerHTML
    this.defaultPronounsHidden = element.hidden
  }

  // Runs on connect too (not just input) so a validation-error re-render —
  // which comes back with the rejected body still filled in — starts at the
  // right height instead of the one-line default.
  textareaTargetConnected(element) {
    this.restoreDraft(element)
    this.autoGrow()
  }

  restoreDraft(element) {
    const key = element.dataset.draftKey
    // Turbo's preview of a cached page carries whatever was typed when it was
    // cached, which the draft may have moved on from since
    if (!key || document.documentElement.hasAttribute("data-turbo-preview")) return
    // The page straight after a message was saved says so (see
    // Chat::MessagesController#create). Nothing else clears the draft: a
    // send the server turns away (too fast, or no longer a member) redirects
    // just like one it saves, so the browser can't tell them apart. Taken off
    // the page once used, so Turbo's cached copy can't clear a later draft.
    if (element.dataset.draftSent === "true") {
      delete element.dataset.draftSent
      clearDraft(key)
      return
    }
    // A validation-error re-render comes back with the rejected message, which
    // is the draft now
    if (element.value) {
      saveDraft(key, element.value)
      return
    }

    const draft = loadDraft(key)
    if (!draft) return
    element.value = draft
    // Once the posting-as picker's targets have connected too
    requestAnimationFrame(() => this.detectProxy())
  }

  saveDraft() {
    const key = this.textareaTarget.dataset.draftKey
    if (key) saveDraft(key, this.textareaTarget.value)
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    // Already handled — the emote autocomplete menu (emote_input_controller.js)
    // claims Enter to insert the highlighted emote while it's open.
    if (event.defaultPrevented) return

    event.preventDefault()
    this.formTarget.requestSubmit()
  }

  // Grows the textarea to fit its content, from one line up to the six-line
  // cap set by max-height in CSS — past that, min-height/max-height clamp the
  // element and its own overflow-y: auto takes over scrolling.
  autoGrow() {
    const el = this.textareaTarget
    el.style.height = "auto"
    el.style.height = `${el.scrollHeight}px`
  }

  detectProxy() {
    if (!this.hasTriggerAvatarTarget || !this.hasTriggerNameTarget) return

    const body = this.textareaTarget.value
    const match = this.matchProxy(body)

    if (match) {
      const avatar = match.option.querySelector(".avatar")
      if (avatar) this.triggerAvatarTarget.replaceChildren(avatar.cloneNode(true))
      const name = match.option.querySelector(".profile-picker__option-name")
      if (name) this.triggerNameTarget.innerHTML = name.innerHTML
      if (this.hasTriggerPronounsTarget) {
        const pronouns = match.option.querySelector(".profile-picker__option-pronouns")
        this.triggerPronounsTarget.innerHTML = pronouns ? pronouns.innerHTML : ""
        this.triggerPronounsTarget.hidden = !pronouns
      }
    } else {
      this.triggerAvatarTarget.innerHTML = this.defaultAvatarHTML
      this.triggerNameTarget.innerHTML = this.defaultNameHTML
      if (this.hasTriggerPronounsTarget) {
        this.triggerPronounsTarget.innerHTML = this.defaultPronounsHTML
        this.triggerPronounsTarget.hidden = this.defaultPronounsHidden
      }
    }
  }

  // Mirrors Chat::ProxyResolver.resolve (app/models/chat/proxy_resolver.rb)
  // — exact (case-sensitive) prefix/suffix match, longest (most specific)
  // brackets win. Case-sensitive deliberately: "guy:" and "GUY:" can
  // identify two different profiles or groups.
  matchProxy(body) {
    let best = null

    this.optionTargets.forEach((option) => {
      const prefix = option.dataset.prefix || ""
      const suffix = option.dataset.suffix || ""
      if (!prefix && !suffix) return
      if (body.length < prefix.length + suffix.length) return

      const bodyPrefix = body.slice(0, prefix.length)
      if (bodyPrefix !== prefix) return

      if (suffix) {
        const bodySuffix = body.slice(body.length - suffix.length)
        if (bodySuffix !== suffix) return
      }

      // Deliberately not requiring non-blank content here, unlike
      // Chat::ProxyResolver.resolve: the preview should switch the instant the
      // brackets themselves match (e.g. right after typing "arki:"), not wait
      // for the first character of the actual message. The real send-time
      // match still requires content, so an empty send falls back to the
      // real default rather than posting a blank message as the wrong profile.
      const specificity = prefix.length + suffix.length
      if (!best || specificity > best.specificity) best = { option, specificity }
    })

    return best
  }
}
