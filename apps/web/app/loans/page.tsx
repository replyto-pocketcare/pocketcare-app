import { redirect } from "next/navigation";

// Loans & recurring commitments merged into the unified Planned Cashflow hub (BETA).
// Kept as a redirect so existing links still land in the right place.
export default function LoansRedirect() {
  redirect("/cashflow");
}
