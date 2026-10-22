import { Composition } from "remotion";
import { Preview } from "./scenes/Preview";

export const MyComposition = () => {
  return <Composition id="Preview" component={Preview} durationInFrames={900} fps={30} width={1280} height={720} />;
};
