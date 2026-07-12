"use client";

import { createContext, useContext, useState, useCallback, type ReactNode } from "react";
import { Modal } from "./Modal";

export interface ConfirmOptions {
  title: string;
  message?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Style the confirm button as destructive (red). Defaults to true. */
  danger?: boolean;
}

type ConfirmFn = (opts: ConfirmOptions) => Promise<boolean>;
const ConfirmContext = createContext<ConfirmFn>(async () => false);

/**
 * App-wide confirmation dialog. Call `const confirm = useConfirm()` in any
 * component, then `if (await confirm({ title: "Delete this?" })) { … }`.
 * Resolves true on confirm, false on cancel / dismiss.
 */
export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [opts, setOpts] = useState<ConfirmOptions | null>(null);
  const [resolver, setResolver] = useState<{ fn: (v: boolean) => void } | null>(null);

  const confirm = useCallback<ConfirmFn>((o) => new Promise<boolean>((resolve) => {
    setOpts(o);
    setResolver({ fn: resolve });
  }), []);

  const close = (value: boolean) => {
    resolver?.fn(value);
    setResolver(null);
    setOpts(null);
  };

  const danger = opts?.danger ?? true;

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      <Modal open={!!opts} onClose={() => close(false)}>
        {opts && (
          <div style={{ display: "grid", gap: 14 }}>
            <h2 style={{ margin: 0 }}>{opts.title}</h2>
            {opts.message && (
              <p className="muted" style={{ margin: 0, fontSize: 14, lineHeight: 1.6 }}>{opts.message}</p>
            )}
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
              <button className="btn ghost" onClick={() => close(false)}>{opts.cancelLabel ?? "Cancel"}</button>
              <button
                className="btn"
                autoFocus
                style={danger ? { background: "var(--negative)", boxShadow: "0 10px 24px -12px rgba(168,80,58,0.9)" } : undefined}
                onClick={() => close(true)}
              >
                {opts.confirmLabel ?? "Delete"}
              </button>
            </div>
          </div>
        )}
      </Modal>
    </ConfirmContext.Provider>
  );
}

export const useConfirm = (): ConfirmFn => useContext(ConfirmContext);
