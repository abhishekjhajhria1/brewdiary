// The icon set — Phosphor Icons (MIT, https://phosphoricons.com), bundled as fonts
// in assets/fonts (see assets/fonts/PHOSPHOR_LICENSE.txt). Only the glyphs named
// here ship: release builds tree-shake the fonts down to the icons in use.
//
// Codepoints are Phosphor v2.1's (the same font as the phosphor_flutter 2.1.0 and
// @phosphor-icons/web 2.1 packages). To add an icon, look its codepoint up in the
// web package's CSS — `.ph-<kebab-name>:before { content: "\eXXX" }` in
// src/regular/style.css (fill/, bold/ for those weights) — and add a line below.
// (phosphor_flutter itself can't be used: it subclasses IconData, which is final
// in current Flutter.)
import 'package:flutter/widgets.dart';

/// Regular weight — the default for every icon.
abstract final class Ph {
  static const arrowCounterClockwise = IconData(0xe038, fontFamily: 'Phosphor');
  static const arrowLeft = IconData(0xe058, fontFamily: 'Phosphor');
  static const arrowRight = IconData(0xe06c, fontFamily: 'Phosphor');
  static const arrowUp = IconData(0xe08e, fontFamily: 'Phosphor');
  static const arrowUpRight = IconData(0xe092, fontFamily: 'Phosphor');
  static const arrowsClockwise = IconData(0xe094, fontFamily: 'Phosphor');
  static const at = IconData(0xe0ac, fontFamily: 'Phosphor');
  static const beerBottle = IconData(0xe7b0, fontFamily: 'Phosphor');
  static const beerStein = IconData(0xeb62, fontFamily: 'Phosphor');
  static const bell = IconData(0xe0ce, fontFamily: 'Phosphor');
  static const bellRinging = IconData(0xe5e8, fontFamily: 'Phosphor');
  static const bellSlash = IconData(0xe0d4, fontFamily: 'Phosphor');
  static const bookOpen = IconData(0xe0e6, fontFamily: 'Phosphor');
  static const brandy = IconData(0xe6b4, fontFamily: 'Phosphor');
  static const broom = IconData(0xec54, fontFamily: 'Phosphor');
  static const calendarBlank = IconData(0xe10a, fontFamily: 'Phosphor');
  static const calendarCheck = IconData(0xe712, fontFamily: 'Phosphor');
  static const calendarPlus = IconData(0xe714, fontFamily: 'Phosphor');
  static const camera = IconData(0xe10e, fontFamily: 'Phosphor');
  static const carProfile = IconData(0xe8cc, fontFamily: 'Phosphor');
  static const caretDown = IconData(0xe136, fontFamily: 'Phosphor');
  static const caretLeft = IconData(0xe138, fontFamily: 'Phosphor');
  static const caretRight = IconData(0xe13a, fontFamily: 'Phosphor');
  static const caretUp = IconData(0xe13c, fontFamily: 'Phosphor');
  static const champagne = IconData(0xeaca, fontFamily: 'Phosphor');
  static const chartBar = IconData(0xe150, fontFamily: 'Phosphor');
  static const chatCircle = IconData(0xe168, fontFamily: 'Phosphor');
  static const chatText = IconData(0xe17a, fontFamily: 'Phosphor');
  static const chatsCircle = IconData(0xe17e, fontFamily: 'Phosphor');
  static const check = IconData(0xe182, fontFamily: 'Phosphor');
  static const checkCircle = IconData(0xe184, fontFamily: 'Phosphor');
  static const cheers = IconData(0xea4a, fontFamily: 'Phosphor');
  static const cigarette = IconData(0xed90, fontFamily: 'Phosphor');
  static const circle = IconData(0xe18a, fontFamily: 'Phosphor');
  static const clock = IconData(0xe19a, fontFamily: 'Phosphor');
  static const clockCounterClockwise = IconData(0xe1a0, fontFamily: 'Phosphor');
  static const cloudSlash = IconData(0xe1b6, fontFamily: 'Phosphor');
  static const coffee = IconData(0xe1c2, fontFamily: 'Phosphor');
  static const compass = IconData(0xe1c8, fontFamily: 'Phosphor');
  static const confetti = IconData(0xe81a, fontFamily: 'Phosphor');
  static const contactlessPayment = IconData(0xed42, fontFamily: 'Phosphor');
  static const copy = IconData(0xe1ca, fontFamily: 'Phosphor');
  static const crown = IconData(0xe614, fontFamily: 'Phosphor');
  static const dotsThree = IconData(0xe1fe, fontFamily: 'Phosphor');
  static const dotsThreeVertical = IconData(0xe208, fontFamily: 'Phosphor');
  static const downloadSimple = IconData(0xe20c, fontFamily: 'Phosphor');
  static const drop = IconData(0xe210, fontFamily: 'Phosphor');
  static const dropHalf = IconData(0xe566, fontFamily: 'Phosphor');
  static const envelopeSimple = IconData(0xe218, fontFamily: 'Phosphor');
  static const eraser = IconData(0xe21e, fontFamily: 'Phosphor');
  static const export = IconData(0xeaf0, fontFamily: 'Phosphor');
  static const eye = IconData(0xe220, fontFamily: 'Phosphor');
  static const eyeSlash = IconData(0xe224, fontFamily: 'Phosphor');
  static const fileArrowDown = IconData(0xe232, fontFamily: 'Phosphor');
  static const fileArrowUp = IconData(0xe61e, fontFamily: 'Phosphor');
  static const fileText = IconData(0xe23a, fontFamily: 'Phosphor');
  static const fire = IconData(0xe242, fontFamily: 'Phosphor');
  static const flag = IconData(0xe244, fontFamily: 'Phosphor');
  static const flame = IconData(0xe624, fontFamily: 'Phosphor');
  static const gearSix = IconData(0xe272, fontFamily: 'Phosphor');
  static const gift = IconData(0xe276, fontFamily: 'Phosphor');
  static const globe = IconData(0xe288, fontFamily: 'Phosphor');
  static const handHeart = IconData(0xe810, fontFamily: 'Phosphor');
  static const handTap = IconData(0xec90, fontFamily: 'Phosphor');
  static const handWaving = IconData(0xe580, fontFamily: 'Phosphor');
  static const handsClapping = IconData(0xe6a0, fontFamily: 'Phosphor');
  static const hash = IconData(0xe2a2, fontFamily: 'Phosphor');
  static const heart = IconData(0xe2a8, fontFamily: 'Phosphor');
  static const house = IconData(0xe2c2, fontFamily: 'Phosphor');
  static const identificationBadge = IconData(0xe6f6, fontFamily: 'Phosphor');
  static const fingerprint = IconData(0xe23e, fontFamily: 'Phosphor');
  static const identificationCard = IconData(0xe2c8, fontFamily: 'Phosphor');
  static const image = IconData(0xe2ca, fontFamily: 'Phosphor');
  static const images = IconData(0xe836, fontFamily: 'Phosphor');
  static const info = IconData(0xe2ce, fontFamily: 'Phosphor');
  static const key = IconData(0xe2d6, fontFamily: 'Phosphor');
  static const leaf = IconData(0xe2da, fontFamily: 'Phosphor');
  static const lifebuoy = IconData(0xe63a, fontFamily: 'Phosphor');
  static const lightning = IconData(0xe2de, fontFamily: 'Phosphor');
  static const link = IconData(0xe2e2, fontFamily: 'Phosphor');
  static const linkSimple = IconData(0xe2e6, fontFamily: 'Phosphor');
  static const listBullets = IconData(0xe2f2, fontFamily: 'Phosphor');
  static const lock = IconData(0xe2fa, fontFamily: 'Phosphor');
  static const magnifyingGlass = IconData(0xe30c, fontFamily: 'Phosphor');
  static const mapPin = IconData(0xe316, fontFamily: 'Phosphor');
  static const mapTrifold = IconData(0xe31a, fontFamily: 'Phosphor');
  static const martini = IconData(0xe31c, fontFamily: 'Phosphor');
  static const minus = IconData(0xe32a, fontFamily: 'Phosphor');
  static const minusCircle = IconData(0xe32c, fontFamily: 'Phosphor');
  static const money = IconData(0xe588, fontFamily: 'Phosphor');
  static const monitor = IconData(0xe32e, fontFamily: 'Phosphor');
  static const moon = IconData(0xe330, fontFamily: 'Phosphor');
  static const moonStars = IconData(0xe58e, fontFamily: 'Phosphor');
  static const musicNotes = IconData(0xe340, fontFamily: 'Phosphor');
  static const navigationArrow = IconData(0xeade, fontFamily: 'Phosphor');
  static const notePencil = IconData(0xe34c, fontFamily: 'Phosphor');
  static const notebook = IconData(0xe34e, fontFamily: 'Phosphor');
  static const paperPlaneTilt = IconData(0xe398, fontFamily: 'Phosphor');
  static const pencilSimple = IconData(0xe3b4, fontFamily: 'Phosphor');
  static const personSimpleWalk = IconData(0xe73a, fontFamily: 'Phosphor');
  static const phone = IconData(0xe3b8, fontFamily: 'Phosphor');
  static const pintGlass = IconData(0xedd0, fontFamily: 'Phosphor');
  static const plus = IconData(0xe3d4, fontFamily: 'Phosphor');
  static const plusCircle = IconData(0xe3d6, fontFamily: 'Phosphor');
  static const prohibit = IconData(0xe3de, fontFamily: 'Phosphor');
  static const qrCode = IconData(0xe3e6, fontFamily: 'Phosphor');
  static const question = IconData(0xe3e8, fontFamily: 'Phosphor');
  static const receipt = IconData(0xe3ec, fontFamily: 'Phosphor');
  static const scales = IconData(0xe750, fontFamily: 'Phosphor');
  static const sealCheck = IconData(0xe606, fontFamily: 'Phosphor');
  static const shareNetwork = IconData(0xe408, fontFamily: 'Phosphor');
  static const shieldCheck = IconData(0xe40c, fontFamily: 'Phosphor');
  static const signIn = IconData(0xe428, fontFamily: 'Phosphor');
  static const signOut = IconData(0xe42a, fontFamily: 'Phosphor');
  static const slidersHorizontal = IconData(0xe434, fontFamily: 'Phosphor');
  static const smiley = IconData(0xe436, fontFamily: 'Phosphor');
  static const sparkle = IconData(0xe6a2, fontFamily: 'Phosphor');
  static const squaresFour = IconData(0xe464, fontFamily: 'Phosphor');
  static const star = IconData(0xe46a, fontFamily: 'Phosphor');
  static const storefront = IconData(0xe470, fontFamily: 'Phosphor');
  static const sun = IconData(0xe472, fontFamily: 'Phosphor');
  static const tag = IconData(0xe478, fontFamily: 'Phosphor');
  static const target = IconData(0xe47c, fontFamily: 'Phosphor');
  static const teaBag = IconData(0xe8e6, fontFamily: 'Phosphor');
  static const ticket = IconData(0xe490, fontFamily: 'Phosphor');
  static const timer = IconData(0xe492, fontFamily: 'Phosphor');
  static const trash = IconData(0xe4a6, fontFamily: 'Phosphor');
  static const trophy = IconData(0xe67e, fontFamily: 'Phosphor');
  static const uploadSimple = IconData(0xe4c0, fontFamily: 'Phosphor');
  static const user = IconData(0xe4c2, fontFamily: 'Phosphor');
  static const userCheck = IconData(0xeafa, fontFamily: 'Phosphor');
  static const userCircle = IconData(0xe4c4, fontFamily: 'Phosphor');
  static const userMinus = IconData(0xe4ce, fontFamily: 'Phosphor');
  static const userPlus = IconData(0xe4d0, fontFamily: 'Phosphor');
  static const users = IconData(0xe4d6, fontFamily: 'Phosphor');
  static const usersThree = IconData(0xe68e, fontFamily: 'Phosphor');
  static const wallet = IconData(0xe68a, fontFamily: 'Phosphor');
  static const warning = IconData(0xe4e0, fontFamily: 'Phosphor');
  static const warningCircle = IconData(0xe4e2, fontFamily: 'Phosphor');
  static const wine = IconData(0xe6b2, fontFamily: 'Phosphor');
  static const x = IconData(0xe4f6, fontFamily: 'Phosphor');
}

