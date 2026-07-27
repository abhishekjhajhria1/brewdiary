"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Scroll-entry reveal — the element stays down and dim until it scrolls into view,
 * then rises once and never animates again.
 *
 * HOW IT'S BUILT — one IntersectionObserver per element, disconnected the moment it
 * fires. No scroll listener, no rAF loop, so a page full of these costs nothing while
 * you read. Returns `reduced` too, because a *delay* is not a duration: the global
 * `prefers-reduced-motion` rule in globals.css collapses transition-DURATION but leaves
 * transition-DELAY alone, so a staggered wave would still stagger — the caller has to
 * zero its own delays, and this tells it when.
 *
 * THE FAILSAFE — content that starts invisible and waits for JS is content that can
 * disappear forever if the observer never fires (an old browser, a layout that never
 * intersects, an aggressive extension). So there's a hard timeout: whatever happens,
 * everything is visible ~1.2s after mount. A reveal is a flourish; it is never allowed
 * to be the reason someone can't read the page.
 *
 * INSPIRED BY — the house anti-slop rule for scroll motion (translateY ~12px + opacity,
 * ~600ms cubic-bezier(0.16, 1, 0.3, 1), stagger ~80ms). Nothing loops, nothing bounces.
 */
export function useReveal<T extends HTMLElement>(threshold = 0.12) {
  const ref = useRef<T | null>(null);
  const [shown, setShown] = useState(false);
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (mq.matches || typeof IntersectionObserver === "undefined") {
      setReduced(mq.matches);
      setShown(true);
      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setShown(true);
          io.disconnect();
        }
      },
      { threshold, rootMargin: "0px 0px -8% 0px" },
    );
    io.observe(el);

    const failsafe = window.setTimeout(() => setShown(true), 1200);
    return () => {
      io.disconnect();
      window.clearTimeout(failsafe);
    };
  }, [threshold]);

  return { ref, shown, reduced };
}
