import { loadFont } from "@remotion/google-fonts/Poppins";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

// Palette and background taken from the Presidio India Exchange deck.
export const C = { text: "#F5ECDD", dim: "#B3A48D", gold: "#E3B04B", card: "#1A2D24", border: "#2C4A3B", bg: "#0C120F", red: "#D64545" };
const poppins = loadFont("normal", { weights: ["400", "600", "700"], subsets: ["latin"] });
export const FONT = `${poppins.fontFamily}, ` + "Poppins, 'Segoe UI', ui-sans-serif, system-ui, sans-serif";

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

export const useIn = (delay = 0) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - delay, fps, config: { damping: 200 } });
};

