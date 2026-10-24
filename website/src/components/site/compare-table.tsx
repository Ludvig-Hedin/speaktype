import type { Dictionary } from "@/i18n";

type Row = Dictionary["compare"]["rows"][number];

/** Three-column table from `sm` up; on phones each row stacks its label above the two values. */
export function CompareTable({
  t,
  rows,
}: {
  t: Pick<Dictionary["compare"], "colUs" | "colThem">;
  rows: Row[];
}) {
  return (
    <>
      <table className="hidden w-full border-collapse text-left text-[15px] sm:table">
        <thead>
          <tr className="text-sm">
            <th scope="col" className="w-[38%] pb-4 font-normal">
              <span className="sr-only">Feature</span>
            </th>
            <th scope="col" className="pb-4 font-semibold">
              {t.colUs}
            </th>
            <th scope="col" className="pb-4 font-medium text-muted-foreground">
              {t.colThem}
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.label} className="border-t border-border">
              <th scope="row" className="py-4 pr-6 font-normal text-muted-foreground">
                {r.label}
              </th>
              <td className="py-4 pr-6 font-medium">{r.us}</td>
              <td className="py-4 text-foreground/60">{r.them}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <dl className="text-[15px] sm:hidden">
        <div className="grid grid-cols-2 gap-4 pb-3 text-sm">
          <span className="font-semibold">{t.colUs}</span>
          <span className="font-medium text-muted-foreground">{t.colThem}</span>
        </div>
        {rows.map((r) => (
          <div key={r.label} className="border-t border-border py-3.5">
            <dt className="text-sm text-muted-foreground">{r.label}</dt>
            <dd className="mt-1 grid grid-cols-2 gap-4">
              <span className="font-medium">{r.us}</span>
              <span className="text-foreground/60">{r.them}</span>
            </dd>
          </div>
        ))}
      </dl>
    </>
  );
}
