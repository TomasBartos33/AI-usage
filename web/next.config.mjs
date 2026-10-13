// Static export: `npm run build` writes a plain site to ./out that any static
// host (GitHub Pages, Vercel, Netlify, S3) can serve. No server, nothing to maintain.
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
};
export default nextConfig;
