"use client";

import { useState } from "react";
import { getRepositories } from "../../src/powersync";
import { useIntentQueue } from "../../src/reflect/useIntentQueue";
import { IntentCard } from "../../src/reflect/IntentCard";
import { CheckCircleIcon, UndoIcon, SkipIcon } from "../../src/ui/icons";

export default function ReflectPage() {
  const { queue, isLoading } = useIntentQueue();
  const [history, setHistory] = useState<{ id: string; action: "skip" | "judge" }[]>([]); 

  const currentQueue = queue.filter(tx => !history.some(h => h.id === tx.id));
  
  if (isLoading) {
    return <div style={{ padding: 24, textAlign: "center" }}>Loading...</div>;
  }

  if (currentQueue.length === 0) {
    return (
      <div style={{ padding: 48, textAlign: "center" }}>
        <div style={{ color: "var(--positive)" }}>
          <CheckCircleIcon size={48} />
        </div>
        <h2 style={{ marginTop: 16 }}>All caught up!</h2>
        <p className="muted">You have reviewed all your recent spending.</p>
      </div>
    );
  }

  const handleJudged = async (id: string, intent: 'need' | 'greed') => {
    setHistory([...history, { id, action: "judge" }]);
    await getRepositories().transactions.update(id, { intent });
  };

  const handleSkip = (id: string) => {
    setHistory([...history, { id, action: "skip" }]);
  };

  const handleUndo = async () => {
    if (history.length === 0) return;
    const last = history[history.length - 1];
    
    setHistory(history.slice(0, -1));
    
    if (last.action === "judge") {
      await getRepositories().transactions.update(last.id, { intent: null });
    }
  };

  return (
    <div style={{ maxWidth: 480, margin: "0 auto", padding: "24px 16px", height: "100dvh", display: "flex", flexDirection: "column" }}>
      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 32 }}>
        <h1 style={{ margin: 0, fontSize: 24 }}>Reflect</h1>
        <div className="muted" style={{ fontSize: 14 }}>
          {currentQueue.length} left
        </div>
      </header>

      <div style={{ flex: 1, position: "relative" }}>
        {/* Render bottom cards for stack effect (max 3) */}
        {currentQueue.slice(0, 3).reverse().map((tx, idx) => {
          const isTop = idx === currentQueue.slice(0, 3).length - 1;
          // Reverse index: 0 is bottom-most rendered, 2 is top
          const scale = isTop ? 1 : 1 - (2 - idx) * 0.05;
          const y = isTop ? 0 : (2 - idx) * 15;
          
          return (
            <div key={tx.id} style={{ position: "absolute", inset: 0, transform: `scale(${scale}) translateY(${y}px)`, transition: "transform 0.3s ease" }}>
              <IntentCard
                id={tx.id}
                raw={tx.description || tx.note || "Unknown"}
                amountMinor={tx.amount}
                currency={tx.currency}
                occurredAt={tx.occurred_at}
                categoryName={tx.category_name} 
                accountName={tx.account_name}
                onJudged={(intent) => handleJudged(tx.id, intent)}
                onSkip={() => handleSkip(tx.id)}
                isTop={isTop}
              />
            </div>
          );
        })}
      </div>

      <footer style={{ marginTop: 32, display: "flex", justifyContent: "space-between" }}>
        <button className="btn ghost" onClick={handleUndo} disabled={history.length === 0} style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <UndoIcon size={18} /> Undo
        </button>
        <button className="btn ghost" onClick={() => handleSkip(currentQueue[currentQueue.length - 1]?.id)} style={{ display: "flex", alignItems: "center", gap: 8 }}>
          Skip <SkipIcon size={18} />
        </button>
      </footer>
    </div>
  );
}
