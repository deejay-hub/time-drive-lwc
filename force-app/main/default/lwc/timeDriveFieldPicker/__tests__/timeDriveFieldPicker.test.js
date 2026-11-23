import { createElement } from "lwc";
import TimeDriveFieldPicker from "c/timeDriveFieldPicker";
import getFields from "@salesforce/apex/TimeDriveSetupController.getFields";

jest.mock("@salesforce/apex/TimeDriveSetupController.getFields", () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-time-drive-field-picker", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("follows a lookup to the related record's fields and picks a path", async () => {
    getFields.mockResolvedValue([
      { name: "Name", label: "Campaign Name", type: "string" },
      { name: "Status", label: "Status", type: "picklist" }
    ]);
    const element = createElement("c-time-drive-field-picker", { is: TimeDriveFieldPicker });
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

  it("follows a lookup to many objects (Related To) into the Name object's fields", async () => {
    getFields.mockResolvedValue([
      { name: "Name", label: "Name", type: "string" },
      { name: "Type", label: "Type", type: "picklist" }
    ]);
    const element = createElement("c-time-drive-field-picker", { is: TimeDriveFieldPicker });
    element.fields = [
      { name: "Subject", label: "Subject", type: "string" },
      { name: "WhatId", label: "Related To ID", type: "reference", relationshipName: "What", polymorphic: true }
    ];
    const picks = [];
    element.addEventListener("pick", (e) => picks.push(e.detail));
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;

    // Not the 18-character ID: a lookup that leads on, to any record.
    const lookup = root.querySelector('.token-result[data-name="WhatId"]');
    expect(lookup.classList.contains("token-result_follow")).toBe(true);
    expect(lookup.textContent).toContain("Related To");
    lookup.click();
    await flush();
    await flush();
    expect(getFields).toHaveBeenCalledWith({ objectName: "Name" });
    root.querySelector('.token-result[data-name="Name"]').click();
    expect(picks[0].path).toBe("What.Name");
    expect(picks[0].label).toBe("Related To › Name");
  });

  it("can start from the lookups alone and list only the types asked for beyond them", async () => {
    getFields.mockResolvedValue([
      { name: "Subject", label: "Subject", type: "string" },
      { name: "ActivityDate", label: "Due Date", type: "date" },
      { name: "CreatedDate", label: "Created Date", type: "datetime" },
      { name: "OwnerId", label: "Owner ID", type: "reference", referenceTo: "User", relationshipName: "Owner" }
    ]);
    const element = createElement("c-time-drive-field-picker", { is: TimeDriveFieldPicker });
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
