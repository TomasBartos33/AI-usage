"use client";
import { useEffect, useState } from "react";
import { FaApple } from "react-icons/fa";
import { RiClaudeFill, RiOpenaiFill } from "react-icons/ri";

// macOS shows e.g. "Tue 13 Oct  11:55:35" in 24-hour time.
function formatDateTime(d: Date) {
  const day = d.toLocaleDateString("en-GB", { weekday: "short" });
  const date = d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
  });
  const time = d.toLocaleTimeString("en-GB", { hour12: false });
  return `${day} ${date}  ${time}`;
}

function formatDate(d: Date) {
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
}

/** A mock macOS menu bar: Apple logo on the left, AI-usage and a live clock on the right. */
export function MenuBar() {
  // Rendered after mount so server and client markup match.
  const [now, setNow] = useState({ date: "", dateTime: "" });
  useEffect(() => {
    const tick = () => {
      const date = new Date();
      setNow({ date: formatDate(date), dateTime: formatDateTime(date) });
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="flex h-8 items-center justify-between px-4 text-[13px] font-medium text-white">
      <div className="flex items-center gap-3">
        <FaApple className="size-[15px]" aria-label="Apple" />
        <span className="hidden sm:block text-md font-bold">AI-usage</span>
      </div>
      <div className="flex items-center gap-2">
        <div
          className="flex items-center gap-3 tabular-nums bg-white/20 rounded-full px-2"
          aria-label="AI-usage: OpenAI Codex 72%, Claude Code 41%"
        >
          <span className="flex items-center gap-1.5">
            <RiOpenaiFill className="size-[15px]" aria-hidden />
            72%
          </span>
          <span className="flex items-center gap-1.5 opacity-50">
            <RiClaudeFill className="size-[15px]" aria-hidden />
            41%
          </span>
        </div>
        <time className="text-right tabular-nums" suppressHydrationWarning>
          <span className="sm:hidden">{now.date || " "}</span>
          <span className="hidden sm:inline">{now.dateTime || " "}</span>
        </time>
      </div>
    </div>
  );
}
