// isSlds2 reads the page once, so each case loads the module afresh.
const load = () => {
  let mod;
  jest.isolateModules(() => {
    mod = require("c/timeShiftErrors");
  });
  return mod;
};

const withButtonRadius = (radius) => {
  const style = document.createElement("style");
  style.textContent = `.slds-button { border-top-left-radius: ${radius}; }`;
  document.head.appendChild(style);
  return () => style.remove();
};

describe("isSlds2", () => {
  afterEach(() => {
    document.documentElement.style.removeProperty("--slds-g-color-surface-1");
  });

  it("goes by an SLDS button's corners, whatever hooks the page defines", () => {
    // SLDS 1's square-cornered buttons, on a page that defines SLDS 2's hooks too.
    document.documentElement.style.setProperty("--slds-g-color-surface-1", "#ffffff");
    let undo = withButtonRadius("4px");
    expect(load().isSlds2(document.body)).toBe(false);
    undo();
    // SLDS 2's rounded ones.
    undo = withButtonRadius("20px");
    expect(load().isSlds2(document.body)).toBe(true);
    undo();
  });

  it("falls back to SLDS 2's surface hook where there are no SLDS styles", () => {
    const element = document.createElement("div");
    document.body.appendChild(element);
    expect(load().isSlds2(element)).toBe(false);
    element.style.setProperty("--slds-g-color-surface-1", "#ffffff");
    expect(load().isSlds2(element)).toBe(true);
    element.remove();
  });

  it("picks the illustration for the page's SLDS", () => {
    const undo = withButtonRadius("4px");
    expect(load().illustrationUrl("/assets", "setup", document.body)).toBe("/assets/illustrations/slds1/setup.svg");
    undo();
  });
});
