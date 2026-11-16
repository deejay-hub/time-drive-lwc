import { LightningElement, api } from "lwc";
import getFields from "@salesforce/apex/TimeDriveSetupController.getFields";

// SOQL reaches five lookups up from an object.
const MAX_DEPTH = 5;
// Fields fetched for related objects, shared by every picker on the page.
const related = new Map();

// A lookup's name without its "ID": "Campaign ID" reads "Campaign".
// The object a lookup leads to: its own, or for a lookup to many (a task's
// Related To) the Name object, whose fields a query reads through any of them.
export function lookupTarget(field) {
  return field?.referenceTo || (field?.polymorphic ? "Name" : null);
}

export function lookupLabel(field) {
  return (field?.label ?? "").replace(/\s+ID$/i, "");
}

/**
 * Time Drive Setup's field picker. It searches an object's fields; a lookup
 * (›) goes into the related record's fields, so a CampaignMember's
 * timeline can show {Campaign.Name}. Picking says so with a pick event:
 * { path: "Campaign.Name", label: "Campaign › Name" }.
 */
export default class TimeDriveFieldPicker extends LightningElement {
  // The object's own fields (the wizard has them already).
  @api fields = [];
  @api label = "Search fields";
  // Leave out lookups (a detail field, say, can still be one of them).
  @api noLookups = false;
  // Start from the lookups alone, so the object is chosen first and its
  // fields second: the first list stays short.
  @api rootLookupsOnly = false;
  // Only fields of these types (date, datetime ...) are listed beside the
  // lookups, which lead on to more of them.
  @api types = [];
  // A lookup to follow at once, so the list opens on that record's fields.
  @api startAt;

  query = "";
  // The lookups followed so far: [{ relationshipName, objectName, label }].
  trail = [];
  loading = false;
  failed = false;
  levelFields;

  connectedCallback() {
    if (lookupTarget(this.startAt) && this.startAt?.relationshipName) this.follow(this.startAt);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => this.template.querySelector(".token-input")?.focus());
  }

  get current() {
    return this.trail.length ? (this.levelFields ?? []) : (this.fields ?? []);
  }

  get atRoot() {
    return this.trail.length === 0;
  }

  get crumbs() {
    return this.trail.map((t, i) => ({ key: `${i}-${t.relationshipName}`, label: t.label }));
  }

  get results() {
    const term = this.query.trim().toLowerCase();
    const deep = this.trail.length >= MAX_DEPTH - 1;
    return this.current
      .filter((f) => f.type !== "address" && f.type !== "location")
      .filter((f) => this.listed(f))
      .filter((f) => !term || f.label.toLowerCase().includes(term) || f.name.toLowerCase().includes(term))
      .slice(0, 40)
      .map((f) => {
        const follows = Boolean(lookupTarget(f) && f.relationshipName) && !deep && !this.noLookups;
        const label = follows ? lookupLabel(f) : f.label;
        const at = term ? label.toLowerCase().indexOf(term) : -1;
        return {
          key: f.name,
          name: f.name,
          follows,
          detail: follows ? (f.referenceTo ?? "Any record") : f.name,
          before: at < 0 ? label : label.slice(0, at),
          match: at < 0 ? "" : label.slice(at, at + term.length),
          after: at < 0 ? "" : label.slice(at + term.length),
          className: `token-result${follows ? " token-result_follow" : ""}`,
          ariaLabel: follows ? `${label}: show its fields` : label
        };
      });
  }

  // Whether a field is on the list: a lookup always (unless lookups are off),
  // another field unless the root is lookups only or its type isn't asked for.
  listed(f) {
    const lookup = Boolean(lookupTarget(f) && f.relationshipName) && !this.noLookups;
    if (lookup) return true;
    if (this.atRoot && this.rootLookupsOnly) return false;
    return !this.types?.length || this.types.includes(f.type);
  }

  get empty() {
    return !this.loading && !this.failed && this.results.length === 0;
  }

  handleQuery(event) {
    this.query = event.target.value ?? "";
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.stopPropagation();
      this.dispatchEvent(new CustomEvent("close"));
    } else if (event.key === "Enter") {
      event.preventDefault();
      const first = this.results[0];
      if (first) this.choose(first.name);
    } else if (event.key === "Backspace" && !this.query && this.trail.length) {
      this.up();
    }
  }

  handleResult(event) {
    this.choose(event.currentTarget.dataset.name);
  }

  handleUp() {
    this.up();
  }

  choose(name) {
    const field = this.current.find((f) => f.name === name);
    if (!field) return;
    const follows =
      lookupTarget(field) && field.relationshipName && this.trail.length < MAX_DEPTH - 1 && !this.noLookups;
    if (follows) {
      this.follow(field);
      return;
    }
    const path = [...this.trail.map((t) => t.relationshipName), field.name].join(".");
    const label = [...this.trail.map((t) => t.label), field.label].join(" › ");
    this.dispatchEvent(new CustomEvent("pick", { detail: { path, label, type: field.type, field } }));
  }

  async follow(field) {
    this.trail = [
      ...this.trail,
      { relationshipName: field.relationshipName, objectName: lookupTarget(field), label: lookupLabel(field) }
    ];
    this.query = "";
    const input = this.template.querySelector(".token-input");
    if (input) input.value = "";
    await this.load(lookupTarget(field));
    input?.focus();
  }

  async up() {
    this.trail = this.trail.slice(0, -1);
    this.query = "";
    const last = this.trail[this.trail.length - 1];
    if (last) await this.load(last.objectName);
    this.template.querySelector(".token-input")?.focus();
  }

  async load(objectName) {
    this.failed = false;
    if (!related.has(objectName)) {
      this.loading = true;
      this.levelFields = [];
      try {
        related.set(objectName, await getFields({ objectName }));
      } catch {
        this.failed = true;
      }
      this.loading = false;
    }
    this.levelFields = related.get(objectName) ?? [];
  }
}
