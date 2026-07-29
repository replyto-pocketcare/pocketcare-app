"use client";

/**
 * Groups & trips merged into Splits (`/friends`), which already carried the
 * group tiles, the person sheet and settle-up. This route now redirects there
 * so existing links, bookmarks and notification deep links keep working.
 *
 * `/groups/[id]` is unaffected — the group detail page is still its own route.
 */

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Spinner } from "../../src/ui/Spinner";

export default function GroupsRedirectPage() {
  const router = useRouter();
  useEffect(() => { router.replace("/friends"); }, [router]);
  return <div style={{ minHeight: "50vh", display: "grid", placeItems: "center" }}><Spinner size={30} /></div>;
}
