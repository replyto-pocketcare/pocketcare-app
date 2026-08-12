"use client";

import { Component, type ReactNode } from "react";

/**
 * Generic error boundary. Stops one component's runtime error from blanking the
 * whole app; shows a graceful fallback and logs the real error to the console so
 * it can be reported and fixed at the source.
 */
interface Props { children: ReactNode; label?: string; fallback?: ReactNode }
interface State { error: Error | null }

export class ErrorBoundary extends Component<Props, State> {
  override state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  override componentDidCatch(error: Error, info: unknown) {
    console.error(`[PocketCare] ${this.props.label ?? "component"} crashed:`, error, info);
  }

  override render() {
    if (this.state.error) {
      if (this.props.fallback) return this.props.fallback;
      return (
        <div className="card" style={{ padding: 24, display: "grid", gap: 8, maxWidth: 520 }}>
          <strong style={{ fontSize: 15 }}>Something went wrong here</strong>
          <span className="muted" style={{ fontSize: 13 }}>
            This section hit an error and couldn’t load. The rest of the app is fine — try again, and if it keeps happening let us know.
          </span>
          <button className="btn ghost" style={{ justifySelf: "start", marginTop: 4 }} onClick={() => this.setState({ error: null })}>Try again</button>
        </div>
      );
    }
    return this.props.children;
  }
}
