// Single place to edit. The download URL always points at the newest GitHub
// release asset, so publishing a new release updates the site with no rebuild.
const REPO = "https://github.com/TomasBartos33/AI-usage";

export const SITE = {
  repo: REPO,
  download: `${REPO}/releases/latest/download/AI-usage-macOS.zip`,
  releases: `${REPO}/releases/latest`,
  tagline: "A native macOS menu bar app that shows your OpenAI Codex and Anthropic Claude Code usage limits at a glance.",
  installCommand: "xattr -dr com.apple.quarantine /Applications/AI-usage.app",
};
