// The game's cues: the animations a move fires (confetti, defeat, explosion, shake).
// The server pushes a "cues" event; the hook plays each cue on its element (the game page).
import confetti from "../vendor/canvas-confetti"

const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

// A full-screen overlay that removes itself. Its look lives in app.css.
const overlay = (className) => {
  const el = document.createElement("div")
  el.className = className
  document.body.appendChild(el)
  return el
}

// Bursts from all four corners, aimed at the centre.
const fireConfetti = () => {
  if (reducedMotion()) return
  const corners = [
    {origin: {x: 0, y: 1}, angle: 60},
    {origin: {x: 1, y: 1}, angle: 120},
    {origin: {x: 0, y: 0}, angle: -60},
    {origin: {x: 1, y: 0}, angle: -120},
  ]
  for (const {origin, angle} of corners) {
    confetti({particleCount: 60, spread: 70, startVelocity: 55, angle, origin})
  }
}

// A short shake plus a red vignette that lingers for 5 seconds.
const fireDefeat = (target) => {
  const flash = overlay("defeat-flash")
  const FLASH_MS = 5000
  if (reducedMotion()) {
    flash.style.opacity = "0.6"
    setTimeout(() => flash.remove(), FLASH_MS)
    return
  }
  const anim = flash.animate(
    [{opacity: 0}, {opacity: 1, offset: 0.06}, {opacity: 1, offset: 0.85}, {opacity: 0}],
    {duration: FLASH_MS, easing: "ease-out"},
  )
  anim.onfinish = anim.oncancel = () => flash.remove()
  target.animate(
    [
      {transform: "translateX(0)"},
      {transform: "translateX(-8px)", offset: 0.2},
      {transform: "translateX(7px)", offset: 0.4},
      {transform: "translateX(-5px)", offset: 0.6},
      {transform: "translateX(3px)", offset: 0.8},
      {transform: "translateX(0)"},
    ],
    {duration: 400, easing: "ease-in-out"},
  )
}

// A white flash that burns through yellow, orange and red while it flickers, plus a hard
// shake that dies down.
const fireExplosion = (target) => {
  const flash = overlay("explosion-flash")
  if (reducedMotion()) {
    flash.style.opacity = "0.5"
    setTimeout(() => flash.remove(), 600)
    return
  }
  const DURATION_MS = 3000
  const anim = flash.animate(
    [
      {opacity: 1, filter: "brightness(3) saturate(0.3)"},
      {opacity: 1, filter: "brightness(2) saturate(0.8)", offset: 0.03},
      {opacity: 0.55, filter: "brightness(1.5) hue-rotate(0deg)", offset: 0.07},
      {opacity: 0.95, filter: "brightness(1.4) hue-rotate(-5deg)", offset: 0.11},
      {opacity: 0.5, filter: "brightness(1.2) hue-rotate(-10deg)", offset: 0.16},
      {opacity: 0.85, filter: "brightness(1.1) hue-rotate(-15deg)", offset: 0.22},
      {opacity: 0.6, filter: "brightness(1) hue-rotate(-20deg)", offset: 0.3},
      {opacity: 0.7, filter: "brightness(1) hue-rotate(-30deg)", offset: 0.4},
      {opacity: 0, filter: "brightness(0.8) hue-rotate(-40deg)"},
    ],
    {duration: DURATION_MS, easing: "ease-out"},
  )
  anim.onfinish = anim.oncancel = () => flash.remove()
  const STEPS = 36
  target.animate(
    Array.from({length: STEPS + 1}, (_, i) => {
      const decay = (1 - i / STEPS) ** 2
      const sign = i % 2 ? 1 : -1
      const x = sign * 28 * decay
      const y = -sign * 18 * decay * (i % 3 ? 1 : -1)
      return {transform: `translate(${x}px, ${y}px) rotate(${sign * 2 * decay}deg)`}
    }),
    {duration: DURATION_MS, easing: "linear"},
  )
}

// The page shakes sideways for about a second.
const fireShake = (target) => {
  if (reducedMotion()) return
  target.animate(
    [
      {transform: "translateX(0)"},
      {transform: "translateX(-9px)", offset: 0.1},
      {transform: "translateX(8px)", offset: 0.2},
      {transform: "translateX(-7px)", offset: 0.3},
      {transform: "translateX(6px)", offset: 0.45},
      {transform: "translateX(-4px)", offset: 0.6},
      {transform: "translateX(3px)", offset: 0.75},
      {transform: "translateX(-1px)", offset: 0.9},
      {transform: "translateX(0)"},
    ],
    {duration: 1000, easing: "ease-in-out"},
  )
}

const CUES = {confetti: fireConfetti, defeat: fireDefeat, explosion: fireExplosion, shake: fireShake}

export const Cues = {
  mounted() {
    this.handleEvent("cues", ({cues}) => cues.forEach((cue) => CUES[cue]?.(this.el)))
  },
}
