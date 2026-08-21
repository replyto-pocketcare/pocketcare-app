import { redirect } from "next/navigation";

// Subscriptions are managed as recurring payments. This redirect predates that
// move (it used to point at the Planned Cashflow hub, now removed) and is kept
// so old links — dashboard tiles, insights CTAs, bookmarks — still land.
export default function SubscriptionsRedirect() {
  redirect("/recurring");
}
