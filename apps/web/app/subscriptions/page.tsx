import { redirect } from "next/navigation";

// Subscriptions merged into the unified Planned Cashflow hub (BETA).
// Kept as a redirect so existing links (dashboard tiles, insights CTAs) still land.
export default function SubscriptionsRedirect() {
  redirect("/cashflow");
}
