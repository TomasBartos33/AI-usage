"use client";
import { useState } from "react";

export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard unavailable: the command stays selectable */
    }
  }
  return (
    <div className="flex items-center gap-3 rounded-3xl border border-line bg-white p-2 pl-5 text-left">
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap font-mono text-[0.8125rem] text-fg">
        {command}
      </code>
      <button
        onClick={copy}
        className="btn btn-gray shrink-0"
        aria-live="polite"
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
