"use client";

/**
 * Lets the currently-mounted page declare what the floating bottom bar's
 * center "+" button should do. The button is global chrome (AppShell), but
 * "add" means something different on every screen — a new transaction on
 * /transactions, a new budget on /budgets, a new loan on /loans, and so on —
 * so the page in view controls it via `useRegisterAddAction`, and AppShell
 * just renders whatever's currently registered.
 *
 * Unregistered pages fall back to the transaction/receipt menu (AppShell's
 * DEFAULT_ADD_ACTION) rather than hiding the button — creating a transaction
 * is the one thing that's *always* a reasonable "+" on a money app.
 */
import { createContext, useContext, useEffect, useRef, type ReactNode } from "react";

export interface AddMenuItem {
  key: string;
  label: string;
  icon: ReactNode;
  href?: string;
  onClick?: () => void;
}

export type AddAction =
  | { type: "link"; href: string; label: string }
  | { type: "button"; onClick: () => void; label: string }
  | { type: "menu"; label: string; items: AddMenuItem[] };

const SetterContext = createContext<((a: AddAction | null) => void) | null>(null);

export function AddActionProvider({ value, children }: { value: (a: AddAction | null) => void; children: ReactNode }) {
  return <SetterContext.Provider value={value}>{children}</SetterContext.Provider>;
}

/**
 * Register this page's contextual "+" action while it's mounted. Pass a
 * stable-ish `deps` array (like useEffect) so it doesn't thrash — but it's
 * cheap either way, this only ever touches one bit of AppShell state.
 */
export function useRegisterAddAction(action: AddAction, deps: React.DependencyList): void {
  const setAction = useContext(SetterContext);
  // Keep the latest action in a ref so the effect can register it without
  // needing `action` itself in the dependency array (callers pass fresh
  // closures every render; only `deps` should decide when to re-register).
  const ref = useRef(action);
  ref.current = action;
  useEffect(() => {
    setAction?.(ref.current);
    return () => setAction?.(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}
