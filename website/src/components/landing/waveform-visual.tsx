export function WaveformVisual() {
  const barCount = 36;
  return (
    <div className="mt-14 flex w-full max-w-md flex-col items-center gap-6">
      <div
        className="flex h-14 w-full items-end justify-center gap-[3px] px-2 text-zinc-400 dark:text-zinc-500"
        aria-hidden
      >
        {Array.from({ length: barCount }).map((_, i) => (
          <span
            key={i}
            className="wave-bar block h-14 w-[3px] rounded-full bg-current"
            style={{
              animationDelay: `${i * 0.035}s`,
            }}
          />
        ))}
      </div>

      <div className="relative h-14 w-full max-w-lg overflow-hidden rounded-sm">
        <svg
          className="h-full w-full text-zinc-300 dark:text-zinc-600"
          viewBox="0 0 800 64"
          preserveAspectRatio="none"
          aria-hidden
        >
          <defs>
            <linearGradient
              id="wave-fade"
              x1="0%"
              y1="0%"
              x2="100%"
              y2="0%"
            >
              <stop offset="0%" stopColor="currentColor" stopOpacity="0" />
              <stop offset="35%" stopColor="currentColor" stopOpacity="0.85" />
              <stop offset="65%" stopColor="currentColor" stopOpacity="0.85" />
              <stop offset="100%" stopColor="currentColor" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d="M0,32 C50,8 100,56 150,32 S250,8 300,32 S400,56 450,32 S550,8 600,32 S700,56 800,32"
            fill="none"
            stroke="url(#wave-fade)"
            strokeWidth="1.35"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
            className="wave-stroke-dash"
          />
          <path
            d="M0,40 C60,18 120,52 180,40 S300,18 360,40 S480,52 540,40 S660,18 720,40 S780,52 800,40"
            fill="none"
            stroke="currentColor"
            strokeOpacity="0.35"
            strokeWidth="1"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
            className="wave-stroke-dash wave-stroke-dash--slow"
          />
        </svg>
      </div>
    </div>
  );
}
