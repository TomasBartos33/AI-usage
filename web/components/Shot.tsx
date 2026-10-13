/* Light/dark screenshot pair that follows the system appearance. */
export function Shot({ name, alt, width, height, className = "" }: {
  name: string; alt: string; width: number; height: number; className?: string;
}) {
  return (
    <picture>
      <source srcSet={`/shots/${name}-dark.png`} media="(prefers-color-scheme: dark)" />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`/shots/${name}-light.png`} alt={alt} width={width} height={height} className={className} />
    </picture>
  );
}
