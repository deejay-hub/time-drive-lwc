/**
 * The Look step's colours: exactly the backgrounds Salesforce's own standard
 * icons wear (the 25 distinct ones in @salesforce-ux/design-system 2.264.1's
 * icon styles, named by their SLDS 2 palette tokens), so an item can wear its
 * object's colour or any other the standard icons use. Each carries the
 * timeline's white icon at 3:1 or better. (The 100 custom icons each have a
 * colour of their own and aren't listed.)
 */
export const PALETTE = [
  {
    hue: "Blue",
    shades: [
      { shade: 20, value: "#032D60" },
      { shade: 30, value: "#014486" },
      { shade: 60, value: "#1B96FF" }
    ]
  },
  {
    hue: "Cloud Blue",
    shades: [
      { shade: 30, value: "#084968" },
      { shade: 50, value: "#107CAD" }
    ]
  },
  {
    hue: "Indigo",
    shades: [
      { shade: 30, value: "#2F2CB7" },
      { shade: 50, value: "#5867E8" }
    ]
  },
  {
    hue: "Violet",
    shades: [
      { shade: 20, value: "#481A54" },
      { shade: 40, value: "#9602C7" },
      { shade: 60, value: "#CB65FF" }
    ]
  },
  {
    hue: "Purple",
    shades: [
      { shade: 30, value: "#5A1BA9" },
      { shade: 50, value: "#9050E9" }
    ]
  },
  {
    hue: "Pink",
    shades: [
      { shade: 40, value: "#B60554" },
      { shade: 60, value: "#FF538A" }
    ]
  },
  {
    hue: "Hot Orange",
    shades: [
      { shade: 30, value: "#7E2600" },
      { shade: 60, value: "#FF5D2D" }
    ]
  },
  {
    hue: "Orange",
    shades: [{ shade: 60, value: "#DD7A01" }]
  },
  {
    hue: "Teal",
    shades: [
      { shade: 40, value: "#056764" },
      { shade: 60, value: "#06A59A" }
    ]
  },
  {
    hue: "Green",
    shades: [
      { shade: 40, value: "#396547" },
      { shade: 60, value: "#3BA755" }
    ]
  },
  {
    hue: "Neutral",
    shades: [
      { shade: 40, value: "#5C5C5C" },
      { shade: 60, value: "#939393" }
    ]
  },
  {
    hue: "Brand",
    shades: [
      { shade: "Slack", value: "#4A154B" },
      { shade: "Tableau", value: "#0F1E3C" }
    ]
  }
];
