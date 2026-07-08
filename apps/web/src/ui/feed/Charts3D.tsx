"use client";

// react-three-fiber visuals. One Canvas per card. Only the ACTIVE card runs a
// live frameloop ("always"); peeking neighbours render once ("demand"). <Bounds>
// auto-frames each visual so it fills the card regardless of aspect ratio.

import { useMemo, useRef } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { RoundedBox, Line, Bounds } from "@react-three/drei";
import * as THREE from "three";
import type { VisualSpec, SeriesPoint } from "../../insights/types";
import { INSIGHT_PALETTE } from "../../insights/types";

const HALF_W = 2.6;
const spread = (n: number, i: number) => (n <= 1 ? 0 : -HALF_W + (i / (n - 1)) * 2 * HALF_W);

// ---- bars (bars3d) ----
function Bars({ series }: { series: SeriesPoint[] }) {
  const max = Math.max(...series.map((s) => Math.abs(s.value)), 1);
  const n = series.length;
  const w = Math.min(0.62, (2 * HALF_W) / (n * 1.5));
  return (
    <group rotation={[0, -0.32, 0]}>
      {series.map((s, i) => {
        const h = (Math.abs(s.value) / max) * 2.6 + 0.12;
        const sign = s.value < 0 ? -1 : 1;
        return (
          <RoundedBox key={i} args={[w, h, w]} radius={Math.min(0.07, w / 3)} smoothness={3} position={[spread(n, i), (sign * h) / 2, 0]}>
            <meshStandardMaterial color={INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]!} roughness={0.45} metalness={0.08} />
          </RoundedBox>
        );
      })}
    </group>
  );
}

// ---- ribbon (ribbon3d): a solid extruded area under the value curve ----
function Ribbon({ series, accent }: { series: SeriesPoint[]; accent: string }) {
  const { geo, top } = useMemo(() => {
    const n = series.length;
    const max = Math.max(...series.map((s) => Math.abs(s.value)), 1);
    const xs = series.map((_, i) => spread(n, i));
    const ys = series.map((s) => (s.value / max) * 1.6);
    const base = Math.min(0, ...ys) - 0.2;
    const shape = new THREE.Shape();
    shape.moveTo(xs[0]!, base);
    xs.forEach((x, i) => shape.lineTo(x, ys[i]!));
    shape.lineTo(xs[n - 1]!, base);
    shape.closePath();
    const g = new THREE.ExtrudeGeometry(shape, { depth: 0.55, bevelEnabled: false });
    const topPts: [number, number, number][] = xs.map((x, i) => [x, ys[i]!, 0.56]);
    return { geo: g, top: topPts };
  }, [series]);
  return (
    <group rotation={[-0.08, -0.4, 0]}>
      <mesh geometry={geo}>
        <meshStandardMaterial color={accent} roughness={0.5} metalness={0.05} emissive={accent} emissiveIntensity={0.1} side={THREE.DoubleSide} />
      </mesh>
      <Line points={top} color={accent} lineWidth={3} />
    </group>
  );
}

// ---- radial bars (donut3d) ----
function Radial({ series, active }: { series: SeriesPoint[]; active: boolean }) {
  const g = useRef<THREE.Group>(null);
  const max = Math.max(...series.map((s) => Math.abs(s.value)), 1);
  const n = series.length;
  useFrame((_, dt) => { if (g.current && active) g.current.rotation.y += dt * 0.3; });
  return (
    <group ref={g} rotation={[0.62, 0, 0]}>
      {series.map((s, i) => {
        const h = (Math.abs(s.value) / max) * 1.7 + 0.25;
        const a = (i / n) * Math.PI * 2;
        const r = 1.45;
        return (
          <RoundedBox key={i} args={[0.42, h, 0.42]} radius={0.08} smoothness={3} position={[Math.cos(a) * r, h / 2, Math.sin(a) * r]} rotation={[0, -a, 0]}>
            <meshStandardMaterial color={INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]!} roughness={0.45} metalness={0.08} />
          </RoundedBox>
        );
      })}
    </group>
  );
}