/// Filled — the "selected" state of a tab, a cheered heart.
abstract final class PhFill {
  static const bell = IconData(0xe0ce, fontFamily: 'PhosphorFill');
  static const calendarBlank = IconData(0xe10a, fontFamily: 'PhosphorFill');
  static const checkCircle = IconData(0xe184, fontFamily: 'PhosphorFill');
  static const cheers = IconData(0xea4a, fontFamily: 'PhosphorFill');
  static const confetti = IconData(0xe81a, fontFamily: 'PhosphorFill');
  static const flame = IconData(0xe624, fontFamily: 'PhosphorFill');
  static const gift = IconData(0xe276, fontFamily: 'PhosphorFill');
  static const handsClapping = IconData(0xe6a0, fontFamily: 'PhosphorFill');
  static const heart = IconData(0xe2a8, fontFamily: 'PhosphorFill');
  static const mapPin = IconData(0xe316, fontFamily: 'PhosphorFill');
  static const martini = IconData(0xe31c, fontFamily: 'PhosphorFill');
  static const sparkle = IconData(0xe6a2, fontFamily: 'PhosphorFill');
  static const star = IconData(0xe46a, fontFamily: 'PhosphorFill');
  static const userCircle = IconData(0xe4c4, fontFamily: 'PhosphorFill');
  static const usersThree = IconData(0xe68e, fontFamily: 'PhosphorFill');
}

/// Bold — small glyphs that must read at a glance (send, check).
abstract final class PhBold {
  static const arrowUp = IconData(0xe08e, fontFamily: 'PhosphorBold');
  static const check = IconData(0xe182, fontFamily: 'PhosphorBold');
  static const plus = IconData(0xe3d4, fontFamily: 'PhosphorBold');
  static const x = IconData(0xe4f6, fontFamily: 'PhosphorBold');
}
