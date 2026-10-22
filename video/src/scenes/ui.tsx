import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

// Palette and background taken from the Presidio India Exchange deck.
export const C = { text: "#F5ECDD", dim: "#B3A48D", gold: "#E3B04B", card: "rgba(26,45,36,0.88)", red: "#E5484D", teal: "#2FA39A" };
export const FONT = "Poppins, 'Segoe UI', ui-sans-serif, system-ui, sans-serif";
export const METRICS = ["Sharing", "Failures", "Watching", "Moving", "Setting up", "Growing"];

export const Fade: React.FC<{ children: React.ReactNode; dur: number; title?: boolean }> = ({ children, dur, title }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [0, 10, dur - 10, dur], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ opacity: o, background: "#0a0705", fontFamily: FONT, color: C.text }}>
      <Img src={staticFile(title ? "brand/title-bg.png" : "brand/content-bg.png")} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
      {children}
    </AbsoluteFill>
  );
};

// Breadcrumb like the deck's "SPEND > COST > HOARD": the active metric is lit.
export const Crumbs: React.FC<{ active: string }> = ({ active }) => (
  <div style={{ position: "absolute", left: 64, top: 34, fontSize: 17, fontWeight: 600, letterSpacing: 2, textTransform: "uppercase", display: "flex", gap: 10 }}>
    {METRICS.map((m, i) => (
      <span key={m} style={{ color: m === active ? C.gold : C.dim, opacity: m === active ? 1 : 0.7 }}>
        {m}{i < METRICS.length - 1 ? " →" : ""}
      </span>
    ))}
  </div>
);

export const Title: React.FC<{ kicker?: string; title: string; active?: string }> = ({ kicker, title, active }) => (
  <>
    {active && <Crumbs active={active} />}
    <div style={{ position: "absolute", left: 64, top: 66 }}>
      {kicker && <div style={{ color: C.gold, fontSize: 20, letterSpacing: 3, textTransform: "uppercase", fontWeight: 600 }}>{kicker}</div>}
      <div style={{ fontSize: 46, fontWeight: 700, marginTop: 2 }}>{title}</div>
    </div>
  </>
);

// Stays above the footer band baked into the background (Presidio logo, India Exchange 2026).
export const Caption: React.FC<{ text: string; sub?: string }> = ({ text, sub }) => (
  <div style={{ position: "absolute", left: 64, right: 64, top: 498 }}>
    <div style={{ fontSize: 30, fontWeight: 600 }}>{text}</div>
    {sub && <div style={{ fontSize: 18, color: C.dim, marginTop: 4 }}>{sub}</div>}
  </div>
);

export const useIn = (delay = 0) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - delay, fps, config: { damping: 200 } });
};

export const Counter: React.FC<{ to: number; from?: number; delay?: number; suffix?: string; color?: string; size?: number; label: string }> = ({ to, from = 0, delay = 0, suffix = "", color = C.gold, size = 96, label }) => {
  const p = useIn(delay);
  const v = Math.round(from + (to - from) * p);
  return (
    <div style={{ background: C.card, borderRadius: 18, padding: "22px 30px", flex: 1, border: "1px solid rgba(227,176,75,0.25)" }}>
      <div style={{ fontSize: size, fontWeight: 700, color, lineHeight: 1, whiteSpace: "nowrap" }}>{v}{suffix}</div>
      <div style={{ fontSize: 19, color: C.dim, marginTop: 10, lineHeight: 1.3 }}>{label}</div>
    </div>
  );
};
