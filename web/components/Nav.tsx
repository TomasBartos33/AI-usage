import { SITE } from "@/lib/site";

export function Nav() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 ">
      <nav className="mx-auto flex h-12 max-w-[1024px] items-center justify-between px-5 text-xs">
        <a href="#" className="flex items-center gap-2 text-sm font-semibold">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/app-icon.png"
            alt=""
            width={30}
            height={30}
            className="rounded-[5px]"
          />
          AI-usage
        </a>
        <div className="flex items-center gap-6 text-fg2">
          <a
            href="#features"
            className="hidden transition-colors hover:text-fg sm:block"
          >
            Features
          </a>
          <a
            href="#providers"
            className="hidden transition-colors hover:text-fg sm:block"
          >
            Providers
          </a>
          <a
            href="#install"
            className="hidden transition-colors hover:text-fg sm:block"
          >
            Install
          </a>
          <a
            href={SITE.repo}
            className="hidden transition-colors hover:text-fg sm:block"
          >
            GitHub
          </a>
          <a href={SITE.download} className="btn btn-primary btn-sm">
            Download
          </a>
        </div>
      </nav>
    </header>
  );
}
