import { createElement } from "lwc";
import TimeDriveRecordDetails from "c/timeDriveRecordDetails";
import { getLayout } from "lightning/uiLayoutApi";
import { getRecord } from "lightning/uiRecordApi";

const LAYOUT = {
  sections: [
    {
      layoutRows: [
        {
          layoutItems: [
            { label: "Subject", layoutComponents: [{ componentType: "Field", apiName: "Subject" }] },
            { label: "Priority", layoutComponents: [{ componentType: "Field", apiName: "Priority" }] }
          ]
        },
        {
          layoutItems: [
            { label: "Status", layoutComponents: [{ componentType: "Field", apiName: "Status" }] },
            { label: "Case Number", layoutComponents: [{ componentType: "Field", apiName: "CaseNumber" }] },
            { label: "Secret", layoutComponents: [{ componentType: "Field", apiName: "Secret__c" }] },
            { label: "", layoutComponents: [{ componentType: "EmptySpace" }] }
          ]
        }
      ]
    }
  ]
};
const RECORD = {
  fields: {
    Subject: { value: "Late delivery", displayValue: null },
    Priority: { value: "High", displayValue: "High" },
    Status: { value: "Closed", displayValue: "Closed" },
    CaseNumber: { value: "00001028", displayValue: null }
  }
};

const flush = () => Promise.resolve();

describe("c-time-drive-record-details", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });
  const mount = () => {
    const element = createElement("c-time-drive-record-details", { is: TimeDriveRecordDetails });
    element.recordId = "500000000000001AAA";
    element.objectApiName = "Case";
    document.body.appendChild(element);
    return element;
  };

  it("shows the compact layout's fields in order, with the record's values", async () => {
    const element = mount();
    expect(element.shadowRoot.querySelector(".loading")).not.toBeNull();
    getLayout.emit(LAYOUT);
    getRecord.emit(RECORD);
    await flush();
    const pairs = [...element.shadowRoot.querySelectorAll(".fact")].map((f) => [
      f.querySelector("dt").textContent,
      f.querySelector("dd").textContent
    ]);
    // The field the user can't see (Secret__c) and the blank space are left out.
    expect(pairs).toEqual([
      ["Subject", "Late delivery"],
      ["Priority", "High"],
      ["Status", "Closed"],
      ["Case Number", "00001028"]
    ]);
  });

  it("shows a lookup's Id, without asking the server for its name", async () => {
    const element = mount();
    getLayout.emit({
      sections: [
        {
          layoutRows: [
            {
              layoutItems: [
                { label: "Name", layoutComponents: [{ componentType: "Field", apiName: "WhoId" }] },
                { label: "Store", layoutComponents: [{ componentType: "Field", apiName: "Store__c" }] }
              ]
            }
          ]
        }
      ]
    });
    await flush();
    expect(getRecord.getLastConfig()).toMatchObject({ optionalFields: ["Case.WhoId", "Case.Store__c"] });
    getRecord.emit({
      fields: {
        WhoId: { value: "003HF00000Kc8HCYAZ", displayValue: null },
        Store__c: { value: "a01000000000001AAA", displayValue: null }
      }
    });
    await flush();
    const values = [...element.shadowRoot.querySelectorAll(".fact dd")].map((d) => d.textContent);
    expect(values).toEqual(["003HF00000Kc8HCYAZ", "a01000000000001AAA"]);
  });

  it("asks for the compact layout in view mode, then only its fields", async () => {
    mount();
    await flush();
    expect(getLayout.getLastConfig()).toMatchObject({ objectApiName: "Case", layoutType: "Compact", mode: "View" });
    getLayout.emit(LAYOUT);
    await flush();
    expect(getRecord.getLastConfig()).toMatchObject({
      recordId: "500000000000001AAA",
      optionalFields: ["Case.Subject", "Case.Priority", "Case.Status", "Case.CaseNumber", "Case.Secret__c"]
    });
  });

  it("says so plainly when the details can't load, never with the raw error", async () => {
    const warn = jest.spyOn(console, "warn").mockImplementation(() => {});
    const element = mount();
    getRecord.error([{ errorCode: "INSUFFICIENT_ACCESS", message: "Secret__c on Invoice__c is not accessible" }], 403);
    await flush();
    const error = element.shadowRoot.querySelector(".error");
    expect(error.getAttribute("role")).toBe("alert");
    // No access is for an admin to grant: the setup illustration.
    expect(error.querySelector("lightning-illustration").illustrationName).toBe("access:request");
    expect(error.textContent).toContain("You don't have access to some of the data this needs.");
    expect(error.textContent).not.toContain("Possible cause");
    expect(error.textContent).not.toContain("Secret__c");
    warn.mockRestore();
  });
});
