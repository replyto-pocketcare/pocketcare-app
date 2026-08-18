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

/** Fires whatever action is currently registered. Optionally takes the element
 *  that triggered it, so a menu-type action can anchor its popover there. */
export type AddRunner = (anchor?: HTMLElement | null) => void;
const RunnerContext = createContext<AddRunner | null>(null);

export function AddActionProvider({ setter, run, children }: {
  setter: (a: AddAction | null) => void; run: AddRunner; children: ReactNode;
}) {
  return (
    <SetterContext.Provider value={setter}>
      <RunnerContext.Provider value={run}>{children}</RunnerContext.Provider>
    </SetterContext.Provider>
  );
}

/**
 * Trigger the shell's contextual add action from inside a page.
 *
 * This exists because the desktop layout moved the add affordance OUT of the
 * shell chrome and into the dashboard's own header row, while phones keep it
 * on the bottom bar. Both surfaces must run the same action — a page that
 * registered a bespoke "+" should not behave differently depending on which
 * button you press — so the page borrows the shell's runner rather than
 * reimplementing it. Null outside a shell (tests, storybook).
 */
export function useAddRunner(): AddRunner | null {
  return useContext(RunnerContext);
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
