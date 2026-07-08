"use client";

// react-three-fiber visuals. One Canvas per card. Only the ACTIVE card runs a
// live frameloop ("always"); peeking neighbours render once ("demand") in their
// finished state, so scrolling stays smooth. Loaded lazily via next/dynamic.

import { useMemo, useRef } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { RoundedBox, Line } from "@react-three/drei";
import * as THREE from "three";
import type { VisualSpec, SeriesPoint } from "../../insights/types";
import { INSIGHT_PALETTE } from "../../insights/types";

const ease = (p: number, dt: number, k = 3) => p + (1 - p) * Math.min(1, dt * k);

// ---- bars (bars3d) ----
function Bars({ series, active }: { series: SeriesPoint[]; active: boolean }) {
  const g = useRef<THREE.Group>(null);
  const p = useRef(active ? 0 : 1);
  const max = Math.max(...series.map((s) => Math.abs(s.value)), 1);
  const n = series.length;
  useFrame((_, dt) => {
    p.current = ease(p.current, dt);
    if (g.current && active) g.current.rotation.y = Math.sin(performance.now() / 2600) * 0.28;
  });
  return (
    <group ref={g}>
      {series.map((s, i) => {
        const h = (Math.abs(s.value) / max) * 2.3 + 0.06;
        const x = (i - (n - 1) / 2) * 0.62;
        const sign = s.value < 0 ? -1 : 1;
        return (
          <group key={i} position={[x, 0, 0]} scale={[1, p.current, 1]}>
            <RoundedBox args={[0.42, h, 0.42]} radius={0.07} smoothness={3} position={[0, (sign * h) / 2, 0]}>
              <meshStandardMaterial color={INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]!} roughness={0.5} metalness={0.05} />
            </RoundedBox>
          </group>
        );
      })}
    </group>
  );
}

// ---- ribbon (ribbon3d): slim accent bars + a trend line through the tops ----
function Ribbon({ series, accent, active }: { series: SeriesPoint[]; accent: string; active: boolean }) {
  const p = useRef(active ? 0 : 1);
  const max = Math.max(...series.map((s) => Math.abs(s.value)), 1);
  const n = series.length;
  const xs = series.map((_, i) => (i - (n - 1) / 2) * 0.62);
  const pts = useMemo<[number, number, number][]>(
    () => series.map((s, i) => [xs[i]!, (s.value / max) * 1.9, 0]),
    [series, max, n], // eslint-disable-line react-hooks/exhaustive-deps
  );
  useFrame((_, dt) => { p.current = ease(p.current, dt); });
  return (
    <group>
      {series.map((s, i) => {
        const h = (Math.abs(s.value) / max) * 1.9 + 0.04;
        const sign = s.value < 0 ? -1 : 1;
        return (
          <group key={i} position={[xs[i]!, 0, 0]} scale={[1, p.current, 1]}>
            <RoundedBox args={[0.2, h, 0.2]} radius={0.05} smoothness={2} position={[0, (sign * h) / 2, 0]}>
              <meshStandardMaterial color={accent} roughness={0.55} transparent opacity={0.55} />
            </RoundedBox>
          </group>
        );
      })}
      <group scale={[1, p.current, 1]}>
        <Line points={pts} color={accent} lineWidth={3} />
      </group>
    </group>
  );
}

// ---- radial bars (donut3d) ----
function Radial({ series, active }: { series: SeriesPoint[]; active: boolean }) {
  const g = useRef<THREE.Group>(null);
  const p = useRef(active ? 0 : 1);
  const max = Math.max(...series.map((s) => Math.abs(s.value)), 1);
  const n = series.length;
  useFrame((_, dt) => {
    p.current = ease(p.current, dt);
    if (g.current && active) g.current.rotation.y += dt * 0.35;
  });
  return (
    <group ref={g} rotation={[0.5, 0, 0]}>
      {series.map((s, i) => {
        const h = (Math.abs(s.value) / max) * 1.8 + 0.1;
        const a = (i / n) * Math.PI * 2;
        const r = 1.25;
        return (
          <group key={i} position={[Math.cos(a) * r, 0, Math.sin(a) * r]} rotation={[0, -a, 0]} scale={[1, p.current, 1]}>
            <RoundedBox args={[0.3, h, 0.3]} radius={0.06} smoothness={2} position={[0, h / 2, 0]}>
              <meshStandardMaterial color={INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]!} roughness={0.5} />
            </RoundedBox>
          </group>
        );
      })}
    </group>
  );
}

