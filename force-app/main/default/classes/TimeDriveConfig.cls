/**
 * Reads the Time Drive Source records: which sources plot for a record
 * page, in sequence, the provider for each, and their detail fields.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessivePublicCount')
public with sharing class TimeDriveConfig {
  // Tests stand in their own sources and detail fields here.
  @TestVisible
  private static List<Time_Drive_Source__mdt> testSources;
  @TestVisible
  private static Map<String, List<Time_Drive_Detail_Field__mdt>> testDetailFields;

  // Tests stand in their own highlights, by source, here.
  @TestVisible
  private static Map<String, List<Time_Drive_Highlight__mdt>> testHighlights;

  // ---- the timeline's views ------------------------------------------------

  public static final String ALL_VIEW = 'All';
  // The Overdue lens, by its API name (its label can be translated or renamed).
  public static final String OVERDUE_VIEW = 'Overdue';
  @TestVisible
  private static List<Time_Drive_View__mdt> testViews;

  // A legend name that's a custom label: $Label.Timeline_Follow_ups.
  public static final String LABEL_PREFIX = '$Label.';
  // Objects whose plural name says little (Content Document Links), and the
  // custom label a source of theirs is named with unless it says otherwise.
  // Setup starts such a source on it too.
  public static final Map<String, String> DEFAULT_LEGEND_LABELS = new Map<String, String>{
    'contentdocumentlink' => 'Time_Drive_Legend_Files'
  };
  // Or another object's name, as Salesforce translates it: $Object.Task (a
  // TaskRelation source reading "Tasks").
  public static final String OBJECT_PREFIX = '$Object.';
  private static Map<String, String> legendLabels = new Map<String, String>();

  private static Map<String, Schema.SObjectType> typesByName = new Map<String, Schema.SObjectType>();

  private static Map<String, Schema.DescribeSObjectResult> described = new Map<String, Schema.DescribeSObjectResult>();

  private static Map<String, Map<String, Schema.SObjectField>> fieldMaps = new Map<String, Map<String, Schema.SObjectField>>();
  private static Map<String, Schema.DescribeFieldResult> fieldDescribes = new Map<String, Schema.DescribeFieldResult>();
  private static Map<Schema.SObjectType, Schema.DescribeSObjectResult> describedTypes = new Map<Schema.SObjectType, Schema.DescribeSObjectResult>();

  private static Map<String, PathField> pathFields = new Map<String, PathField>();

  // ---- the admin's Time Drive records --------------------------------------
  // Read into the same shapes the metadata types give, so the providers, the
  // plotter and the controller take a source the way they always have.

  private static Map<String, Time_Drive_Source__mdt> driveSources;
  private static Map<String, List<Time_Drive_Detail_Field__mdt>> driveDetails;
  private static Map<String, List<Time_Drive_Highlight__mdt>> driveHighlights;

  // The package's namespace prefix on Time Drive's own fields (ns__), or ''
  // unpackaged: read off an object of the package, so it's never typed in.
  private static final String FIELD_PREFIX = String.valueOf(Time_Drive_Record__c.SObjectType)
    .removeEnd('Time_Drive_Record__c');

  /**
   * One of Time Drive's own fields by its full name, for get and put by name:
   * Kind__c reads ns__Kind__c once packaged. Field maps and populated-field
   * maps key packaged fields by their full names.
   *
   * @param name the field's name without a namespace, such as Kind__c
   * @return the name with the package's prefix, if it has one
   */
  public static String field(String name) {
    return FIELD_PREFIX + name;
  }

  /** The package's namespace, or null unpackaged. */
  public static final String NAMESPACE = String.isBlank(FIELD_PREFIX) ? null : FIELD_PREFIX.removeEnd('__');

  /**
   * An Apex source's class by the name Setup keeps: the org's own class
   * first (it has no namespace), else Time Drive's (TimeDriveOpportunityProducts).
   * A name with a namespace (acme.LoyaltySource) is found as given.
   *
   * @param name the class name
   * @return the class's type, or null when there's none by that name
   */
  public static Type apexType(String name) {
    if (String.isBlank(name)) {
      return null;
    }
    String trimmed = name.trim();
    if (trimmed.contains('.')) {
      return Type.forName(trimmed);
    }
    Type own = Type.forName('', trimmed);
    return own != null ? own : Type.forName(trimmed);
  }

  private static final List<String> SOURCE_COPIED = new List<String>{
    'Kind__c',
    'Object_Name__c',
    'Parent_Field__c',
    'Junction_Object__c',
    'Junction_Parent_Field__c',
    'Junction_Record_Field__c',
    'Individual_Field__c',
    'Data_Space__c',
    'Provider_Class__c',
    'Date_Field__c',
    'Filter__c',
    'Max_Records__c',
    'History_Months__c',
    'Event_Type__c',
    'Event_Label__c',
    'Category__c',
    'Lenses__c',
    'Title__c',
    'Subtitle__c',
    'Icon__c',
    'Icon_Colour__c',
    'Record_Id_Field__c',
    'Id_Field__c',
    'Sequence__c'
  };

  // The partition for what is kept between requests; none to use in tests or
  // where the org has no capacity for it.
  private static final String CACHE_KEY = 'driveRecords';
  private static final Integer CACHE_SECONDS = 600;

  /**
   * Active sources for the parent object, by Sequence.
   *
   * @param parentObject API name of the parent object
   * @return the active sources, by Sequence
   */
  public static List<Time_Drive_Source__mdt> sources(String parentObject) {
    List<SourceOrder> ordered = new List<SourceOrder>();
    for (Time_Drive_Source__mdt s : allSources().values()) {
      if (s.Active__c && s.Parent_Object__c == parentObject) {
        ordered.add(new SourceOrder(s));
      }
    }
    ordered.sort();
    List<Time_Drive_Source__mdt> result = new List<Time_Drive_Source__mdt>();
    for (SourceOrder o : ordered) {
      result.add(o.source);
    }
    return result;
  }

  /**
   * The source's provider: the rows its record plots. With no Provider
   * Class, Salesforce sources use the generic SOQL provider and Data 360
   * sources the Data 360 one; Apex sources name a class extending
   * TimeDriveApexSource.
   *
   * @param source the source to find a provider for
   * @param warnings receives a message when no usable provider can be made
   * @return the provider instance, or null when there is none
   */
  public static TimeDriveRowProvider providerFor(Time_Drive_Source__mdt source, List<String> warnings) {
    String kind = new TimeDriveContext(null, null, null, source, null, null).kind();
    if (String.isBlank(source.Provider_Class__c)) {
      if (kind == TimeDriveContext.KIND_DATA_360) {
        return new TimeDriveData360Provider();
      }
      if (kind == TimeDriveContext.KIND_APEX) {
        warnings.add(String.format(Label.Time_Drive_Server_Apex_Needs_Class, new List<String>{ source.Label }));
        return null;
      }
      return new TimeDriveSoqlProvider();
    }
    Type providerType = apexType(source.Provider_Class__c);
    Object instance = providerType == null ? null : providerType.newInstance();
    if (instance instanceof TimeDriveApexSource) {
      return (TimeDriveApexSource) instance;
    }
    warnings.add(
      String.format(Label.Time_Drive_Server_Bad_Provider, new List<String>{ source.Label, source.Provider_Class__c })
    );
    return null;
  }

  /**
   * The views, All first, then in alphabetical order of the label people see
   * (their language's, when it's a custom label).
   *
   * @return the views in display order
   */
  public static List<Time_Drive_View__mdt> views() {
    List<Time_Drive_View__mdt> all = testViews != null ? testViews : Time_Drive_View__mdt.getAll().values();
    List<ViewOrder> ordered = new List<ViewOrder>();
    for (Time_Drive_View__mdt v : all) {
      ordered.add(new ViewOrder(v));
    }
    ordered.sort();
    List<Time_Drive_View__mdt> out = new List<Time_Drive_View__mdt>();
    for (ViewOrder o : ordered) {
      out.add(o.view);
    }
    return out;
  }

  /**
   * The views the picker offers: All, and every active one.
   *
   * @return the views to offer
   */
  public static List<Time_Drive_View__mdt> activeViews() {
    List<Time_Drive_View__mdt> out = new List<Time_Drive_View__mdt>();
    for (Time_Drive_View__mdt v : views()) {
      if (isActive(v)) {
        out.add(v);
      }
    }
    return out;
  }

  /**
   * Whether the picker offers a lens, by its API name (DeveloperName).
   *
   * @param key the lens's DeveloperName
   * @return true when it exists and is switched on
   */
  public static Boolean isOffered(String key) {
    for (Time_Drive_View__mdt v : views()) {
      if (v.DeveloperName == key) {
        return isActive(v);
      }
    }
    return false;
  }

  /**
   * Whether a view is offered: All always; others unless made inactive.
   *
   * @param v the view to check
   * @return true when the view is offered
   */
  public static Boolean isActive(Time_Drive_View__mdt v) {
    return v.DeveloperName == ALL_VIEW || !hiddenViews().contains(v.DeveloperName);
  }

  private static Set<String> hiddenViews;

  /**
   * The lenses that start switched off: until Setup first saves the org's
   * choices (Get started writes these), the picker doesn't offer them.
   */
  public static final List<String> OFF_BY_DEFAULT = new List<String>{ 'Commerce', 'Digital' };

  /**
   * The views Setup has switched off, kept on the org's Time_Drive_Setup__c
   * record (read once a transaction); before there is one, OFF_BY_DEFAULT.
   *
   * @return the developer names of the views the picker doesn't offer
   */
  public static Set<String> hiddenViews() {
    if (hiddenViews == null) {
      hiddenViews = new Set<String>();
      // The org's own Setup record: read for everyone who opens a timeline.
      List<Time_Drive_Setup__c> rows = [
        SELECT Hidden_Views__c
        FROM Time_Drive_Setup__c
        WITH SYSTEM_MODE
        ORDER BY CreatedDate
        LIMIT 1
      ];
      // No Setup record yet: the lenses that start switched off.
      String raw = rows.isEmpty() ? String.join(OFF_BY_DEFAULT, ',') : rows[0].Hidden_Views__c;
      for (String name : String.isBlank(raw) ? new List<String>() : raw.split(',')) {
        if (String.isNotBlank(name)) {
          hiddenViews.add(name.trim());
        }
      }
    }
    return hiddenViews;
  }

  /** Reads the switched-off views again on next use (after Setup saves them). */
  public static void forgetHiddenViews() {
    hiddenViews = null;
  }

  /**
   * The custom label a view's Menu Label names ($Label.Time_Drive_View_Sales gives
   * Time_Drive_View_Sales), or null when it's plain text. The card shows its own copy
   * of a label it knows: Apex only translates a label once its language is Active in
   * Translation Language Settings, the card's labels whatever.
   *
   * @param v the view
   * @return the custom label's name, or null
   */
  public static String viewLabelName(Time_Drive_View__mdt v) {
    String raw = v.Menu_Label__c?.trim();
    return String.isNotBlank(raw) && raw.startsWith(LABEL_PREFIX) ? raw.substring(LABEL_PREFIX.length()).trim() : null;
  }

  /**
   * A view's picker label in the viewer's language: its Menu Label (or a custom label's), else its label.
   *
   * @param v the view
   * @return the view's picker label
   */
  public static String viewLabel(Time_Drive_View__mdt v) {
    String raw = v.Menu_Label__c?.trim();
    String out = String.isNotBlank(raw) && raw.startsWith(LABEL_PREFIX)
      ? customLabel(raw.substring(LABEL_PREFIX.length()))
      : raw;
    return String.isBlank(out) ? v.Label : out;
  }

  private class ViewOrder implements Comparable {
    Time_Drive_View__mdt view;
    // The label people see, lower-cased: the alphabetical order ignores case.
    String key;
    ViewOrder(Time_Drive_View__mdt view) {
      this.view = view;
      this.key = viewLabel(view).toLowerCase();
    }
    /**
     * Orders views All first, then alphabetically by the label people see.
     *
     * @param other the ViewOrder to compare with
     * @return a negative, zero or positive number
     */
    public Integer compareTo(Object other) {
      ViewOrder that = (ViewOrder) other;
      Boolean mineAll = view.DeveloperName == ALL_VIEW;
      Boolean theirsAll = that.view.DeveloperName == ALL_VIEW;
      if (mineAll != theirsAll) {
        return mineAll ? -1 : 1;
      }
      return key == that.key ? view.DeveloperName.compareTo(that.view.DeveloperName) : key.compareTo(that.key);
    }
  }

  /**
   * What the legend and filters call a source's items, in the viewer's
   * language: a custom label's translation ($Label.Name), the words typed
   * (one language), or, left blank, the object's plural name (Salesforce
   * translates those); else the source's own name.
   *
   * @param s the source
   * @return the label to show for the source in the legend
   */
  /**
   * The custom label behind a source's name ($Label.Time_Drive_Legend_Emails in its
   * Event Label, or the default label for its object), or null when its name is
   * plain text or an object's: the card shows its own copy (see viewLabelName).
   *
   * @param s the source
   * @return the custom label's name, or null
   */
  public static String legendLabelName(Time_Drive_Source__mdt s) {
    if (s == null) {
      return null;
    }
    String raw = s.isSet(Time_Drive_Source__mdt.Event_Label__c) ? s.Event_Label__c?.trim() : null;
    if (String.isNotBlank(raw)) {
      return raw.startsWith(LABEL_PREFIX) ? raw.substring(LABEL_PREFIX.length()).trim() : null;
    }
    if (
      String.isBlank(s.Object_Name__c) ||
      new TimeDriveContext(null, null, null, s, null, null).kind() != TimeDriveContext.KIND_SALESFORCE
    ) {
      return null;
    }
    return DEFAULT_LEGEND_LABELS.get(s.Object_Name__c.toLowerCase());
  }

  public static String legendLabel(Time_Drive_Source__mdt s) {
    if (s == null) {
      return null;
    }
    String raw = s.isSet(Time_Drive_Source__mdt.Event_Label__c) ? s.Event_Label__c?.trim() : null;
    String key = s.DeveloperName + '|' + raw + '|' + s.Object_Name__c;
    if (legendLabels.containsKey(key)) {
      return legendLabels.get(key);
    }
    String out;
    if (String.isNotBlank(raw) && raw.startsWith(LABEL_PREFIX)) {
      out = customLabel(raw.substring(LABEL_PREFIX.length()));
    } else if (String.isNotBlank(raw) && raw.startsWith(OBJECT_PREFIX)) {
      out = objectPlural(raw.substring(OBJECT_PREFIX.length()).trim());
    } else if (String.isNotBlank(raw)) {
      out = raw;
    } else if (new TimeDriveContext(null, null, null, s, null, null).kind() == TimeDriveContext.KIND_SALESFORCE) {
      String defaultLabel = String.isBlank(s.Object_Name__c)
        ? null
        : DEFAULT_LEGEND_LABELS.get(s.Object_Name__c.toLowerCase());
      out = defaultLabel == null ? null : customLabel(defaultLabel);
      if (String.isBlank(out)) {
        out = objectPlural(dateOwner(s));
      }
    }
    if (String.isBlank(out)) {
      out = s.Label;
    }
    legendLabels.put(key, out);
    return out;
  }

  /**
   * A custom label in the viewer's language, or null when there's none by that name.
   * Time Drive's own labels come first (null is the package's namespace once it's
   * packaged), then the org's own ('' is the org's namespace). Unpackaged, they're one.
   *
   * @param name the custom label's name
   * @return the label text, or null when there is no such label
   */
  public static String customLabel(String name) {
    if (String.isBlank(name)) {
      return null;
    }
    String key = name.trim();
    for (String namespace : new List<String>{ null, '' }) {
      try {
        return System.Label.get(namespace, key);
      } catch (Exception e) {
        // Not a label in that namespace: try the next.
      }
    }
    return null;
  }

  private static String objectPlural(String objectName) {
    try {
      return String.isBlank(objectName)
        ? null
        : Schema.describeSObjects(new List<String>{ objectName }, SObjectDescribeOptions.DEFERRED)[0].getLabelPlural();
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * An object's describe, kept for the request: the source's query, its
   * highlights and its rows all ask for the same one. Throws for a name that
   * isn't an object, as Schema.describeSObjects does.
   *
   * @param objectName API name of the object
   * @return the object's describe result
   */
  public static Schema.DescribeSObjectResult describeObject(String objectName) {
    String key = objectName.toLowerCase();
    Schema.DescribeSObjectResult found = described.get(key);
    if (found == null) {
      found = Schema.describeSObjects(new List<String>{ objectName }, SObjectDescribeOptions.DEFERRED)[0];
      described.put(key, found);
    }
    return found;
  }

  /**
   * An object's fields by lower-case name, built once for the request:
   * fields.getMap() rebuilds the whole map on every call, which in an object
   * with hundreds of fields is a measurable cost each time.
   *
   * @param objectName API name of the object
   * @return the object's fields by lower-case name
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
   *
   * @param objectName API name of the object
   * @param fieldName API name of the field
   * @return the field's describe result, or null when there is no such field
   */
  public static Schema.DescribeFieldResult fieldDescribe(String objectName, String fieldName) {
    if (String.isBlank(fieldName)) {
      return null;
    }
    // A path through lookups (Task.ActivityDate on TaskRelation).
    if (fieldName.contains('.')) {
      return pathField(objectName, fieldName)?.field;
    }
    String key = (objectName + '.' + fieldName).toLowerCase();
    Schema.DescribeFieldResult found = fieldDescribes.get(key);
    if (found == null) {
      Schema.SObjectField f = ownField(fieldMap(objectName), fieldName);
      if (f == null) {
        return null;
      }
      found = f.getDescribe();
      fieldDescribes.put(key, found);
    }
    return found;
  }

  // A field by name, or Time Drive's own by its short name: installed, the
  // describe lists Overdue__c as drvrckt__Overdue__c, while queries and
  // record reads take either.
  private static Schema.SObjectField ownField(Map<String, Schema.SObjectField> fields, String name) {
    String key = name.toLowerCase();
    Schema.SObjectField f = fields.get(key);
    if (f == null && FIELD_PREFIX != null && key.endsWith('__c') && key.countMatches('__') == 1) {
      f = fields.get(FIELD_PREFIX.toLowerCase() + key);
    }
    return f;
  }

  /**
   * A field reached through lookups: Task.ActivityDate on TaskRelation,
   * Campaign.StartDate on CampaignMember. `owner` is the object the field
   * belongs to (Task), `prefix` the path to it with its dot ('Task.'; blank
   * for a field of the object itself).
   */
  public class PathField {
    public Schema.DescribeFieldResult field;
    public String owner;
    public String prefix = '';
  }

  /**
   * Follows a path of relationship names to its last field. Null when a step
   * isn't a lookup to one object (a polymorphic Who or What can't be
   * followed), the object or field doesn't exist, or the last field is
   * missing. A path without dots is the object's own field.
   *
   * @param objectName API name of the object the path starts from
   * @param path a field name or dotted relationship path
   * @return the field the path ends at, or null when it cannot be resolved
   */
  public static PathField pathField(String objectName, String path) {
    if (String.isBlank(objectName) || String.isBlank(path)) {
      return null;
    }
    String key = (objectName + '|' + path).toLowerCase();
    if (pathFields.containsKey(key)) {
      return pathFields.get(key);
    }
    PathField out = new PathField();
    try {
      List<String> steps = path.split('\\.');
      String current = describeObject(objectName).getName();
      for (Integer i = 0; i < steps.size() - 1 && out != null; i++) {
        Schema.DescribeFieldResult lookup = lookupNamed(current, steps[i]);
        if (lookup == null || lookup.getReferenceTo().size() != 1) {
          out = null;
        } else {
          current = describeType(lookup.getReferenceTo()[0]).getName();
          out.prefix += steps[i] + '.';
        }
      }
      if (out != null) {
        String last = steps[steps.size() - 1].toLowerCase();
        Schema.SObjectField f = ownField(fieldMap(current), last);
        if (f == null) {
          out = null;
        } else {
          out.field = f.getDescribe();
          out.owner = current;
        }
      }
    } catch (Exception e) {
      out = null;
    }
    pathFields.put(key, out);
    return out;
  }

  // The lookup field on an object whose relationship has this name: found by
  // the usual names first (Task is TaskId, Campaign__r is Campaign__c), else
  // by looking through the object's lookups.
  private static Schema.DescribeFieldResult lookupNamed(String objectName, String relationship) {
    Map<String, Schema.SObjectField> fields = fieldMap(objectName);
    for (String guess : new List<String>{ relationship + 'Id', relationship.replaceAll('(?i)__r$', '__c') }) {
      Schema.SObjectField f = fields.get(guess.toLowerCase());
      if (f != null) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getRelationshipName()?.equalsIgnoreCase(relationship) == true) {
          return d;
        }
      }
    }
    for (Schema.SObjectField f : fields.values()) {
      Schema.DescribeFieldResult d = f.getDescribe();
      if (d.getRelationshipName()?.equalsIgnoreCase(relationship) == true) {
        return d;
      }
    }
    return null;
  }

  /**
   * The object a source's date belongs to: the source's own object, or, for
   * a junction (TaskRelation with Task.ActivityDate), the object the date
   * path leads to. Behaviour that depends on the kind of record (archived
   * activities, all-day events) follows this, not the source's object.
   *
   * @param s the source
   * @return API name of the object that holds the source's date
   */
  public static String dateOwner(Time_Drive_Source__mdt s) {
    return pathField(s.Object_Name__c, s.Date_Field__c)?.owner ?? s.Object_Name__c;
  }

  /**
   * The path to the date's object with its dot (Task.), blank when it is the source's own.
   *
   * @param s the source
   * @return the prefix, or blank
   */
  public static String datePrefix(Time_Drive_Source__mdt s) {
    return pathField(s.Object_Name__c, s.Date_Field__c)?.prefix ?? '';
  }

  /**
   * A type's describe, kept for the request, for record Ids and lookup targets.
   *
   * @param type the sObject type
   * @return the type's describe result
   */
  public static Schema.DescribeSObjectResult describeType(Schema.SObjectType type) {
    Schema.DescribeSObjectResult found = describedTypes.get(type);
    if (found == null) {
      found = type.getDescribe(SObjectDescribeOptions.DEFERRED);
      describedTypes.put(type, found);
      described.put(found.getName().toLowerCase(), found);
    }
    return found;
  }

  /**
   * An object by API name, described by name (Data 360's DMOs can be, though
   * the global describe doesn't list them in every org). Null when there's no
   * such object.
   *
   * @param name API name of the object
   * @return the sObject type, or null when there is no such object
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

  /**
   * The shipped templates (Time Drive Source metadata): a catalogue the setup
   * wizard copies from. They are never plotted themselves.
   *
   * @return the templates by developer name
   */
  public static Map<String, Time_Drive_Source__mdt> templates() {
    if (testSources == null) {
      return Time_Drive_Source__mdt.getAll();
    }
    // Tests stand in the templates with their sources.
    Map<String, Time_Drive_Source__mdt> out = new Map<String, Time_Drive_Source__mdt>();
    for (Time_Drive_Source__mdt s : testSources) {
      out.put(s.DeveloperName, s);
    }
    return out;
  }

  /** Forgets what was read, so the next read is fresh (after a save). */
  public static void reset() {
    try {
      Cache.OrgPartition cache = partition();
      if (cache != null) {
        cache.remove(CACHE_KEY);
      }
    } catch (Exception e) {
      // Nothing kept to forget.
    }
    driveSources = null;
    driveDetails = null;
    driveHighlights = null;
  }

  private static void loadDrives() {
    if (driveSources != null) {
      return;
    }
    driveSources = new Map<String, Time_Drive_Source__mdt>();
    driveDetails = new Map<String, List<Time_Drive_Detail_Field__mdt>>();
    driveHighlights = new Map<String, List<Time_Drive_Highlight__mdt>>();
    for (Time_Drive_Record__c r : driveRecords()) {
      adopt(r);
    }
  }

  private static Cache.OrgPartition partition() {
    try {
      return Test.isRunningTest() ? null : Cache.Org.getPartition(TimeDriveCache.PARTITION);
    } catch (Exception e) {
      return null;
    }
  }

  // The admin's records, from Platform Cache when kept there, else queried
  // (and kept for the next request).
  private static List<Time_Drive_Record__c> driveRecords() {
    Cache.OrgPartition cache = partition();
    try {
      if (cache != null && cache.contains(CACHE_KEY)) {
        return (List<Time_Drive_Record__c>) cache.get(CACHE_KEY);
      }
    } catch (Exception e) {
      // Not readable: read the records.
    }
    List<Time_Drive_Record__c> found = queryDriveRecords();
    try {
      if (cache != null) {
        cache.put(CACHE_KEY, found, CACHE_SECONDS);
      }
    } catch (Exception e) {
      // No room to keep them: every request reads them.
    }
    return found;
  }

  private static List<Time_Drive_Record__c> queryDriveRecords() {
    // System mode on purpose: this is the admin's configuration of what every
    // user's timeline plots, not data any one user is entitled to or not.
    return [
      SELECT
        Name,
        Key__c,
        Active__c,
        Kind__c,
        Object_Name__c,
        Parent_Field__c,
        Junction_Object__c,
        Junction_Parent_Field__c,
        Junction_Record_Field__c,
        Individual_Field__c,
        Data_Space__c,
        Provider_Class__c,
        Date_Field__c,
        Filter__c,
        Max_Records__c,
        History_Months__c,
        Event_Type__c,
        Event_Label__c,
        Category__c,
        Lenses__c,
        Title__c,
        Subtitle__c,
        Icon__c,
        Icon_Colour__c,
        Record_Id_Field__c,
        Id_Field__c,
        Sequence__c,
        Template_Key__c,
        Template_Version__c,
        Detail_1_Field__c,
        Detail_1_Label__c,
        Detail_1_Format__c,
        Detail_2_Field__c,
        Detail_2_Label__c,
        Detail_2_Format__c,
        Detail_3_Field__c,
        Detail_3_Label__c,
        Detail_3_Format__c,
        Detail_4_Field__c,
        Detail_4_Label__c,
        Detail_4_Format__c,
        Highlight_Field__c,
        Highlight_Icon__c,
        Highlight_Colour__c,
        Time_Drive__r.Parent_Object__c,
        Time_Drive__r.Active__c
      FROM Time_Drive_Record__c
      WITH SYSTEM_MODE
      ORDER BY Sequence__c NULLS LAST, Name
    ];
  }

  // One record as the source, detail fields and highlight the providers read.
  private static void adopt(Time_Drive_Record__c r) {
    String key = r.Key__c;
    Time_Drive_Source__mdt s = new Time_Drive_Source__mdt(
      DeveloperName = key,
      Label = r.Name,
      Active__c = r.Active__c == true && r.Time_Drive__r.Active__c == true,
      Parent_Object__c = r.Time_Drive__r.Parent_Object__c
    );
    for (String name : SOURCE_COPIED) {
      Object value = r.get(field(name));
      if (value != null) {
        s.put(field(name), value);
      }
    }
    driveSources.put(key, s);
    List<Time_Drive_Detail_Field__mdt> details = new List<Time_Drive_Detail_Field__mdt>();
    for (Integer n = 1; n <= 4; n++) {
      String field = (String) r.get(field('Detail_' + n + '_Field__c'));
      if (String.isBlank(field)) {
        continue;
      }
      String label = (String) r.get(field('Detail_' + n + '_Label__c'));
      String format = (String) r.get(field('Detail_' + n + '_Format__c'));
      details.add(
        new Time_Drive_Detail_Field__mdt(
          DeveloperName = key.left(34) + '_D' + n,
          Label = String.isBlank(label) ? field.left(40) : label,
          Field__c = field,
          Format__c = String.isBlank(format) ? 'Text' : format,
          Sequence__c = n * 10
        )
      );
    }
    driveDetails.put(key, details);
    if (String.isNotBlank(r.Highlight_Field__c)) {
      driveHighlights.put(
        key,
        new List<Time_Drive_Highlight__mdt>{
          new Time_Drive_Highlight__mdt(
            DeveloperName = key.left(34) + '_H1',
            Label = r.Highlight_Field__c.left(40),
            Field__c = r.Highlight_Field__c,
            Icon__c = r.Highlight_Icon__c,
            Colour__c = r.Highlight_Colour__c,
            Sequence__c = 10
          )
        }
      );
    }
  }

  /**
   * The keys of the lenses a source is in: its Lenses, else its Category (one lens).
   *
   * @param s the source
   * @return the lens keys
   */
  public static List<String> lensesOf(Time_Drive_Source__mdt s) {
    List<String> out = new List<String>();
    if (s == null) {
      return out;
    }
    String raw = s.isSet(Time_Drive_Source__mdt.Lenses__c) ? s.Lenses__c : null;
    if (String.isBlank(raw)) {
      raw = s.Category__c;
    }
    for (String part : String.isBlank(raw) ? new List<String>() : raw.split(';')) {
      if (String.isNotBlank(part) && !out.contains(part.trim())) {
        out.add(part.trim());
      }
    }
    return out;
  }

  /**
   * The lenses as one string (Sales;Service), which an event carries to the lens filter.
   *
   * @param s the source
   * @return the lenses joined with semicolons
   */
  public static String lensKey(Time_Drive_Source__mdt s) {
    List<String> lenses = lensesOf(s);
    return lenses.isEmpty() ? null : String.join(lenses, ';');
  }

  /**
   * Every source by key: the admin's Time Drive records, or a test's stand-ins.
   *
   * @return the sources by key
   */
  public static Map<String, Time_Drive_Source__mdt> allSources() {
    if (testSources == null) {
      loadDrives();
      return driveSources;
    }
    Map<String, Time_Drive_Source__mdt> out = new Map<String, Time_Drive_Source__mdt>();
    for (Time_Drive_Source__mdt s : testSources) {
      out.put(s.DeveloperName, s);
    }
    return out;
  }

  /**
   * One source by developer name.
   *
   * @param developerName the source's developer name
   * @return the source, or null when there is none
   */
  public static Time_Drive_Source__mdt source(String developerName) {
    return String.isBlank(developerName) ? null : allSources().get(developerName);
  }

  /**
   * A source's detail field records as stored, blanked ones too (the setup
   * wizard reuses their names), by Sequence.
   *
   * @param sourceDeveloperName developer name of the source
   * @return the stored detail field records
   */
  public static List<Time_Drive_Detail_Field__mdt> storedDetailFields(String sourceDeveloperName) {
    if (testDetailFields != null) {
      return testDetailFields.containsKey(sourceDeveloperName)
        ? testDetailFields.get(sourceDeveloperName)
        : new List<Time_Drive_Detail_Field__mdt>();
    }
    if (testSources != null) {
      return new List<Time_Drive_Detail_Field__mdt>();
    }
    loadDrives();
    List<Time_Drive_Detail_Field__mdt> found = driveDetails.get(sourceDeveloperName);
    return found == null ? new List<Time_Drive_Detail_Field__mdt>() : found;
  }

  /**
   * A source's highlight records as stored, blanked ones too (the setup
   * wizard reuses their names), by Sequence.
   *
   * @param sourceDeveloperName developer name of the source
   * @return the stored highlight records
   */
  public static List<Time_Drive_Highlight__mdt> storedHighlights(String sourceDeveloperName) {
    if (testHighlights != null) {
      return testHighlights.containsKey(sourceDeveloperName)
        ? testHighlights.get(sourceDeveloperName)
        : new List<Time_Drive_Highlight__mdt>();
    }
    if (testSources != null) {
      return new List<Time_Drive_Highlight__mdt>();
    }
    loadDrives();
    List<Time_Drive_Highlight__mdt> found = driveHighlights.get(sourceDeveloperName);
    return found == null ? new List<Time_Drive_Highlight__mdt>() : found;
  }

  /**
   * The source's highlights in use.
   *
   * @param sourceDeveloperName developer name of the source
   * @return the highlights in use
   */
  public static List<Time_Drive_Highlight__mdt> highlights(String sourceDeveloperName) {
    return storedHighlights(sourceDeveloperName);
  }

  /**
   * The source's detail fields in use, by Sequence.
   *
   * @param sourceDeveloperName developer name of the source
   * @return the detail fields in use
   */
  public static List<Time_Drive_Detail_Field__mdt> detailFields(String sourceDeveloperName) {
    return storedDetailFields(sourceDeveloperName);
  }

  private class SourceOrder implements Comparable {
    Time_Drive_Source__mdt source;

    SourceOrder(Time_Drive_Source__mdt source) {
      this.source = source;
    }

    /**
     * Orders sources by Sequence.
     *
     * @param other the SourceOrder to compare with
     * @return a negative, zero or positive number
     */
    public Integer compareTo(Object other) {
      Decimal mine = source.Sequence__c == null ? 0 : source.Sequence__c;
      Decimal theirs = ((SourceOrder) other).source.Sequence__c == null ? 0 : ((SourceOrder) other).source.Sequence__c;
      return mine == theirs ? 0 : (mine < theirs ? -1 : 1);
    }
  }
}
