import { createElement } from "lwc";
import TimeShiftFieldPicker from "c/timeShiftFieldPicker";
import getFields from "@salesforce/apex/TimeShiftSetupController.getFields";

jest.mock("@salesforce/apex/TimeShiftSetupController.getFields", () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0)); // eslint-disable-line @lwc/lwc/no-async-operation

describe("c-time-shift-field-picker", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("follows a lookup to the related record's fields and picks a path", async () => {
    getFields.mockResolvedValue([
      { name: "Name", label: "Campaign Name", type: "string" },
      { name: "Status", label: "Status", type: "picklist" }
    ]);
    const element = createElement("c-time-shift-field-picker", { is: TimeShiftFieldPicker });
    element.fields = [
      { name: "Status", label: "Status", type: "picklist" },
      {
        name: "CampaignId",
        label: "Campaign ID",
        type: "reference",
        referenceTo: "Campaign",
        relationshipName: "Campaign"
      }
    ];
    const picks = [];
    element.addEventListener("pick", (e) => picks.push(e.detail));
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;

    // The lookup reads "Campaign" and leads on (›).
    const lookup = root.querySelector('.token-result[data-name="CampaignId"]');
    expect(lookup.classList.contains("token-result_follow")).toBe(true);
    expect(lookup.textContent).toContain("Campaign");
    lookup.click();
    await flush();
    await flush();
    expect(getFields).toHaveBeenCalledWith({ objectName: "Campaign" });
    expect(root.querySelector(".token-crumb").textContent).toBe("Campaign");

    root.querySelector('.token-result[data-name="Name"]').click();
    expect(picks).toEqual([{ path: "Campaign.Name", label: "Campaign › Campaign Name", type: "string" }]);

    // Back up to the object's own fields.
    root.querySelector(".token-up").click();
    await flush();
    expect(root.querySelector(".token-crumb")).toBeNull();
  });
});
