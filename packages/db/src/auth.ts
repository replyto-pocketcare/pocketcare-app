/**
 * Auth helpers — one identity from first launch (ARCHITECTURE.md §9).
 * A guest is a real Supabase user with is_anonymous = true; registering upgrades
 * the SAME UID in place, so no data is ever re-keyed or copied.
 */
import {
  createClient,
  type SupabaseClient,
  type SupabaseClientOptions,
} from "@supabase/supabase-js";

export interface SupabaseConfig {
  url: string;
  anonKey: string;
  /** Platform storage (SecureStore adapter on mobile, localStorage on web). */
  storage?: SupabaseClientOptions<"public">["auth"] extends infer A
    ? A extends { storage?: infer S }
      ? S
      : unknown
    : unknown;
}

export function createSupabaseClient(config: SupabaseConfig): SupabaseClient {
  return createClient(config.url, config.anonKey, {
    auth: {
      ...(config.storage ? { storage: config.storage as never } : {}),
      autoRefreshToken: true,
      persistSession: true,
      // Needed so email-confirmation / magic links complete when the user is
      // redirected back to the app with tokens in the URL.
      detectSessionInUrl: true,
    },
  });
}

/** Ensure there's a session; sign in anonymously (guest) if none exists. */
export async function ensureUser(client: SupabaseClient): Promise<string> {
  const { data } = await client.auth.getSession();
  if (data.session?.user) return data.session.user.id;

  const { data: anon, error } = await client.auth.signInAnonymously();
  if (error || !anon.user) throw error ?? new Error("Anonymous sign-in failed");
  return anon.user.id;
}

/** True if the current user is a guest (anonymous). */
export async function isGuest(client: SupabaseClient): Promise<boolean> {
  const { data } = await client.auth.getUser();
  // Supabase exposes is_anonymous on the user object for anonymous sessions.
  return Boolean((data.user as { is_anonymous?: boolean } | null)?.is_anonymous);
}

/**
 * Upgrade the current anonymous user to a registered account IN PLACE.
 * The UID is unchanged, so every existing row stays owned by this user.
 */
export async function upgradeGuestWithEmail(
  client: SupabaseClient,
  email: string,
  password: string,
): Promise<void> {
  const { error } = await client.auth.updateUser({ email, password });
  if (error) throw error;
  // After email confirmation the same user is now non-anonymous.
}
