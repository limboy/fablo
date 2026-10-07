import type React from "react";
import {
  Interactive,
  interpolate,
  useCurrentFrame,
  type InteractivitySchema,
} from "remotion";
import { C, F } from "./theme";
import { clamp, easeOut } from "./ui";

type HeadlineProps = {
  readonly title: string;
  readonly subtitle: string;
  readonly accentColor: string;
  readonly style?: React.CSSProperties;
};

/** Scene headline above the phone; the title rises in, the subtitle follows. */
const HeadlineInner: React.FC<HeadlineProps> = ({ title, subtitle, accentColor, style }) => {
  const frame = useCurrentFrame();
  return (
    <Interactive.Div
      style={{
        position: "absolute",
        left: 80,
        right: 80,
        top: 110,
        textAlign: "center",
        fontFamily: F.ui,
        ...style,
      }}
    >
      <div
        style={{
          fontSize: 92,
          fontWeight: 800,
          letterSpacing: 2,
          lineHeight: 1.15,
          color: C.ink,
          opacity: interpolate(frame, [0, 14], [0, 1], clamp),
          translate: interpolate(frame, [0, 18], ["0px 40px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        {title}
      </div>
      <div
        style={{
          marginTop: 22,
          fontSize: 44,
          fontWeight: 600,
          color: accentColor,
          opacity: interpolate(frame, [8, 22], [0, 1], clamp),
          translate: interpolate(frame, [8, 26], ["0px 30px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        {subtitle}
      </div>
    </Interactive.Div>
  );
};

const headlineSchema = {
  title: { type: "text-content", default: "", description: "Title" },
  subtitle: { type: "text-content", default: "", description: "Subtitle" },
  accentColor: { type: "color", default: C.accent, description: "Subtitle color" },
} as const satisfies InteractivitySchema;

export const Headline = Interactive.withSchema({
  Component: HeadlineInner,
  componentName: "<Headline>",
  schema: headlineSchema,
  wrapInSequence: true,
});
