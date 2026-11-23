/**
 * Highlights: a small icon on an item when a checkbox field is checked (high
 * priority, escalated, VIP). The field is read with the item's own query, so a
 * highlight costs a column, not a request. An Apex source's highlight is the
 * key (or field path) it names, marked where the row's value is true.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class TimeDriveHighlights {
  /** One highlight per source. */
  public static final Integer MAX_RULES = 1;

  /** A rule ready to test rows against. */
  public class Rule {
    public String field;
    public String icon;
    public String colour;
    // The field's label in the user's language: what the icon says (an Apex
    // source's: worked out from each row, or the key itself).
    public String fieldLabel;
  }

  // A key or field path, as an Apex source's highlight names it.
  private static final Pattern KEY_PATTERN = Pattern.compile('[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*');

  /**
   * An Apex source's rules: the key or field path each names, at most
   * MAX_RULES. Its rows say what's there, so nothing is described up front.
   * @param stored the saved highlight records for the source
   * @return the rules to apply
   */
  public static List<Rule> rulesForRows(List<Time_Drive_Highlight__mdt> stored) {
    List<Rule> out = new List<Rule>();
    for (Time_Drive_Highlight__mdt h : stored == null ? new List<Time_Drive_Highlight__mdt>() : stored) {
      String key = h.Field__c?.trim();
      if (out.size() >= MAX_RULES || String.isBlank(key) || !KEY_PATTERN.matcher(key).matches()) {
        continue;
      }
      Rule r = new Rule();
      r.field = key;
      r.icon = String.isBlank(h.Icon__c) ? 'dot' : h.Icon__c;
      r.colour = String.isBlank(h.Colour__c) ? null : h.Colour__c;
      out.add(r);
    }
    return out;
  }

  /**
   * The source's rules whose checkbox the user can read (one they can't would fail the whole
   * query), at most MAX_RULES. Other kinds of field are left out.
   * @param objectName the API name of the source's object
   * @param stored the saved highlight records for the source
   * @return the rules to apply
   */
  public static List<Rule> rulesFor(String objectName, List<Time_Drive_Highlight__mdt> stored) {
    List<Rule> out = new List<Rule>();
    if (stored == null || stored.isEmpty() || String.isBlank(objectName)) {
      return out;
    }
    try {
      TimeDriveConfig.fieldMap(objectName);
    } catch (Exception e) {
      return out;
    }
    for (Time_Drive_Highlight__mdt h : stored) {
      if (out.size() >= MAX_RULES) {
        break;
      }
      if (String.isBlank(h.Field__c)) {
        continue;
      }
      Schema.DescribeFieldResult fd = TimeDriveConfig.fieldDescribe(objectName, h.Field__c);
      if (fd == null) {
        continue;
      }
      if (!fd.isAccessible() || fd.getType() != Schema.DisplayType.BOOLEAN) {
        continue;
      }
      Rule r = new Rule();
      // A field reached through a lookup keeps its path (Task.IsClosed).
      r.field = (TimeDriveConfig.pathField(objectName, h.Field__c)?.prefix ?? '') + fd.getName();
      r.icon = String.isBlank(h.Icon__c) ? 'dot' : h.Icon__c;
      r.colour = String.isBlank(h.Colour__c) ? null : h.Colour__c;
      r.fieldLabel = fd.getLabel();
      out.add(r);
    }
    return out;
  }

  /**
   * The fields the rules read, for the item's query.
   * @param rules the rules in use
   * @return the field paths to select
   */
  public static Set<String> fieldsOf(List<Rule> rules) {
    Set<String> out = new Set<String>();
    for (Rule r : rules) {
      out.add(r.field);
    }
    return out;
  }

  /**
   * The icons a row earns; null for none.
   * @param rules the rules in use
   * @param row the row to test
   * @return the flags for the checked fields, or null
   */
  public static List<TimeDriveController.Flag> flagsFor(List<Rule> rules, TimeDriveRow row) {
    List<TimeDriveController.Flag> out;
    for (Rule r : rules) {
      if (!isTrue(row, r.field)) {
        continue;
      }
      if (out == null) {
        out = new List<TimeDriveController.Flag>();
      }
      out.add(new TimeDriveController.Flag(r.icon, r.colour, r.fieldLabel ?? row.labelOf(r.field)));
    }
    return out;
  }

  // The row's value is true: an Apex source's own query may not have read
  // the field, which counts as not.
  private static Boolean isTrue(TimeDriveRow row, String field) {
    try {
      return row.get(field) == true;
    } catch (Exception e) {
      return false;
    }
  }
}
