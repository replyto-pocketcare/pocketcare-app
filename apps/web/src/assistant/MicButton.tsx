"use client";

import { useRef, useState } from "react";
import {
  voiceSupported, recordingSupported, webSpeechSupported,
  startRecording, transcribeWhisper, startWebSpeech, type Recorder, type LiveSession,
} from "./speech";

type Status = "idle" | "recording" | "transcribing" | "listening" | "unsupported";

/**
 * Mic for the assistant composer. Tap to start, tap to stop. Prefers on-device
 * Whisper (record → transcribe locally); falls back to the browser's live
 * dictation when recording/Whisper isn't available. Inserts text into the
 * composer — the assistant still replies in text.
 */
export function MicButton({ getInput, setInput, disabled }: { getInput: () => string; setInput: (v: string) => void; disabled?: boolean }) {
  const [status, setStatus] = useState<Status>(() => (voiceSupported() ? "idle" : "unsupported"));
  const [pct, setPct] = useState(0);
  const recRef = useRef<Recorder | null>(null);
  const liveRef = useRef<LiveSession | null>(null);
  const baseRef = useRef("");

  function startLive() {
    if (!webSpeechSupported()) { setStatus("idle"); return; }
    try {
      liveRef.current = startWebSpeech({
        onText: (t) => setInput(baseRef.current ? `${baseRef.current} ${t}` : t),
        onEnd: () => { liveRef.current = null; setStatus("idle"); },
        onError: () => { liveRef.current = null; setStatus("idle"); },
      });
      setStatus("listening");
    } catch { setStatus("idle"); }
  }

  async function start() {
    baseRef.current = getInput();
    if (recordingSupported()) {
      try { recRef.current = await startRecording(); setStatus("recording"); return; }
      catch { /* mic blocked → try live */ }
    }
    startLive();
  }

  async function stopRecording() {
    const r = recRef.current; recRef.current = null;
    if (!r) { setStatus("idle"); return; }
    setStatus("transcribing"); setPct(0);
    try {
      const blob = await r.stop();
      const text = await transcribeWhisper(blob, setPct);
      if (text) { const base = getInput(); setInput(base ? `${base} ${text}` : text); }
    } catch { /* transcription failed — leave input as-is */ }
    setStatus("idle");
  }

  function onClick() {
    if (disabled) return;
    if (status === "idle") void start();
    else if (status === "recording") void stopRecording();
    else if (status === "listening") liveRef.current?.stop();
  }

  if (status === "unsupported") return null;

  const active = status === "recording" || status === "listening";
  const label = status === "recording" ? "Stop recording" : status === "listening" ? "Stop" : status === "transcribing" ? "Transcribing…" : "Speak";
  return (
    <button
      type="button"
      aria-label={label}
      title={status === "idle" ? "Speak to PocketCare" : label}
      onClick={onClick}
      disabled={disabled || status === "transcribing"}
      style={{
        flexShrink: 0, width: 38, height: 38, borderRadius: 999, border: "1px solid var(--border)",
        display: "grid", placeItems: "center", cursor: "pointer", fontSize: 15,
        background: active ? "var(--accent)" : "var(--surface-2)", color: active ? "#fff" : "var(--text-2)",
        animation: active ? "micPulse 1.4s ease-in-out infinite" : "none",
      }}
    >
      {status === "transcribing" ? <span style={{ fontSize: 10, fontWeight: 700 }}>{pct > 0 && pct < 1 ? `${Math.round(pct * 100)}%` : "…"}</span> : "🎙"}
      <style>{`@keyframes micPulse { 0%,100%{ box-shadow: 0 0 0 0 var(--accent-soft) } 50%{ box-shadow: 0 0 0 6px transparent } }`}</style>
    </button>
  );
}
