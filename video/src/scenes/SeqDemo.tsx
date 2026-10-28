import { AbsoluteFill, Freeze, Sequence, OffthreadVideo, interpolate, staticFile, useCurrentFrame } from "remotion";
import { C, Fade, useIn } from "./ui";

// One before/after demo: the "without" terminal plays first while the other one is paused, then after a 2 s gap the "with" terminal plays,
// then the comparison slide. Terminal time is the real recording, sped up by the segment rates.
const FPS = 30;
const GAP = 2 * FPS;
const HOLD = 2 * FPS;
const INTRO = 3 * FPS;
const OUTRO = 8 * FPS;

type Seg = { from: number; to: number; rate: number };
export type SideCfg = { src: string; base: number; segs: Seg[]; label: string; color: string };
type Item = { pre?: string; v: string; post?: string; color: string };
export type DemoCfg = {
  name: string;
  subtitle: string;
  crop: { x: number; y: number; w: number; h: number };
  a: SideCfg;
  b: SideCfg;
  outro: { left: Item[]; right: Item[]; strength: { pre: string; v: string; post?: string } };
};

const layout = (segs: Seg[]) => {
  let start = 0;
  const out = segs.map((s) => {
    const frames = Math.round(((s.to - s.from) / s.rate) * FPS);
    const r = { ...s, frames, start };
    start += frames;
    return r;
  });
  return { segs: out, total: start };
};

const PW = 940;

const Clip: React.FC<{ side: SideCfg; start: number; crop: DemoCfg["crop"]; sc: number }> = ({ side, start, crop, sc }) => {
  const L = layout(side.segs);
  const last = side.segs[side.segs.length - 1].to;
  const vid = { width: 1920, height: 1080 } as const;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, transformOrigin: "0 0", transform: `scale(${sc}) translate(${-crop.x}px, ${-crop.y}px)` }}>
      {start > 0 && (
        <Sequence  durationInFrames={start}>
          <Freeze frame={0}>
            <OffthreadVideo src={staticFile(side.src)} startFrom={Math.round(side.base * FPS)} muted style={vid} />
          </Freeze>
        </Sequence>
      )}
      {L.segs.map((s) => (
        <Sequence key={s.from} from={start + s.start} durationInFrames={s.frames}>
          <OffthreadVideo src={staticFile(side.src)} startFrom={Math.round((side.base + s.from) * FPS)} playbackRate={s.rate} muted style={vid} />
        </Sequence>
      ))}
      <Sequence from={start + L.total}>
        <Freeze frame={0}>
          <OffthreadVideo src={staticFile(side.src)} startFrom={Math.round((side.base + last) * FPS) - 1} muted style={vid} />
        </Freeze>
      </Sequence>
    </div>
  );
};

const Panel: React.FC<{ side: SideCfg; start: number; end: number; crop: DemoCfg["crop"]; keepLit?: boolean }> = ({ side, start, end, crop, keepLit }) => {
  const f = useCurrentFrame();
  const sc = PW / crop.w;
  const ph = Math.round(sc * crop.h);
  const playing = f >= start && f < end;
  const lit = playing || (keepLit && f >= start);
  const o = interpolate(f, [start - 8, start, end, end + 8], [0.45, 1, 1, keepLit ? 1 : 0.55], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ width: PW, opacity: o }}>
      <div style={{ fontSize: 48, fontWeight: 700, color: side.color, marginBottom: 14 }}>{side.label}</div>
      <div style={{ width: PW, height: ph, overflow: "hidden", borderRadius: 14, border: `2px solid ${side.color}`, background: C.bg, position: "relative", boxShadow: lit ? `0 0 90px ${side.color}aa, 0 0 28px ${side.color}dd` : "none" }}>
        <Clip side={side} start={start} crop={crop} sc={sc} />
      </div>
    </div>
  );
};

