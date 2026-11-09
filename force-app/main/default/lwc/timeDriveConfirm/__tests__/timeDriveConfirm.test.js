import { createElement } from "lwc";
import TimeDriveConfirm from "c/timeDriveConfirm";

describe("c-time-drive-confirm", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  const mount = () => {
    const element = createElement("c-time-drive-confirm", { is: TimeDriveConfirm });
    element.title = "Delete Event";
    element.message = "Are you sure you want to delete this event?";
    element.confirmLabel = "Delete";
    document.body.appendChild(element);
    return element;
  };

  it("asks the question with Cancel and Delete, and answers false or true", () => {
    const element = mount();
    const root = element.shadowRoot;
    expect(root.querySelector("lightning-modal-header").label).toBe("Delete Event");
    expect(root.querySelector(".message").textContent).toBe("Are you sure you want to delete this event?");
    const buttons = [...root.querySelectorAll("lightning-button")];
    expect(buttons.map((b) => b.label)).toEqual(["Cancel", "Delete"]);
    expect(buttons[1].variant).toBe("brand");
  });

  it("with an acknowledgement, waits for the box to be ticked", async () => {
    const element = createElement("c-time-drive-confirm", { is: TimeDriveConfirm });
    element.title = "Before you save an Apex source";
    element.message = "This class runs every time a timeline loads.";
    element.acknowledgement = "I've thought about how this class scales.";
    element.confirmLabel = "Save";
    document.body.appendChild(element);
    const root = element.shadowRoot;
    const box = root.querySelector("lightning-input.acknowledge");
    expect(box.label).toBe("I've thought about how this class scales.");
    const confirm = root.querySelector("lightning-button.confirm");
    expect(confirm.disabled).toBe(true);
    box.checked = true;
    box.dispatchEvent(new CustomEvent("change"));
    await Promise.resolve();
    expect(confirm.disabled).toBe(false);
  });

  it("has no box, and nothing to wait for, without one", () => {
    const root = mount().shadowRoot;
    expect(root.querySelector("lightning-input.acknowledge")).toBeNull();
    expect(root.querySelector("lightning-button.confirm").disabled).toBe(false);
  });
});
