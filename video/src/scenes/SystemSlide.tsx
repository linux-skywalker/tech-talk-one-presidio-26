import { interpolate, useCurrentFrame } from "remotion";
import { C, Fade, useIn } from "./ui";

// Opening slide: the machine every demo was recorded on. Facts read from the machine (lscpu, free, nvidia-smi, /etc/os-release, kubectl version).
export const SYSTEM_TOTAL = 6 * 30;

// Stylised RTX 4070 card drawn in SVG (not a photo): two fans that spin, a gold glow that pulses, a gentle float.
const Fan: React.FC<{ cx: number; spin: number }> = ({ cx, spin }) => (
  <g transform={`translate(${cx} 170)`}>
    <circle r="108" fill="#0a0f0c" stroke="#2C4A3B" strokeWidth="4" />
    <g transform={`rotate(${spin})`}>
      {Array.from({ length: 9 }).map((_, i) => (
        <path key={i} transform={`rotate(${i * 40})`} d="M0 0 C 18 -30, 60 -78, 14 -98 C -10 -70, -18 -30, 0 0 Z" fill="#1A2D24" stroke="#E3B04B" strokeOpacity="0.55" strokeWidth="1.5" />
      ))}
    </g>
    <circle r="22" fill="#E3B04B" />
    <circle r="12" fill="#0C120F" />
  </g>
);

const Gpu: React.FC = () => {
  const f = useCurrentFrame();
  const float = Math.sin(f / 18) * 8;
  const glow = 0.5 + 0.35 * Math.sin(f / 12);
  return (
    <svg width="820" height="440" viewBox="0 0 820 440" style={{ transform: `translateY(${float}px)`, overflow: "visible" }}>
      <ellipse cx="410" cy="410" rx="340" ry="22" fill="#E3B04B" opacity={0.18 * glow} />
      <rect x="20" y="40" width="740" height="260" rx="26" fill="#121b16" stroke="#E3B04B" strokeWidth="3" style={{ filter: `drop-shadow(0 0 ${14 + 16 * glow}px rgba(227,176,75,${0.45 * glow}))` }} />
      <rect x="760" y="70" width="40" height="200" rx="8" fill="#1A2D24" stroke="#2C4A3B" strokeWidth="3" />
      <Fan cx={230} spin={f * 14} />
      <Fan cx={540} spin={f * 14} />
      <rect x="20" y="268" width="740" height="32" rx="10" fill="#0C120F" />
      <text x="44" y="291" fontSize="20" fontWeight="700" fill="#E3B04B" letterSpacing="4" fontFamily="inherit">GEFORCE RTX 4070</text>
      <rect x="120" y="300" width="300" height="34" fill="#E3B04B" opacity="0.9" />
      {Array.from({ length: 14 }).map((_, i) => <rect key={i} x={126 + i * 21} y={304} width="12" height="26" fill="#0C120F" />)}
    </svg>
  );
};

const Chip: React.FC<{ t: string; delay: number }> = ({ t, delay }) => {
  const p = useIn(delay);
  return (
    <div style={{ opacity: p, transform: `translateY(${(1 - p) * 14}px)`, background: C.card, border: `1px solid ${C.border}`, borderRadius: 14, padding: "12px 22px", fontSize: 28, color: C.text }}>{t}</div>
  );
};

export const SystemSlide = () => {
  const f = useCurrentFrame();
  const a = interpolate(f, [0, 20], [0, 1], { extrapolateRight: "clamp" });
  return (
    <Fade dur={SYSTEM_TOTAL}>
      <div style={{ position: "absolute", left: 100, top: 110, opacity: a }}>
        <div style={{ fontSize: 28, color: C.gold, letterSpacing: 4, textTransform: "uppercase", fontWeight: 600 }}>The machine behind every demo</div>
        <div style={{ fontSize: 190, fontWeight: 700, color: C.gold, lineHeight: 1.05, marginTop: 14 }}>RTX 4070</div>
        <div style={{ fontSize: 62, fontWeight: 700, color: C.text, marginTop: 4 }}>Ada Lovelace · <span style={{ color: C.gold }}>12 GB VRAM</span></div>
      </div>
      <div style={{ position: "absolute", left: 100, top: 640, display: "flex", gap: 16, flexWrap: "wrap", width: 860 }}>
        <Chip t="Intel Core i7-13700K · 32 GB DDR5 RAM" delay={30} />
        <Chip t="Ubuntu 24.04" delay={42} />
        <Chip t="Kubernetes (k3s) v1.36" delay={54} />
        <Chip t="NVIDIA driver 595.99" delay={66} />
      </div>
      <div style={{ position: "absolute", right: 40, top: 310, transform: "scale(0.88)", transformOrigin: "100% 0" }}><Gpu /></div>
    </Fade>
  );
};
