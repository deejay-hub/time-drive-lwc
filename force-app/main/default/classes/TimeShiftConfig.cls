/**
 * Reads the Time Trail Source records: which sources plot for a record
 * page, in sequence, the provider for each, and their detail fields.
 */
public with sharing class TimeShiftConfig {
  // Tests stand in their own sources and detail fields here.
  @TestVisible
  private static List<Time_Shift_Source__mdt> testSources;
  @TestVisible
  private static Map<String, List<Time_Shift_Detail_Field__mdt>> testDetailFields;

  private static Map<String, List<Time_Shift_Detail_Field__mdt>> detailFieldsBySource;

  // Tests stand in their own highlights, by source, here.
  @TestVisible
  private static Map<String, List<Time_Shift_Highlight__mdt>> testHighlights;
  private static Map<String, List<Time_Shift_Highlight__mdt>> highlightsBySource;

  /** Active sources for the parent object, by Sequence. */
  public static List<Time_Shift_Source__mdt> sources(String parentObject) {
    List<SourceOrder> ordered = new List<SourceOrder>();
    for (Time_Shift_Source__mdt s : allSources().values()) {
      if (s.Active__c && s.Parent_Object__c == parentObject) {
        ordered.add(new SourceOrder(s));
      }
    }
    ordered.sort();
    List<Time_Shift_Source__mdt> result = new List<Time_Shift_Source__mdt>();
    for (SourceOrder o : ordered) {
      result.add(o.source);
    }
    return result;
  }

  /**
   * The source's provider: a TimeShiftRowProvider (rows the record
   * plots) or a TimeShiftProvider (finished events). With no Provider
   * Class, Salesforce sources use the generic SOQL provider and Data 360
   * sources the Data 360 one; Apex sources must name their class.
   */
  public static Object providerFor(Time_Shift_Source__mdt source, List<String> warnings) {
    String kind = new TimeShiftContext(null, null, null, source, null, null).kind();
    if (String.isBlank(source.Provider_Class__c)) {
      if (kind == TimeShiftContext.KIND_DATA_360) {
        return new TimeShiftData360Provider();
      }
      if (kind == TimeShiftContext.KIND_APEX) {
        warnings.add(String.format(Label.Time_Shift_Server_Apex_Needs_Class, new List<String>{ source.Label }));
        return null;
      }
      return new TimeShiftSoqlProvider();
    }
    Type providerType = Type.forName(source.Provider_Class__c);
    Object instance = providerType == null ? null : providerType.newInstance();
    if (instance instanceof TimeShiftRowProvider || instance instanceof TimeShiftProvider) {
      return instance;
    }
    warnings.add(
      String.format(Label.Time_Shift_Server_Bad_Provider, new List<String>{ source.Label, source.Provider_Class__c })
    );
    return null;
  }

  // ---- the timeline's views ------------------------------------------------

  public static final String ALL_VIEW = 'All';
  @TestVisible
  private static List<Time_Shift_View__mdt> testViews;

  /** The views, All first, then by Sequence. */
  public static List<Time_Shift_View__mdt> views() {
    List<Time_Shift_View__mdt> all = testViews != null ? testViews : Time_Shift_View__mdt.getAll().values();
    List<ViewOrder> ordered = new List<ViewOrder>();
    for (Time_Shift_View__mdt v : all) {
      ordered.add(new ViewOrder(v));
    }
    ordered.sort();
    List<Time_Shift_View__mdt> out = new List<Time_Shift_View__mdt>();
    for (ViewOrder o : ordered) {
      out.add(o.view);
    }
    return out;
  }

  /** The views the picker offers: All, and every active one. */
  public static List<Time_Shift_View__mdt> activeViews() {
    List<Time_Shift_View__mdt> out = new List<Time_Shift_View__mdt>();
    for (Time_Shift_View__mdt v : views()) {
      if (isActive(v)) {
        out.add(v);
      }
    }
    return out;
  }

  /** Whether a view is offered: All always; others unless made inactive. */
  public static Boolean isActive(Time_Shift_View__mdt v) {
    return v.DeveloperName == ALL_VIEW || v.getPopulatedFieldsAsMap().get('Active__c') != false;
  }

  /** A view's picker label in the viewer's language: its Menu Label (or a custom label's), else its label. */
  public static String viewLabel(Time_Shift_View__mdt v) {
    String raw = v.Menu_Label__c?.trim();
    String out = String.isNotBlank(raw) && raw.startsWith(LABEL_PREFIX)
      ? customLabel(raw.substring(LABEL_PREFIX.length()))
      : raw;
    return String.isBlank(out) ? v.Label : out;
  }

  private class ViewOrder implements Comparable {
    Time_Shift_View__mdt view;
    ViewOrder(Time_Shift_View__mdt view) {
      this.view = view;
    }
    Decimal rank() {
      return view.DeveloperName == ALL_VIEW ? -1 : (view.Sequence__c == null ? 1000 : view.Sequence__c);
    }
    public Integer compareTo(Object other) {
      Decimal a = rank();
      Decimal b = ((ViewOrder) other).rank();
      return a == b ? view.Label.compareTo(((ViewOrder) other).view.Label) : (a < b ? -1 : 1);
    }
  }

  // A legend name that's a custom label: $Label.Timeline_Follow_ups.
  public static final String LABEL_PREFIX = '$Label.';
  private static Map<String, String> legendLabels = new Map<String, String>();

  /**
   * What the legend and filters call a source's items, in the viewer's
   * language: a custom label's translation ($Label.Name), the words typed
   * (one language), or, left blank, the object's plural name (Salesforce
   * translates those); else the source's own name.
   */
  public static String legendLabel(Time_Shift_Source__mdt s) {
    if (s == null) {
      return null;
    }
    String raw = s.getPopulatedFieldsAsMap().containsKey('Event_Label__c') ? s.Event_Label__c?.trim() : null;
    String key = s.DeveloperName + '|' + raw + '|' + s.Object_Name__c;
    if (legendLabels.containsKey(key)) {
      return legendLabels.get(key);
    }
    String out;
    if (String.isNotBlank(raw) && raw.startsWith(LABEL_PREFIX)) {
      out = customLabel(raw.substring(LABEL_PREFIX.length()));
    } else if (String.isNotBlank(raw)) {
      out = raw;
    } else if (new TimeShiftContext(null, null, null, s, null, null).kind() == TimeShiftContext.KIND_SALESFORCE) {
      out = objectPlural(s.Object_Name__c);
    }
    if (String.isBlank(out)) {
      out = s.Label;
    }
    legendLabels.put(key, out);
    return out;
  }

  /** A custom label in the viewer's language, or null when there's none by that name. */
  public static String customLabel(String name) {
    if (String.isBlank(name)) {
      return null;
    }
    try {
      return System.Label.get('', name.trim());
    } catch (Exception e) {
      return null;
    }
  }

  private static String objectPlural(String objectName) {
    try {
      return String.isBlank(objectName)
        ? null
        : Schema.describeSObjects(new List<String>{ objectName })[0].getLabelPlural();
    } catch (Exception e) {
      return null;
    }
  }

  private static Map<String, Schema.SObjectType> typesByName = new Map<String, Schema.SObjectType>();

  private static Map<String, Schema.DescribeSObjectResult> described = new Map<String, Schema.DescribeSObjectResult>();

  /**
   * An object's describe, kept for the request: the source's query, its
   * highlights and its rows all ask for the same one. Throws for a name that
   * isn't an object, as Schema.describeSObjects does.
   */
  public static Schema.DescribeSObjectResult describeObject(String objectName) {
    String key = objectName.toLowerCase();
    Schema.DescribeSObjectResult found = described.get(key);
    if (found == null) {
      found = Schema.describeSObjects(new List<String>{ objectName })[0];
      described.put(key, found);
    }
    return found;
  }

  private static Map<String, Map<String, Schema.SObjectField>> fieldMaps = new Map<String, Map<String, Schema.SObjectField>>();
  private static Map<String, Schema.DescribeFieldResult> fieldDescribes = new Map<String, Schema.DescribeFieldResult>();
  private static Map<Schema.SObjectType, Schema.DescribeSObjectResult> describedTypes = new Map<Schema.SObjectType, Schema.DescribeSObjectResult>();

  /**
   * An object's fields by lower-case name, built once for the request:
   * fields.getMap() rebuilds the whole map on every call, which in an object
   * with hundreds of fields is a measurable cost each time.
   */
  public static Map<String, Schema.SObjectField> fieldMap(String objectName) {
    String key = objectName.toLowerCase();
    Map<String, Schema.SObjectField> found = fieldMaps.get(key);
    if (found == null) {
      found = describeObject(objectName).fields.getMap();
      fieldMaps.put(key, found);
    }
    return found;
  }

  /**
   * One field's describe, kept for the request (getDescribe() on a field is
   * not free either). Null when the object has no such field.
   */
  public static Schema.DescribeFieldResult fieldDescribe(String objectName, String fieldName) {
    if (String.isBlank(fieldName)) {
      return null;
    }
    String key = (objectName + '.' + fieldName).toLowerCase();
    Schema.DescribeFieldResult found = fieldDescribes.get(key);
    if (found == null) {
      Schema.SObjectField f = fieldMap(objectName).get(fieldName.toLowerCase());
      if (f == null) {
        return null;
      }
      found = f.getDescribe();
      fieldDescribes.put(key, found);
    }
    return found;
  }

  /** A type's describe, kept for the request, for record Ids and lookup targets. */
  public static Schema.DescribeSObjectResult describeType(Schema.SObjectType type) {
    Schema.DescribeSObjectResult found = describedTypes.get(type);
    if (found == null) {
      found = type.getDescribe();
      describedTypes.put(type, found);
      described.put(found.getName().toLowerCase(), found);
    }
    return found;
  }

  /**
   * An object by API name, described by name (Data 360's DMOs can be, though
   * the global describe doesn't list them in every org). Null when there's no
   * such object.
   */
  public static Schema.SObjectType sObjectType(String name) {
    if (String.isBlank(name)) {
      return null;
    }
    String key = name.toLowerCase();
    if (typesByName.containsKey(key)) {
      return typesByName.get(key);
    }
    // By name: the org's global describe lists thousands of objects and costs
    // 150 to 400 ms in a big org, on every request.
    Schema.SObjectType t;
    try {
      t = describeObject(name).getSObjectType();
    } catch (Exception e) {
      t = null;
    }
    typesByName.put(key, t);
    return t;
  }

  /** Every source by DeveloperName: the org's, or a test's stand-ins. */
  public static Map<String, Time_Shift_Source__mdt> allSources() {
    if (testSources == null) {
      return Time_Shift_Source__mdt.getAll();
    }
    Map<String, Time_Shift_Source__mdt> out = new Map<String, Time_Shift_Source__mdt>();
    for (Time_Shift_Source__mdt s : testSources) {
      out.put(s.DeveloperName, s);
    }
    return out;
  }

  public static Time_Shift_Source__mdt source(String developerName) {
    return String.isBlank(developerName) ? null : allSources().get(developerName);
  }

  /**
   * A source's detail field records as stored, blanked ones too (the setup
   * wizard reuses their names), by Sequence.
   */
  public static List<Time_Shift_Detail_Field__mdt> storedDetailFields(String sourceDeveloperName) {
    if (testDetailFields != null) {
      return testDetailFields.containsKey(sourceDeveloperName)
        ? testDetailFields.get(sourceDeveloperName)
        : new List<Time_Shift_Detail_Field__mdt>();
    }
    return [
      SELECT DeveloperName, Label, Field__c, Format__c, Sequence__c
      FROM Time_Shift_Detail_Field__mdt
      WHERE Source__r.DeveloperName = :sourceDeveloperName
      ORDER BY Sequence__c, Label
    ];
  }

  /**
   * A source's highlight records as stored, blanked ones too (the setup
   * wizard reuses their names), by Sequence.
   */
  public static List<Time_Shift_Highlight__mdt> storedHighlights(String sourceDeveloperName) {
    if (testHighlights != null) {
      return testHighlights.containsKey(sourceDeveloperName)
        ? testHighlights.get(sourceDeveloperName)
        : new List<Time_Shift_Highlight__mdt>();
    }
    return [
      SELECT DeveloperName, Label, Field__c, Values__c, Icon__c, Colour__c, Sequence__c
      FROM Time_Shift_Highlight__mdt
      WHERE Source__r.DeveloperName = :sourceDeveloperName
      ORDER BY Sequence__c, Label
    ];
  }

  // Highlights and detail fields in Sequence order (blank last), then Label.
  private class BySequenceThenLabel implements System.Comparator<SObject> {
    public Integer compare(SObject a, SObject b) {
      Decimal sa = (Decimal) a.get('Sequence__c');
      Decimal sb = (Decimal) b.get('Sequence__c');
      if (sa != sb) {
        if (sa == null) {
          return 1;
        }
        if (sb == null) {
          return -1;
        }
        return sa < sb ? -1 : 1;
      }
      String la = (String) a.get('Label');
      String lb = (String) b.get('Label');
      return la == null ? (lb == null ? 0 : -1) : (lb == null ? 1 : la.compareTo(lb));
    }
  }

  /** The source's highlights in use, by Sequence (read once for all sources). */
  public static List<Time_Shift_Highlight__mdt> highlights(String sourceDeveloperName) {
    if (testHighlights != null) {
      return storedHighlights(sourceDeveloperName);
    }
    if (highlightsBySource == null) {
      highlightsBySource = new Map<String, List<Time_Shift_Highlight__mdt>>();
      // getAll costs no query; the order is the same as it was in SOQL.
      List<Time_Shift_Highlight__mdt> stored = Time_Shift_Highlight__mdt.getAll().values();
      stored.sort(new BySequenceThenLabel());
      for (Time_Shift_Highlight__mdt h : stored) {
        // Removed in the setup wizard: left with no field.
        if (String.isBlank(h.Field__c)) {
          continue;
        }
        String key = h.Source__r.DeveloperName;
        if (!highlightsBySource.containsKey(key)) {
          highlightsBySource.put(key, new List<Time_Shift_Highlight__mdt>());
        }
        highlightsBySource.get(key).add(h);
      }
    }
    List<Time_Shift_Highlight__mdt> found = highlightsBySource.get(sourceDeveloperName);
    return found == null ? new List<Time_Shift_Highlight__mdt>() : found;
  }

  /** The source's Time Trail Detail Field records, by Sequence. */
  public static List<Time_Shift_Detail_Field__mdt> detailFields(String sourceDeveloperName) {
    if (testDetailFields != null) {
      return testDetailFields.containsKey(sourceDeveloperName)
        ? testDetailFields.get(sourceDeveloperName)
        : new List<Time_Shift_Detail_Field__mdt>();
    }
    if (detailFieldsBySource == null) {
      detailFieldsBySource = new Map<String, List<Time_Shift_Detail_Field__mdt>>();
      List<Time_Shift_Detail_Field__mdt> stored = Time_Shift_Detail_Field__mdt.getAll().values();
      stored.sort(new BySequenceThenLabel());
      for (Time_Shift_Detail_Field__mdt d : stored) {
        // Removed in the setup wizard: Apex can't delete metadata records,
        // so a removed detail field is left with no field.
        if (String.isBlank(d.Field__c)) {
          continue;
        }
        String key = d.Source__r.DeveloperName;
        if (!detailFieldsBySource.containsKey(key)) {
          detailFieldsBySource.put(key, new List<Time_Shift_Detail_Field__mdt>());
        }
        detailFieldsBySource.get(key).add(d);
      }
    }
    List<Time_Shift_Detail_Field__mdt> found = detailFieldsBySource.get(sourceDeveloperName);
    return found == null ? new List<Time_Shift_Detail_Field__mdt>() : found;
  }

  private class SourceOrder implements Comparable {
    Time_Shift_Source__mdt source;

    SourceOrder(Time_Shift_Source__mdt source) {
      this.source = source;
    }

    public Integer compareTo(Object other) {
      Decimal mine = source.Sequence__c == null ? 0 : source.Sequence__c;
      Decimal theirs = ((SourceOrder) other).source.Sequence__c == null ? 0 : ((SourceOrder) other).source.Sequence__c;
      return mine == theirs ? 0 : (mine < theirs ? -1 : 1);
    }
  }
}
