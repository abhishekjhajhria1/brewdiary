"use client";

import { useEffect, useRef } from "react";

/** Gentle scroll-linked drift — the element trails the scroll by a few pixels,
 *  giving the mosaic a layer of depth without spectacle. Transform-only,
 *  rAF-throttled, capped at ±maxPx, and inert under prefers-reduced-motion
 *  (honored live, not just at mount). The heavy multi-layer parallax look is
 *  deliberately out of scope — the house style is calm; see the north star. */
export function useParallax<T extends HTMLElement>(maxPx = 12, factor = 0.06) {
  const ref = useRef<T | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    let raf = 0;
    let cur = 0; // current applied translation — subtracted so the rect read doesn't feed back
    let attached = false;

    const update = () => {
      raf = 0;
      const r = el.getBoundingClientRect();
      const untransformedMid = r.top - cur + r.height / 2;
      const delta = (untransformedMid - window.innerHeight / 2) * factor;
      cur = Math.max(-maxPx, Math.min(maxPx, delta));
      el.style.transform = `translate3d(0, ${cur.toFixed(1)}px, 0)`;
    };
    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(update);
    };
    const attach = () => {
      if (attached) return;
      attached = true;
      update();
      window.addEventListener("scroll", schedule, { passive: true });
      window.addEventListener("resize", schedule, { passive: true });
    };
    const detach = () => {
      if (!attached) return;
      attached = false;
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      cur = 0;
      el.style.transform = "";
    };

    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => (mq.matches ? detach() : attach());
    sync();
    mq.addEventListener("change", sync);
    return () => {
      mq.removeEventListener("change", sync);
      detach();
    };
  }, [maxPx, factor]);

  return ref;
}
