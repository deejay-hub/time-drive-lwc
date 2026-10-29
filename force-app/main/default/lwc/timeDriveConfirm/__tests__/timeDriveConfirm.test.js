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
});
