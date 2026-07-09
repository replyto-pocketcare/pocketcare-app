"use client";

import { Canvas, useFrame } from "@react-three/fiber";
import { useRef } from "react";
import * as THREE from "three";

/** A single flickering candle flame (emissive cone + warm point light). */
function Flame({ position }: { position: [number, number, number] }) {
  const flame = useRef<THREE.Mesh>(null);
  const light = useRef<THREE.PointLight>(null);
  useFrame((state) => {
    const t = state.clock.elapsedTime;
    const flicker = 0.85 + Math.sin(t * 20 + position[0] * 10) * 0.12 + Math.random() * 0.05;
    if (flame.current) {
      flame.current.scale.set(flicker, 1 + (flicker - 0.9), flicker);
      (flame.current.material as THREE.MeshStandardMaterial).emissiveIntensity = 1.6 * flicker;
    }
    if (light.current) light.current.intensity = 0.5 * flicker;
  });
  return (
    <group position={position}>
      <mesh ref={flame} position={[0, 0.16, 0]}>
        <coneGeometry args={[0.05, 0.22, 12]} />
        <meshStandardMaterial color="#ff9d2e" emissive="#ffb347" emissiveIntensity={1.6} toneMapped={false} />
      </mesh>
      <pointLight ref={light} position={[0, 0.2, 0]} distance={2} color="#ffcf87" intensity={0.5} />
    </group>
  );
}

/** A thin candle. */
function Candle({ position }: { position: [number, number, number] }) {
  return (
    <group position={position}>
      <mesh castShadow>
        <cylinderGeometry args={[0.045, 0.045, 0.5, 16]} />
        <meshStandardMaterial color="#f6d5e4" />
      </mesh>
      <Flame position={[0, 0.28, 0]} />
    </group>
  );
}

function Cake() {
  const group = useRef<THREE.Group>(null);
  useFrame((_, dt) => {
    if (group.current) group.current.rotation.y += dt * 0.5;
  });

  // Five candles evenly around the top tier.
  const candles: [number, number, number][] = [];
  const N = 5, r = 0.5, topY = 1.15;
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2;
    candles.push([Math.cos(a) * r, topY, Math.sin(a) * r]);
  }

  return (
    <group ref={group} position={[0, -0.6, 0]}>
      {/* plate */}
      <mesh position={[0, -0.05, 0]} receiveShadow>
        <cylinderGeometry args={[1.5, 1.5, 0.08, 48]} />
        <meshStandardMaterial color="#e9e4dc" metalness={0.1} roughness={0.6} />
      </mesh>
      {/* bottom sponge */}
      <mesh position={[0, 0.35, 0]} castShadow>
        <cylinderGeometry args={[1.15, 1.2, 0.7, 48]} />
        <meshStandardMaterial color="#c98a72" roughness={0.8} />
      </mesh>
      {/* bottom frosting drip ring */}
      <mesh position={[0, 0.68, 0]}>
        <torusGeometry args={[1.16, 0.09, 16, 48]} />
        <meshStandardMaterial color="#fdeef2" roughness={0.5} />
      </mesh>
      {/* top sponge */}
      <mesh position={[0, 0.95, 0]} castShadow>
        <cylinderGeometry args={[0.8, 0.85, 0.5, 48]} />
        <meshStandardMaterial color="#d79a82" roughness={0.8} />
      </mesh>
      {/* top frosting */}
      <mesh position={[0, 1.18, 0]}>
        <cylinderGeometry args={[0.83, 0.83, 0.14, 48]} />
        <meshStandardMaterial color="#fff4f7" roughness={0.4} />
      </mesh>
      {/* cherry on top */}
      <mesh position={[0, 1.32, 0]} castShadow>
        <sphereGeometry args={[0.1, 20, 20]} />
        <meshStandardMaterial color="#d23a5e" roughness={0.3} />
      </mesh>
      {candles.map((p, i) => <Candle key={i} position={p} />)}
    </group>
  );
}

export default function Cake3D() {
  return (
    <Canvas camera={{ position: [0, 1.3, 4.6], fov: 45 }} dpr={[1, 2]} style={{ width: "100%", height: "100%" }}>
      <ambientLight intensity={0.65} />
      <directionalLight position={[3, 5, 2]} intensity={1.15} castShadow />
      <pointLight position={[-3, 2, -2]} intensity={0.4} color="#bcd3ff" />
      <Cake />
    </Canvas>
  );
}
