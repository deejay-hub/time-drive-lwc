import { detailText, localDetails } from "c/timeDriveFormat";

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
});
