/* Always shows the light screenshot. */
export function Shot({ name, alt, width, height, className = "" }: {
  name: string; alt: string; width: number; height: number; className?: string;
}) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={`/shots/${name}-light.png`} alt={alt} width={width} height={height} className={className} />
  );
}
