import { detailText, localDetails, ownWords, sentToText } from "c/timeDriveFormat";

describe("c-time-drive-format", () => {
  it("writes money in its own currency", () => {
    const text = detailText({ value: "EUR 1,234.50", amount: 1234.5, currencyCode: "EUR" });
    expect(text).toBe(new Intl.NumberFormat("en-US", { style: "currency", currency: "EUR" }).format(1234.5));
  });

  it("groups plain numbers and keeps their decimals", () => {
    expect(detailText({ value: "2713.31", amount: 2713.31 })).toBe("2,713.31");
  });

  it("keeps text as the server wrote it", () => {
    expect(detailText({ value: "Closed Won" })).toBe("Closed Won");
  });

  it("falls back to the server's text for a currency the browser doesn't know", () => {
    expect(detailText({ value: "XX 5", amount: 5, currencyCode: "not a code" })).toBe("XX 5");
  });

  it("formats only the details that carry an amount", () => {
    const text = { label: "Stage", value: "Prospecting" };
    const [first, second] = localDetails([text, { label: "Quantity", value: "1200", amount: 1200 }]);
    expect(first).toBe(text);
    expect(second).toEqual({ label: "Quantity", value: "1,200", amount: 1200 });
    expect(localDetails(undefined)).toBeUndefined();
  });

  it("words an email's recipients itself, whatever Apex sent", () => {
    // Apex's text is only translated once the language is Active; the card's always.
    expect(sentToText({ sentTo: "Sam Lee", sentToOthers: 0 })).toBe("Sent to: Sam Lee");
    expect(sentToText({ sentTo: "Sam Lee", sentToOthers: 1 })).toBe("Sent to: Sam Lee and 1 other");
    expect(sentToText({ sentTo: "Sam Lee", sentToOthers: 2 })).toBe("Sent to: Sam Lee and 2 others");
    expect(sentToText({ subtitle: "Open" })).toBeNull();
  });

  it("shows its own copy of a Time Drive label the server names, else the server's text", () => {
    const email = {
      typeLabel: "SERVER",
      typeLabelName: "Time_Drive_Legend_Emails",
      subtitle: "SERVER",
      sentTo: "Sam Lee",
      sentToOthers: 2
    };
    expect(ownWords(email)).toMatchObject({ typeLabel: "Emails", subtitle: "Sent to: Sam Lee and 2 others" });
    // A name an admin typed, or a label the card doesn't know: as sent.
    expect(ownWords({ typeLabel: "Site visits", subtitle: "Open" })).toMatchObject({
      typeLabel: "Site visits",
      subtitle: "Open"
    });
    expect(ownWords({ typeLabel: "Mine", typeLabelName: "My_Own_Label" }).typeLabel).toBe("Mine");
    // Nothing to change: the same event.
    const plain = { typeLabel: "Calls" };
    expect(ownWords(plain)).toBe(plain);
  });
});
