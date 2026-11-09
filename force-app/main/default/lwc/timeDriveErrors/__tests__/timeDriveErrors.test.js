// isSlds2 reads the page once, so each case loads the module afresh.
const load = () => {
  let mod;
  jest.isolateModules(() => {
    mod = require("c/timeDriveErrors");
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

  it("names the SLDS illustration for a state, and lightning-illustration draws it in the page's SLDS", () => {
    expect(load().illustrationName("setup")).toBe("access:request");
    expect(load().illustrationName("error")).toBe("error:recoverable");
    expect(load().illustrationName("noresults")).toBe("noresults:search");
    expect(load().illustrationName("filtered")).toBe("noresults:filter");
    expect(load().illustrationName("anything else")).toBe("error:recoverable");
  });

  describe("fitIllustrations", () => {
    let callbacks;
    beforeEach(() => {
      callbacks = [];
      global.ResizeObserver = class {
        constructor(callback) {
          callbacks.push(callback);
        }
        observe() {}
      };
    });
    afterEach(() => {
      delete global.ResizeObserver;
    });

    function slotWith(slotHeight, artHeight) {
      const root = document.createElement("div");
      const slot = document.createElement("div");
      slot.className = "illustration";
      const art = document.createElement("lightning-illustration");
      slot.appendChild(art);
      root.appendChild(slot);
      Object.defineProperty(slot, "clientHeight", { value: slotHeight });
      Object.defineProperty(art, "offsetHeight", { value: artHeight });
      return { root, art };
    }

    it("scales a drawing far taller than its slot down to fit, standing on its floor", () => {
      const { root, art } = slotWith(100, 200);
      load().fitIllustrations(root);
      callbacks[0]();
      expect(art.style.transform).toBe("scale(0.8)");
      expect(art.style.transformOrigin).toBe("center bottom");
    });

    it("leaves a drawing within its slot and its empty margin alone, and watches each once", () => {
      const { root, art } = slotWith(100, 150);
      const errors = load();
      errors.fitIllustrations(root);
      errors.fitIllustrations(root);
      expect(callbacks).toHaveLength(1);
      callbacks[0]();
      expect(art.style.transform).toBe("");
    });
  });
});
