import { Nav } from "@/components/Nav";
import { Shot } from "@/components/Shot";
import { MenuBar } from "@/components/MenuBar";
import { CopyCommand } from "@/components/CopyCommand";
import { SITE } from "@/lib/site";

const FEATURES = [
  {
    title: "Always in view",
    body: "Your 5-hour and weekly usage sit in the menu bar as live percentages. No tab, no terminal, no guessing.",
  },
  {
    title: "Zero tokens spent",
    body: "It never runs a model to ask about itself. Only local telemetry and account metadata the tools already expose.",
  },
  {
    title: "Private by design",
    body: "No analytics, no telemetry, no backend. Prompts and transcripts are never uploaded, logged or stored.",
  },
  {
    title: "Truly native",
    body: "Pure SwiftUI. Follows light and dark menu bars, stays out of the Dock and sips resources in the background.",
  },
  {
    title: "Make it yours",
    body: "Choose providers, order, icon, values and reset countdowns. Changes apply instantly.",
  },
  {
    title: "Resets at a glance",
    body: "See exactly when each window refills, like “resets in 2h 14m at 13:54”, in 24-hour time.",
  },
];

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        {/* Hero */}
        <section className="mx-auto max-w-[1024px] px-5 pb-10 pt-32 text-center sm:pt-40">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/app-icon.png"
            alt="AI-usage app icon"
            width={112}
            height={112}
            className="reveal mx-auto rounded-[26px] shadow-[0_20px_40px_-12px_rgba(0,0,0,0.35)]"
          />
          <h1
            className="reveal mx-auto mt-8 text-[2.75rem] font-semibold leading-[1.05] tracking-[-0.03em] sm:text-7xl"
            style={{ animationDelay: ".08s" }}
          >
            Your AI limits.
            <br />
            At a glance.
          </h1>
          <p
            className="reveal mx-auto mt-6 max-w-[34rem] text-xl leading-snug text-fg2 sm:text-2xl"
            style={{ animationDelay: ".16s" }}
          >
            OpenAI Codex and Anthropic Claude Code usage, live in your Mac menu
            bar.
          </p>
          <div
            className="reveal mt-9 flex flex-col items-center justify-center gap-1 sm:flex-row sm:gap-4"
            style={{ animationDelay: ".24s" }}
          >
            <a href={SITE.download} className="btn btn-primary">
              Download for Mac
            </a>
            <a href={SITE.repo} className="btn btn-secondary">
              View on GitHub <span aria-hidden>›</span>
            </a>
          </div>
          <p
            className="reveal mt-3 text-sm text-fg2"
            style={{ animationDelay: ".3s" }}
          >
            Free and open source · macOS 14 or later · Apple silicon and Intel
          </p>
        </section>

        {/* Product shot: a menu bar with the popover hanging from it */}
        <section
          aria-label="Preview"
          className="mx-auto max-w-[1024px] px-5 pb-24 pt-10"
        >
          <div
            className="reveal isolate overflow-hidden rounded-xl bg-gradient-to-b from-[#7aa7ff] via-[#a78bfa] to-[#f0abfc] shadow-[0_40px_80px_-30px_rgba(0,0,0,0.45)] dark:from-[#1d3a8a] dark:via-[#4c1d95] dark:to-[#831843]"
            style={{ animationDelay: ".35s" }}
          >
            <MenuBar />
            <div className="flex justify-center px-5 pb-12 pt-6 sm:justify-end sm:pr-[12%]">
              <Shot
                name="panel"
                alt="The AI-usage detail panel with Codex and Claude Code usage bars"
                width={600}
                height={1371}
                className="w-[300px] rounded-[10px] shadow-[0_30px_60px_-15px_rgba(0,0,0,0.5)]"
              />
            </div>
          </div>
        </section>

        {/* Features */}
        <section id="features" className="bg-alt py-24">
          <div className="mx-auto max-w-[1024px] px-5">
            <h2 className="max-w-[18ch] text-4xl font-semibold leading-[1.08] tracking-[-0.025em] sm:text-6xl">
              Know before you hit the wall.
            </h2>
            <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {FEATURES.map((f) => (
                <article key={f.title} className="rounded-3xl bg-card p-8 ">
                  <h3 className="text-xl font-semibold tracking-tight">
                    {f.title}
                  </h3>
                  <p className="mt-3 leading-relaxed text-fg2">{f.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        {/* Providers */}
        <section className="py-24 text-center">
          <div className="mx-auto max-w-[1024px] px-5">
            <h2 className="mx-auto max-w-[16ch] text-4xl font-semibold leading-[1.08] tracking-[-0.025em] sm:text-6xl">
              Two tools. One glance.
            </h2>
            <p className="mx-auto mt-6 max-w-[36rem] text-xl text-fg2">
              Codex and Claude Code side by side, with plan, model, context,
              tokens and last activity one click away.
            </p>
            <div className="mt-12 grid gap-4 text-left sm:grid-cols-2">
              {[
                {
                  name: "OpenAI Codex",
                  detail:
                    "Reads session logs and the Codex app-server for rate limits, plan and credits.",
                },
                {
                  name: "Claude Code",
                  detail:
                    "Uses your existing Claude Code sign-in to read live limits. No extra login.",
                },
              ].map((p) => (
                <div key={p.name} className="rounded-3xl bg-alt p-8">
                  <h3 className="text-2xl font-semibold tracking-tight">
                    {p.name}
                  </h3>
                  <p className="mt-3 leading-relaxed text-fg2">{p.detail}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Install */}
        <section id="install" className="bg-alt py-24">
          <div className="mx-auto max-w-[680px] px-5 text-center">
            <h2 className="text-4xl font-semibold leading-[1.08] tracking-[-0.025em] sm:text-6xl">
              Get it in a minute.
            </h2>
            <ol className="mt-12 space-y-10 text-left">
              <Step n={1} title="Download and move to Applications">
                Unzip{" "}
                <code className="font-mono text-[0.9em]">
                  AI-usage-macOS.zip
                </code>{" "}
                and drag{" "}
                <code className="font-mono text-[0.9em]">AI-usage.app</code>{" "}
                into your Applications folder.
                <div className="mt-5">
                  <a
                    href={SITE.download}
                    className="btn btn-primary !px-5 !py-3 !text-base"
                  >
                    Download for Mac
                  </a>
                </div>
              </Step>
              <Step n={2} title="Allow it to open once">
                The app is not notarized, so macOS blocks a plain double-click.
                Run this in Terminal one time:
                <div className="mt-5">
                  <CopyCommand command={SITE.installCommand} />
                </div>
              </Step>
              <Step n={3} title="Open AI-usage">
                Your limits appear in the menu bar. Click for details, or open
                Settings to make it yours.
              </Step>
            </ol>
          </div>
        </section>
      </main>

      <footer className="border-t border-line py-10 text-xs text-fg2">
        <div className="mx-auto flex max-w-[1024px] flex-col gap-3 px-5 sm:flex-row sm:items-center sm:justify-between">
          <p>
            AI-usage is an independent project. Not affiliated with or endorsed
            by OpenAI or Anthropic. All trademarks belong to their owners.
          </p>
          <nav className="flex gap-5">
            <a href={SITE.repo} className="hover:text-fg">
              GitHub
            </a>
            <a href={SITE.releases} className="hover:text-fg">
              Releases
            </a>
            <a href={`${SITE.repo}/issues`} className="hover:text-fg">
              Issues
            </a>
          </nav>
        </div>
      </footer>
    </>
  );
}

function Step({
  n,
  title,
  children,
}: {
  n: number;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <li className="flex gap-5">
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent text-sm font-semibold text-white">
        {n}
      </span>
      <div className="min-w-0 flex-1">
        <h3 className="text-xl font-semibold tracking-tight">{title}</h3>
        <div className="mt-2 leading-relaxed text-fg2">{children}</div>
      </div>
    </li>
  );
}
