import { createElement } from "lwc";
import TimeShiftLayoutWarmer from "c/timeShiftLayoutWarmer";
import { getLayout } from "lightning/uiLayoutApi";

describe("c-time-shift-layout-warmer", () => {
  it("asks for the object's compact layout, the request the details make", async () => {
    const element = createElement("c-time-shift-layout-warmer", { is: TimeShiftLayoutWarmer });
    element.objectApiName = "Case";
    document.body.appendChild(element);
    await Promise.resolve();
    expect(getLayout.getLastConfig()).toMatchObject({ objectApiName: "Case", layoutType: "Compact", mode: "View" });
    expect(element.shadowRoot.childNodes.length).toBe(0);
    document.body.removeChild(element);
  });
});