// ---- gauge (gauge3d): liquid-fill cylinder that colours by threshold ----
function Gauge({ value, max, warnAt, dangerAt, active }: { value: number; max: number; warnAt?: number | undefined; dangerAt?: number | undefined; active: boolean }) {
  const fill = useRef(0);
  const target = Math.min(1.15, max > 0 ? value / max : 0);
  const color = value >= (dangerAt ?? max) ? "#a8503a" : value >= (warnAt ?? max * 0.8) ? "#c08a3e" : "#5f7a52";
  const H = 2.4;
  const g = useRef<THREE.Group>(null);
  useFrame((_, dt) => {
    fill.current += (target - fill.current) * Math.min(1, dt * 2.5);
    if (g.current && active) g.current.rotation.y += dt * 0.3;
  });
  const h = Math.max(0.001, Math.min(1, fill.current)) * H;
  return (
    <group ref={g}>
      {/* glass shell */}
      <mesh position={[0, 0, 0]}>
        <cylinderGeometry args={[0.92, 0.92, H, 40, 1, true]} />
        <meshStandardMaterial color="#ffffff" transparent opacity={0.14} roughness={0.1} side={THREE.DoubleSide} />
      </mesh>
      {/* liquid */}
      <mesh position={[0, -H / 2 + h / 2, 0]}>
        <cylinderGeometry args={[0.86, 0.86, h, 40]} />
        <meshStandardMaterial color={color} roughness={0.35} metalness={0.05} emissive={color} emissiveIntensity={0.12} />
      </mesh>
    </group>
  );
}

// ---- orb (orb3d): fill sphere for achievements ----
function Orb({ value, target, accent, active }: { value: number; target?: number | undefined; accent: string; active: boolean }) {
  const s = useRef(0);
  const ratio = target && target > 0 ? Math.min(1, value / target) : 0.6;
  const g = useRef<THREE.Group>(null);
  useFrame((_, dt) => {
    s.current += (ratio - s.current) * Math.min(1, dt * 2.5);
    if (g.current) g.current.rotation.y += dt * (active ? 0.5 : 0);
  });
  const scale = 0.35 + Math.max(0.001, s.current) * 1.15;
  return (
    <group ref={g}>
      <mesh>
        <sphereGeometry args={[1.5, 40, 40]} />
        <meshStandardMaterial color={accent} transparent opacity={0.12} roughness={0.2} />
      </mesh>
      <mesh scale={scale}>
        <sphereGeometry args={[1, 40, 40]} />
        <meshStandardMaterial color={accent} roughness={0.3} metalness={0.1} emissive={accent} emissiveIntensity={0.18} />
      </mesh>
    </group>
  );
}

function Content({ visual, accent, active }: { visual: VisualSpec; accent: string; active: boolean }) {
  switch (visual.kind) {
    case "bars3d": return <Bars series={visual.series} active={active} />;
    case "ribbon3d": return <Ribbon series={visual.series} accent={accent} active={active} />;
    case "donut3d": return <Radial series={visual.series} active={active} />;
    case "gauge3d": return <Gauge value={visual.value} max={visual.max} warnAt={visual.warnAt} dangerAt={visual.dangerAt} active={active} />;
    case "orb3d": return <Orb value={visual.value} target={visual.target} accent={accent} active={active} />;
    default: return null;
  }
}

export default function Visual3D({ visual, accent, active }: { visual: VisualSpec; accent: string; active: boolean }) {
  return (
    <Canvas
      dpr={[1, 2]}
      frameloop={active ? "always" : "demand"}
      camera={{ position: [0, 1.2, 5.2], fov: 42 }}
      gl={{ antialias: true, alpha: true }}
      style={{ touchAction: "none" }} // 3D canvas never steals the feed's paging gesture
    >
      <ambientLight intensity={0.75} />
      <directionalLight position={[3, 6, 4]} intensity={1.15} />
      <directionalLight position={[-4, 2, -3]} intensity={0.35} />
      <group position={[0, -0.5, 0]}>
        <Content visual={visual} accent={accent} active={active} />
      </group>
    </Canvas>
  );
}
