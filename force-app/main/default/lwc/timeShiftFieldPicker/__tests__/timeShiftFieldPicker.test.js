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
    expect(picks).toEqual([
      {
        path: "Campaign.Name",
        label: "Campaign › Campaign Name",
        type: "string",
        field: { name: "Name", label: "Campaign Name", type: "string" }
      }
    ]);

    // Back up to the object's own fields.
    root.querySelector(".token-up").click();
    await flush();
    expect(root.querySelector(".token-crumb")).toBeNull();
  });

  it("can start from the lookups alone and list only the types asked for beyond them", async () => {
    getFields.mockResolvedValue([
      { name: "Subject", label: "Subject", type: "string" },
      { name: "ActivityDate", label: "Due Date", type: "date" },
      { name: "CreatedDate", label: "Created Date", type: "datetime" },
      { name: "OwnerId", label: "Owner ID", type: "reference", referenceTo: "User", relationshipName: "Owner" }
    ]);
    const element = createElement("c-time-shift-field-picker", { is: TimeShiftFieldPicker });
    element.fields = [
      { name: "CreatedDate", label: "Created Date", type: "datetime" },
      { name: "TaskId", label: "Task ID", type: "reference", referenceTo: "Task", relationshipName: "Task" },
      { name: "Type", label: "Type", type: "string" }
    ];
    element.rootLookupsOnly = true;
    element.types = ["date", "datetime"];
    const picks = [];
    element.addEventListener("pick", (e) => picks.push(e.detail));
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    const names = () => [...root.querySelectorAll(".token-result")].map((b) => b.dataset.name);

    // The object first: only the lookup, none of the object's own fields.
    expect(names()).toEqual(["TaskId"]);

    // Then its fields: dates, and lookups that lead on; not the text field.
    root.querySelector('.token-result[data-name="TaskId"]').click();
    await flush();
    await flush();
    expect(names()).toEqual(["ActivityDate", "CreatedDate", "OwnerId"]);

    root.querySelector('.token-result[data-name="ActivityDate"]').click();
    expect(picks.map((p) => [p.path, p.type])).toEqual([["Task.ActivityDate", "date"]]);
  });
});
