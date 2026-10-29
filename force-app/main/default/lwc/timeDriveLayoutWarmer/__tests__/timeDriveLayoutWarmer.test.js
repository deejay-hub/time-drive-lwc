import { createElement } from "lwc";
import TimeDriveLayoutWarmer from "c/timeDriveLayoutWarmer";
import { getLayout } from "lightning/uiLayoutApi";

describe("c-time-drive-layout-warmer", () => {
  it("asks for the object's compact layout, the request the details make", async () => {
    const element = createElement("c-time-drive-layout-warmer", { is: TimeDriveLayoutWarmer });
    element.objectApiName = "Case";
    document.body.appendChild(element);
    await Promise.resolve();
    expect(getLayout.getLastConfig()).toMatchObject({ objectApiName: "Case", layoutType: "Compact", mode: "View" });
    expect(element.shadowRoot.childNodes.length).toBe(0);
    document.body.removeChild(element);
  });
});
