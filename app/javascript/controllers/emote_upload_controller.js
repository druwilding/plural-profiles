import { Controller } from "@hotwired/stimulus"

// The emote upload form: accepts dropped files, and converts SVGs to PNG in
// the browser before they're uploaded. The server doesn't read SVGs itself
// (libvips' SVG loader isn't hardened against malicious files), so an SVG is
// drawn at SVG_SIZE on a canvas and replaced with the PNG, keeping its name.
const SVG_SIZE = 256

export default class extends Controller {
  static targets = [ "input", "dropzone", "status", "submit" ]

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("emote-upload__dropzone--active")
  }

  dragLeave() {
    this.dropzoneTarget.classList.remove("emote-upload__dropzone--active")
  }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    if (!event.dataTransfer?.files.length) return

    this.inputTarget.files = event.dataTransfer.files
    this.convert()
  }

  async convert() {
    const files = [ ...this.inputTarget.files ]
    const svgs = files.filter(isSvg)
    if (svgs.length === 0) {
      this.statusTarget.textContent = files.length ? `${files.length} ${files.length === 1 ? "file" : "files"} chosen.` : ""
      return
    }

    this.converting = true
    this.submitTarget.disabled = true
    this.statusTarget.textContent = `Converting ${svgs.length} SVG ${svgs.length === 1 ? "file" : "files"} to PNG…`

    let failed = 0
    const converted = await Promise.all(files.map(async (file) => {
      if (!isSvg(file)) return file
      try {
        return await svgToPng(file)
      } catch {
        failed += 1
        return file
      }
    }))

    const transfer = new DataTransfer()
    converted.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files

    this.converting = false
    this.submitTarget.disabled = false
    this.statusTarget.textContent = failed
      ? `${failed} SVG ${failed === 1 ? "file" : "files"} couldn't be converted and will be skipped.`
      : `${files.length} ${files.length === 1 ? "file" : "files"} chosen. SVGs were converted to PNG.`
  }

  submit(event) {
    if (this.converting) event.preventDefault()
  }
}

function isSvg(file) {
  return file.type === "image/svg+xml" || /\.svg$/i.test(file.name)
}

// Draws the SVG so its longest side is SVG_SIZE, keeping its shape. An SVG
// with no size of its own is drawn square.
async function svgToPng(file) {
  const url = URL.createObjectURL(file)
  try {
    const image = new Image()
    image.src = url
    await image.decode()

    const width = image.naturalWidth || SVG_SIZE
    const height = image.naturalHeight || SVG_SIZE
    const scale = SVG_SIZE / Math.max(width, height)
    const canvas = document.createElement("canvas")
    canvas.width = Math.max(1, Math.round(width * scale))
    canvas.height = Math.max(1, Math.round(height * scale))
    canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height)

    const png = await new Promise((resolve, reject) => {
      canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("Couldn't draw the SVG"))), "image/png")
    })
    return new File([ png ], file.name.replace(/\.svg$/i, "") + ".png", { type: "image/png" })
  } finally {
    URL.revokeObjectURL(url)
  }
}
