export function WaveformVisual() {
  const barCount = 48;
  return (
    <div className="mt-16 flex w-full max-w-2xl flex-col items-center gap-10 sm:mt-20">
      <div
        className="flex h-24 w-full items-end justify-center gap-1 px-4 text-zinc-300 dark:text-zinc-600"
        aria-hidden
      >
        {Array.from({ length: barCount }).map((_, i) => (
          <span
            key={i}
            className="wave-bar block h-24 w-1 max-w-[4px] shrink-0 rounded-full bg-current sm:w-[5px]"
            style={{
              animationDelay: `${i * 0.055}s`,
            }}
          />
        ))}
      </div>

      <div className="relative h-24 w-full max-w-2xl overflow-hidden rounded-sm">
        <svg
          className="h-full w-full text-zinc-300/90 dark:text-zinc-600/90"
          viewBox="0 0 800 64"
          preserveAspectRatio="none"
          aria-hidden
        >
          <defs>
            <linearGradient
              id="wave-fade-hero"
              x1="0%"
              y1="0%"
              x2="100%"
              y2="0%"
            >
              <stop offset="0%" stopColor="currentColor" stopOpacity="0" />
              <stop
                offset="40%"
                stopColor="currentColor"
                stopOpacity="0.45"
              />
              <stop
                offset="60%"
                stopColor="currentColor"
                stopOpacity="0.45"
              />
              <stop offset="100%" stopColor="currentColor" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d="M0,32 C50,8 100,56 150,32 S250,8 300,32 S400,56 450,32 S550,8 600,32 S700,56 800,32"
            fill="none"
            stroke="url(#wave-fade-hero)"
            strokeWidth="1.15"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
            className="wave-stroke-dash"
          />
          <path
            d="M0,40 C60,18 120,52 180,40 S300,18 360,40 S480,52 540,40 S660,18 720,40 S780,52 800,40"
            fill="none"
            stroke="currentColor"
            strokeOpacity="0.22"
            strokeWidth="0.95"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
            className="wave-stroke-dash wave-stroke-dash--slow"
          />
        </svg>
      </div>
    </div>
  );
}