// ---- gauge (gauge3d): liquid-fill cylinder that colours by threshold ----
function Gauge({ value, max, warnAt, dangerAt, active }: { value: number; max: number; warnAt?: number | undefined; dangerAt?: number | undefined; active: boolean }) {
  const fill = useRef(0);
  const target = Math.min(1, max > 0 ? value / max : 0);
  const color = value >= (dangerAt ?? max) ? "#a8503a" : value >= (warnAt ?? max * 0.8) ? "#c08a3e" : "#5f7a52";
  const H = 3;
  const g = useRef<THREE.Group>(null);
  const liquid = useRef<THREE.Mesh>(null);
  useFrame((_, dt) => {
    fill.current += (target - fill.current) * Math.min(1, dt * 2.5);
    if (g.current && active) g.current.rotation.y += dt * 0.25;
    const h = Math.max(0.001, fill.current) * H;
    if (liquid.current) { liquid.current.scale.y = h / H; liquid.current.position.y = -H / 2 + h / 2; }
  });
  return (
    <group ref={g}>
      <mesh>
        <cylinderGeometry args={[1.15, 1.15, H, 48, 1, true]} />
        <meshStandardMaterial color="#ffffff" transparent opacity={0.13} roughness={0.1} side={THREE.DoubleSide} />
      </mesh>
      <mesh ref={liquid} position={[0, -H / 2, 0]}>
        <cylinderGeometry args={[1.07, 1.07, H, 48]} />
        <meshStandardMaterial color={color} roughness={0.3} metalness={0.05} emissive={color} emissiveIntensity={0.14} />
      </mesh>
    </group>
  );
}

// ---- orb (orb3d): fill sphere for achievements ----
function Orb({ value, target, accent, active }: { value: number; target?: number | undefined; accent: string; active: boolean }) {
  const s = useRef(0);
  const ratio = target && target > 0 ? Math.min(1, value / target) : 0.6;
  const g = useRef<THREE.Group>(null);
  const inner = useRef<THREE.Mesh>(null);
  useFrame((_, dt) => {
    s.current += (ratio - s.current) * Math.min(1, dt * 2.5);
    if (g.current && active) g.current.rotation.y += dt * 0.4;
    const sc = 0.35 + Math.max(0.001, s.current) * 1.15;
    if (inner.current) inner.current.scale.setScalar(sc);
  });
  return (
    <group ref={g}>
      <mesh>
        <sphereGeometry args={[1.6, 48, 48]} />
        <meshStandardMaterial color={accent} transparent opacity={0.12} roughness={0.2} />
      </mesh>
      <mesh ref={inner}>
        <sphereGeometry args={[1, 48, 48]} />
        <meshStandardMaterial color={accent} roughness={0.28} metalness={0.12} emissive={accent} emissiveIntensity={0.2} />
      </mesh>
    </group>
  );
}

function Content({ visual, accent, active }: { visual: VisualSpec; accent: string; active: boolean }) {
  switch (visual.kind) {
    case "bars3d": return <Bars series={visual.series} />;
    case "ribbon3d": return <Ribbon series={visual.series} accent={accent} />;
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
      camera={{ position: [0, 1.6, 7], fov: 38 }}
      gl={{ antialias: true, alpha: true }}
      style={{ touchAction: "none" }} // 3D canvas never steals the feed's paging gesture
    >
      <ambientLight intensity={0.85} />
      <directionalLight position={[4, 7, 5]} intensity={1.2} />
      <directionalLight position={[-5, 2, -4]} intensity={0.4} />
      <Bounds fit clip observe margin={1.2}>
        <Content visual={visual} accent={accent} active={active} />
      </Bounds>
    </Canvas>
  );
}
