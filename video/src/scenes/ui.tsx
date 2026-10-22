import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";

export const C = { bg: "#0b0f14", panel: "#141b24", text: "#e8eef5", dim: "#8a97a8", green: "#76b900", red: "#ff6b57", blue: "#4aa8ff" };
export const FONT = "Inter, ui-sans-serif, system-ui, sans-serif";

export const Fade: React.FC<{ children: React.ReactNode; dur: number }> = ({ children, dur }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [0, 10, dur - 10, dur], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return <AbsoluteFill style={{ opacity: o, background: C.bg, fontFamily: FONT, color: C.text }}>{children}</AbsoluteFill>;
};

export const Title: React.FC<{ kicker: string; title: string }> = ({ kicker, title }) => (
  <div style={{ position: "absolute", left: 64, top: 48 }}>
    <div style={{ color: C.green, fontSize: 22, letterSpacing: 3, textTransform: "uppercase", fontWeight: 600 }}>{kicker}</div>
    <div style={{ fontSize: 54, fontWeight: 700, marginTop: 6 }}>{title}</div>
  </div>
);

export const Caption: React.FC<{ text: string; sub?: string }> = ({ text, sub }) => (
  <div style={{ position: "absolute", left: 64, right: 64, bottom: 44 }}>
    <div style={{ fontSize: 34, fontWeight: 600 }}>{text}</div>
    {sub && <div style={{ fontSize: 20, color: C.dim, marginTop: 6 }}>{sub}</div>}
  </div>
);

export const useIn = (delay = 0) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - delay, fps, config: { damping: 200 } });
};

export const Counter: React.FC<{ to: number; from?: number; delay?: number; suffix?: string; color?: string; size?: number; label: string }> = ({ to, from = 0, delay = 0, suffix = "", color = C.text, size = 120, label }) => {
  const p = useIn(delay);
  const v = Math.round(from + (to - from) * p);
  return (
    <div style={{ background: C.panel, borderRadius: 20, padding: "28px 36px", flex: 1 }}>
      <div style={{ fontSize: size, fontWeight: 800, color, lineHeight: 1, whiteSpace: "nowrap" }}>{v}{suffix}</div>
      <div style={{ fontSize: 22, color: C.dim, marginTop: 10 }}>{label}</div>
    </div>
  );
};
