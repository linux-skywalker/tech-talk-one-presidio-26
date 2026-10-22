import { AbsoluteFill, Sequence, interpolate, useCurrentFrame } from "remotion";
import { N } from "../numbers";
import { C, Caption, Counter, Fade, Title, useIn } from "./ui";

const S = 30; // frames per second

const Intro = () => {
  const p = useIn(4);
  return (
    <Fade dur={3 * S}>
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", textAlign: "center" }}>
        <div style={{ opacity: p, transform: `translateY(${(1 - p) * 24}px)` }}>
          <div style={{ fontSize: 70, fontWeight: 800 }}>Beyond <span style={{ color: C.green }}>kubectl apply</span></div>
          <div style={{ fontSize: 30, color: C.dim, marginTop: 14 }}>Same model, two ways, one {N.gpu}</div>
        </div>
      </AbsoluteFill>
    </Fade>
  );
};

const Card: React.FC<{ i: number; on: boolean }> = ({ i, on }) => {
  const p = useIn(i * 6);
  return (
    <div style={{ width: 150, height: 90, borderRadius: 14, background: on ? C.green : C.panel, color: on ? "#0b0f14" : C.dim, fontWeight: 700, fontSize: 22, display: "flex", alignItems: "center", justifyContent: "center", opacity: p, transform: `scale(${0.8 + 0.2 * p})` }}>
      model {i + 1}
    </div>
  );
};

const Sharing = () => (
  <Fade dur={10 * S}>
    <Title kicker="Metric 1 of 6" title="Sharing" />
    <div style={{ position: "absolute", top: 170, left: 64, right: 64, display: "flex", flexDirection: "column", gap: 28 }}>
      <div style={{ display: "flex", gap: 14 }}>{Array.from({ length: N.sharing.models }, (_, i) => <Card key={i} i={i} on />)}</div>
      <div style={{ display: "flex", gap: 24 }}>
        <Counter from={N.sharing.aloneBusy} to={N.sharing.sharingBusyBest} delay={50} suffix="%" color={C.green} label="GPU busy, one model alone to six sharing (up to, best of 3 runs)" />
        <Counter to={N.sharing.models} delay={20} suffix=" of 6" size={90} label={`ready on their own in ${N.sharing.readySeconds} s, ${N.sharing.restarts} restarts`} />
        <Counter to={1} delay={30} suffix=" card" size={90} color={C.blue} label="instead of six" />
      </div>
    </div>
    <Caption text="One card, six models, ready without anyone babysitting them" sub={`${N.gpu}. Single runs on a desktop PC.`} />
  </Fade>
);

const Menu = () => {
  const items = [
    { n: "Time slicing", d: "Pods take turns. What we ran.", c: C.green },
    { n: "MPS", d: "Run together, memory limit per pod.", c: C.blue },
    { n: "MIG", d: "Hardware slices on A100 / H100. NVIDIA feature, applied in Kubernetes by the GPU Operator.", c: "#c792ea" },
  ];
  return (
    <Fade dur={6 * S}>
      <Title kicker="Sharing, the menu" title="Three ways to share one GPU" />
      <div style={{ position: "absolute", top: 190, left: 64, right: 64, display: "flex", flexDirection: "row", gap: 24 }}>
        {items.map((it, i) => {
          const p = useIn(i * 14);
          return (
            <div key={it.n} style={{ flex: 1, height: 300, background: C.panel, borderRadius: 20, padding: 28, borderTop: `6px solid ${it.c}`, opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
              <div style={{ fontSize: 40, fontWeight: 800, color: it.c }}>{it.n}</div>
              <div style={{ fontSize: 24, color: C.text, marginTop: 14, lineHeight: 1.35 }}>{it.d}</div>
              {it.n === "MIG" && <div style={{ fontSize: 18, color: C.dim, marginTop: 14 }}>Theory: our RTX 4070 has no MIG.</div>}
            </div>
          );
        })}
      </div>
      <Caption text="One catch on this card: models take turns. NVIDIA's answer is MIG." />
    </Fade>
  );
};

const Failures = () => {
  const f = useCurrentFrame();
  const t = interpolate(f, [30, 30 + N.failures.busyAgainSeconds * 4], [0, N.failures.busyAgainSeconds], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const killed = f >= 30;
  return (
    <Fade dur={8 * S}>
      <Title kicker="Metric 2 of 6" title="Failures" />
      <div style={{ position: "absolute", top: 180, left: 64, right: 64, height: 330, display: "flex", flexDirection: "row", gap: 24 }}>
        <div style={{ flex: 1, background: C.panel, borderRadius: 20, padding: 28 }}>
          <div style={{ fontSize: 26, color: C.dim }}>Traditional, process killed</div>
          <div style={{ fontSize: 64, fontWeight: 800, color: killed ? C.red : C.text, marginTop: 16 }}>{killed ? "stays dead" : "training"}</div>
          <div style={{ fontSize: 22, color: C.dim, marginTop: 8 }}>until a person notices</div>
        </div>
        <div style={{ flex: 1, background: C.panel, borderRadius: 20, padding: 28 }}>
          <div style={{ fontSize: 26, color: C.dim }}>Kubernetes, pod killed</div>
          <div style={{ fontSize: 64, fontWeight: 800, color: C.green, marginTop: 16 }}>{killed ? `${Math.round(t)} s` : "training"}</div>
          <div style={{ fontSize: 22, color: C.dim, marginTop: 8 }}>{t >= N.failures.busyAgainSeconds - 0.5 ? `training again from checkpoint-${N.failures.checkpoint}, nobody involved` : "replacement pod starting"}</div>
        </div>
      </div>
      <Caption text="Restart is built in, for every workload, the same way" sub="Simulated crash on both sides. Single run." />
    </Fade>
  );
};

const Tail = () => (
  <Fade dur={3 * S}>
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", textAlign: "center" }}>
      <div style={{ fontSize: 46, fontWeight: 700 }}>Tools engineers already know,<br /><span style={{ color: C.green }}>applied to the GPU data center</span></div>
    </AbsoluteFill>
  </Fade>
);

export const Preview: React.FC = () => (
  <AbsoluteFill style={{ background: C.bg }}>
    <Sequence from={0} durationInFrames={3 * S}><Intro /></Sequence>
    <Sequence from={3 * S} durationInFrames={10 * S}><Sharing /></Sequence>
    <Sequence from={13 * S} durationInFrames={6 * S}><Menu /></Sequence>
    <Sequence from={19 * S} durationInFrames={8 * S}><Failures /></Sequence>
    <Sequence from={27 * S} durationInFrames={3 * S}><Tail /></Sequence>
  </AbsoluteFill>
);