const Intro: React.FC<{ cfg: DemoCfg }> = ({ cfg }) => {
  const p = useIn(4);
  return (
    <Fade dur={INTRO} title>
      <AbsoluteFill style={{ justifyContent: "center", paddingLeft: 120, width: 1000 }}>
        <div style={{ opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
          <div style={{ fontSize: 110, fontWeight: 700, lineHeight: 1.1 }}><span style={{ color: C.gold }}>{cfg.name}</span> demo</div>
          <div style={{ fontSize: 40, color: C.dim, marginTop: 22 }}>{cfg.subtitle}</div>
        </div>
      </AbsoluteFill>
    </Fade>
  );
};

const Line: React.FC<{ item: Item; delay: number }> = ({ item, delay }) => {
  const p = useIn(delay);
  return (
    <div style={{ opacity: p, transform: `translateY(${(1 - p) * 20}px)`, marginBottom: 34, fontSize: 50, fontWeight: 600, lineHeight: 1.2, color: C.text, whiteSpace: "nowrap" }}>
      {item.pre}
      <span style={{ color: item.color, fontWeight: 700 }}>{item.v}</span>
      {item.post}
    </div>
  );
};

const Strength: React.FC<{ s: DemoCfg["outro"]["strength"] }> = ({ s }) => {
  const p = useIn(75);
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: 735, display: "flex", justifyContent: "center", opacity: p, transform: `translateY(${(1 - p) * 24}px)` }}>
      <div style={{ background: C.card, border: `2px solid ${C.gold}`, borderRadius: 22, padding: "22px 48px", boxShadow: `0 0 60px ${C.gold}66`, textAlign: "center" }}>
        <div style={{ fontSize: 24, fontWeight: 700, color: C.gold, letterSpacing: 5, textTransform: "uppercase", marginBottom: 8 }}>The strength</div>
        <div style={{ fontSize: 50, fontWeight: 700, color: C.text }}>
          {s.pre}
          <span style={{ color: C.gold }}>{s.v}</span>
          {s.post}
        </div>
      </div>
    </div>
  );
};

const Outro: React.FC<{ cfg: DemoCfg }> = ({ cfg }) => (
  <Fade dur={OUTRO}>
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", paddingBottom: 230 }}>
      <div style={{ display: "flex", gap: 170 }}>
        <div>
          <div style={{ fontSize: 60, fontWeight: 700, color: cfg.a.color, marginBottom: 40 }}>{cfg.a.label}</div>
          {cfg.outro.left.map((it, i) => <Line key={i} item={it} delay={10 + i * 20} />)}
        </div>
        <div>
          <div style={{ fontSize: 60, fontWeight: 700, color: cfg.b.color, marginBottom: 40 }}>{cfg.b.label}</div>
          {cfg.outro.right.map((it, i) => <Line key={i} item={it} delay={20 + i * 20} />)}
        </div>
      </div>
    </AbsoluteFill>
    <Strength s={cfg.outro.strength} />
  </Fade>
);

export const makeDemo = (cfg: DemoCfg) => {
  const A = layout(cfg.a.segs).total;
  const B = layout(cfg.b.segs).total;
  const MAIN = A + GAP + B + HOLD;
  const Main = () => (
    <Fade dur={MAIN}>
      <div style={{ position: "absolute", left: 10, top: 190, display: "flex", gap: 20 }}>
        <Panel side={cfg.a} start={0} end={A} crop={cfg.crop} />
        <Panel side={cfg.b} start={A + GAP} end={A + GAP + B} crop={cfg.crop} keepLit />
      </div>
    </Fade>
  );
  const Demo = () => (
    <>
      <Sequence  durationInFrames={INTRO}><Intro cfg={cfg} /></Sequence>
      <Sequence from={INTRO} durationInFrames={MAIN}><Main /></Sequence>
      <Sequence from={INTRO + MAIN} durationInFrames={OUTRO}><Outro cfg={cfg} /></Sequence>
    </>
  );
  return { Demo, total: INTRO + MAIN + OUTRO };
};
