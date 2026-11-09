import { createElement } from "lwc";
import TimeDriveGroup from "c/timeDriveGroup";
import { CurrentPageReference } from "lightning/navigation";
import getGroupPage from "@salesforce/apex/TimeDriveController.getGroupPage";

jest.mock("@salesforce/apex/TimeDriveController.getGroupPage", () => ({ default: jest.fn() }), {
  virtual: true
});

const STATE = {
  c__recordId: "003000000000001AAA",
  c__type: "case",
  c__from: "2026-10-14T09:00:00.000Z",
  c__to: "2026-10-14T17:00:00.000Z",
  c__count: "120",
  c__label: "Case updates"
};

const item = (i) => ({
  id: `500${String(i).padStart(12, "0")}AAA-Cases`,
  recordId: `500${String(i).padStart(12, "0")}AAA`,
  title: `Case ${i}`,
  subtitle: i % 2 ? "Web" : null,
  occurredAt: new Date(Date.UTC(2026, 9, 14, 17, 0) - i * 60000).toISOString(),
  details: [{ label: "Status", value: "New" }, ...(i === 0 ? [{ label: "Priority", value: "High" }] : [])]
});
const page = (from, to, more) => ({
  items: Array.from({ length: to - from }, (_, k) => item(from + k)),
  cursor: `after-${to}`,
  more,
  problems: [],
  label: "Case updates",
  icon: "standard:case",
  dateOnly: false,
  recordName: "Morgan Bramley"
});

const flush = async () => {
  for (let i = 0; i < 4; i++) await Promise.resolve();
};

const mount = async (state = STATE) => {
  const element = createElement("c-time-drive-group", { is: TimeDriveGroup });
  document.body.appendChild(element);
  CurrentPageReference.emit({ type: "standard__component", state });
  await flush();
  return element;
};

describe("c-time-drive-group", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("lists the first page as a related list's View All does", async () => {
    getGroupPage.mockResolvedValueOnce(page(0, 50, true));
    const element = await mount();
    const root = element.shadowRoot;
    expect(getGroupPage).toHaveBeenCalledWith({
      recordId: STATE.c__recordId,
      type: "case",
      fromAt: STATE.c__from,
      toAt: STATE.c__to,
      pageSize: 50,
      cursor: null
    });
    expect(root.querySelector("h1").textContent).toBe("Case updates");
    const back = root.querySelector("a.back");
    expect(back.textContent).toBe("Back to Morgan Bramley");
    expect(back.getAttribute("href")).toBe("/lightning/r/003000000000001AAA/view");
    // The timeline's count until everything is loaded.
    expect(root.querySelector(".meta").textContent).toMatch(/^120 items • Sorted by Date • /);
    const table = root.querySelector("lightning-datatable");
    expect(table.data).toHaveLength(50);
    expect(table.enableInfiniteLoading).toBe(true);
    expect(table.columns.map((c) => c.label)).toEqual(["Name", "Summary", "Status", "Priority", "Date/Time"]);
    expect(table.data[0]).toMatchObject({
      title: "Case 0",
      recordUrl: "/lightning/r/500000000000000AAA/view",
      detail0: "New",
      detail1: "High"
    });
  });

  it("takes its columns from the source alone, with the header waiting for the first page", async () => {
    let deliver;
    getGroupPage.mockReturnValueOnce(
      new Promise((resolve) => {
        deliver = resolve;
      })
    );
    const element = await mount({ ...STATE, c__object: "Case", c__icon: "standard:case" });
    // Asked at once: no layout to wait for.
    expect(getGroupPage).toHaveBeenCalledTimes(1);
    // Meanwhile, the table's shape and a placeholder for the way back.
    const root = element.shadowRoot;
    expect(root.querySelector(".skeleton-table")).toBeTruthy();
    expect(root.querySelector("lightning-datatable")).toBeNull();
    expect(root.querySelector(".skeleton_back")).toBeTruthy();
    // The whole header waits too: no icon or title to change under you.
    expect(root.querySelector(".slds-media__figure lightning-icon")).toBeNull();
    expect(root.querySelector(".skeleton_icon")).toBeTruthy();
    expect(root.querySelector(".skeleton_title")).toBeTruthy();
    deliver(page(0, 2, false));
    await flush();
    const table = root.querySelector("lightning-datatable");
    // The title linking to the record, the subtitle, the admin's detail fields, the date.
    expect(table.columns.map((c) => c.label)).toEqual(["Name", "Summary", "Status", "Priority", "Date/Time"]);
    expect(table.columns[0].type).toBe("url");
    expect(root.querySelector(".skeleton-table")).toBeNull();
    expect(root.querySelector("a.back").textContent).toBe("Back to Morgan Bramley");
    expect(root.querySelector(".slds-media__figure lightning-icon").iconName).toBe("standard:case");
    expect(root.querySelector("h1").textContent).toBe("Case updates");
  });

  it("loads the next page from where the last left off, then stops", async () => {
    getGroupPage.mockResolvedValueOnce(page(0, 50, true)).mockResolvedValueOnce(page(50, 70, false));
    const element = await mount();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    table.dispatchEvent(new CustomEvent("loadmore"));
    await flush();
    expect(getGroupPage).toHaveBeenLastCalledWith(expect.objectContaining({ cursor: "after-50" }));
    expect(table.data).toHaveLength(70);
    expect(table.enableInfiniteLoading).toBe(false);
    // All there: what was found, not the timeline's count.
    expect(element.shadowRoot.querySelector(".meta").textContent).toMatch(/^70 items/);
    table.dispatchEvent(new CustomEvent("loadmore"));
    await flush();
    expect(getGroupPage).toHaveBeenCalledTimes(2);
  });

  it("says so when the items have gone, and when they can't be read", async () => {
    getGroupPage.mockResolvedValueOnce({ ...page(0, 0, false) });
    let element = await mount();
    expect(element.shadowRoot.querySelector(".state-title").textContent).toBe("Nothing to show");
    document.body.removeChild(element);

    getGroupPage.mockRejectedValueOnce({ status: 500, body: { message: "timedrive:busy" } });
    element = await mount({ ...STATE, c__type: "email" });
    expect(element.shadowRoot.querySelector("[role=alert]")).toBeTruthy();
    getGroupPage.mockResolvedValueOnce(page(0, 3, false));
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(element.shadowRoot.querySelector("lightning-datatable").data).toHaveLength(3);
  });
});
