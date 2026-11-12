/**
 * The Time Drive Setup page: lists the Time Drive Source records in plain
 * words, answers the setup wizard's questions from the org's own schema
 * (objects, how they link to the page's record, their fields), previews a
 * draft source against a real record, and saves sources (new, changed or
 * switched off) as Time_Drive_Record__c records. Every save is done when
 * its call returns.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings(
  'PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.AvoidBooleanMethodParameters, PMD.ExcessiveParameterList, PMD.ExcessivePublicCount, PMD.NcssCount, PMD.TooManyFields'
)
public with sharing class TimeDriveSetupController {
  private static final Integer MAX_DETAILS = 4;
  // Contact points (email, phone, address) are how to reach someone, not what they did, whatever
  // category Data 360 files them under.
  @TestVisible
  private static final Pattern CONTACT_POINT_DMO = Pattern.compile('(?i)ssot__ContactPoint[A-Za-z0-9_]*__dlm');
  // Objects no one plots: system plumbing, history, sharing and metadata.
  private static final List<String> SKIPPED_SUFFIXES = new List<String>{
    'history',
    'share',
    'feed',
    'changeevent',
    'tag',
    '__mdt',
    '__e',
    '__b',
    '__x',
    '__xo',
    '__hd',
    '__chn',
    '__dll',
    'eventstore',
    'event'
  };
  // System objects that look up a record but aren't things that happen to it.
  private static final Set<String> PLUMBING = new Set<String>{
    'acceptedeventrelation',
    'declinedeventrelation',
    'undecidedeventrelation',
    'eventrelation',
    'activityrecurrence2',
    'activityrecurrence2exception',
    'agentwork',
    'aiinsightvalue',
    'airecordinsight',
    'approvalsubmission',
    'approvalworkitem',
    'entitysubscription',
    'duplicaterecorditem',
    'flowrecordrelation',
    'processinstance',
    'recordaction'
  };

  // The relation objects behind tasks and events, and their record field.
  private static final Map<String, String> ACTIVITY_RELATIONS = new Map<String, String>{
    'TaskRelation' => 'TaskId',
    'EventRelation' => 'EventId',
    'TaskWhoRelation' => 'TaskId',
    'EventWhoRelation' => 'EventId'
  };

  // Junction objects whose date (and title, filter) are the related record's,
  // read across it by path (Task.ActivityDate), and that record's object: the
  // source opens that record. (The wizard reaches its fields by following the
  // lookup, one object at a time.)
  private static final Map<String, String> RELATION_RECORDS = new Map<String, String>{
    'TaskRelation' => 'Task',
    'TaskWhoRelation' => 'Task',
    'EventRelation' => 'Event',
    'EventWhoRelation' => 'Event',
    'CampaignMember' => 'Campaign',
    'OpportunityContactRole' => 'Opportunity',
    'CaseRelatedIssue' => 'Case',
    'ChangeRequestRelatedIssue' => 'ChangeRequest',
    'MaintenanceAsset' => 'MaintenancePlan',
    'ContentDocumentLink' => 'ContentDocument'
  };

  // Setup records a junction can require, which aren't engagement.
  private static final Set<String> SETUP_OBJECTS = new Set<String>{
    'User',
    'Profile',
    'UserRole',
    'Group',
    'BusinessHours',
    'Organization',
    'RecordType'
  };

  // Lookups every object has, which say nothing about who a record is for.
  private static final Set<String> AUDIT_FIELDS = new Set<String>{
    'CreatedById',
    'LastModifiedById',
    'OwnerId',
    'RecordTypeId'
  };

  // The field that names an object's records: Name, Subject, Case Number.
  // Where an object's name field usually is, tried before reading the rest:
  // describing every field of a big object (Case has hundreds) to find it is
  // most of what a link costs.
  private static final List<String> NAME_FIELD_GUESSES = new List<String>{
    'name',
    'subject',
    'casenumber',
    'title',
    'lastname'
  };
  private static Map<String, String> nameLabels = new Map<String, String>();

  // Data 360's DMO names, where force-app-data360's catalog is deployed.
  @TestVisible
  private static List<String> testDmoNames;
  @TestVisible
  private static List<Option> testDataSpaces;
  @TestVisible
  private static Data360Status testData360Status;

  // ---- data volumes --------------------------------------------------------

  private static final List<Integer> RANGES = new List<Integer>{ 3, 6, 12, 24, 60 };
  // Counting stops here: past it, "more than" is all that matters.
  private static final Integer COUNT_CAP = 200000;

  // The object being counted is a Task or Event: archived ones count too.
  private static Boolean archived = false;

  // The legend order's stand-in for the source being saved (it may not have
  // a name yet).
  public static final String THIS_SOURCE = '__this__';

  // How a filter's conditions combine: all of them (AND) or any (OR).
  public static final String MATCH_ALL = 'all';
  public static final String MATCH_ANY = 'any';

  // ---- fit the timeline to the org ------------------------------------------

  // The org features org-fitted sources can need, and how Setup names them.
  private static final Map<String, String> FEATURE_LABELS = new Map<String, String>{
    'SharedActivities' => 'Shared Activities',
    'PersonAccounts' => 'Person Accounts',
    'ContactsToMultipleAccounts' => 'Contacts to Multiple Accounts',
    'EnhancedEmail' => 'Enhanced Email'
  };
  // Which setting wins when two variants need as many: Enhanced Email's
  // Email Messages over email tasks, however those link.
  private static final List<String> FEATURE_PRECEDENCE = new List<String>{
    'EnhancedEmail',
    'PersonAccounts',
    'SharedActivities',
    'ContactsToMultipleAccounts'
  };
  private static final List<String> PAGE_ORDER = new List<String>{
    'Contact',
    'Account',
    TimeDriveController.PERSON_ACCOUNT,
    'Lead'
  };

  @TestVisible
  private static Set<String> testFeatures;

  // ---- checking the org ----------------------------------------------------
  // Setup looks at how the org works, one thing at a time (so the page can tick
  // each off as it is done), then says what it found and what that means for
  // the sources it will add.

  private static final List<String> ORG_CHECKS = new List<String>{
    'SharedActivities',
    'ContactsToMultipleAccounts',
    'PersonAccounts',
    'EnhancedEmail',
    'Data360',
    'ActivityCapture'
  };

  private static final Map<String, String> CHECK_LABELS = new Map<String, String>{
    'SharedActivities' => 'Shared Activities',
    'ContactsToMultipleAccounts' => 'Contacts to Multiple Accounts',
    'PersonAccounts' => 'Person Accounts',
    'EnhancedEmail' => 'Enhanced Email',
    'Data360' => 'Data 360',
    'ActivityCapture' => 'Einstein Activity Capture'
  };

  // The exact setting each check reads, and where an admin finds it, so a
  // result says which setting was on or off.
  private static final Map<String, List<String>> CHECK_SETTINGS = new Map<String, List<String>>{
    'SharedActivities' => new List<String>{
      'Allow Users to Relate Multiple Contacts to Tasks and Events',
      'Setup › Activity Settings'
    },
    'ContactsToMultipleAccounts' => new List<String>{
      'Allow users to relate a contact to multiple accounts',
      'Setup › Account Settings'
    },
    'PersonAccounts' => new List<String>{
      'Person Accounts (the Account field Is Person Account)',
      'Admin controlled and managed; checked on the Account object'
    },
    'EnhancedEmail' => new List<String>{
      'Enhanced Email (emails saved as Email Messages with their activity)',
      'Setup › Enhanced Email'
    },
    'Data360' => new List<String>{
      'Data 360 connected, with the Time Drive Data 360 add-on installed',
      'Setup › Data 360 Setup, and the add-on package'
    },
    'ActivityCapture' => new List<String>{
      'Einstein Activity Capture licences assigned to users',
      'Setup › Einstein Activity Capture Settings (check Sync Email as Salesforce Activity)'
    }
  };

  @TestVisible
  private static ActivityCapture testActivityCapture;

  // ---- the sources ---------------------------------------------------------

  /**
   * Every source the admin has set up, in sequence, with a sentence saying what it plots.
   * @return The sources as summaries, in sequence order.
   */
  @AuraEnabled
  public static List<SourceSummary> getSources() {
    requireSetupAccess();
    TimeDriveConfig.reset();
    List<SourceSummary> out = new List<SourceSummary>();
    for (Time_Drive_Source__mdt s : TimeDriveConfig.allSources().values()) {
      out.add(new SourceSummary(s));
    }
    out.sort();
    return out;
  }

  /**
   * One source as the wizard edits it, with its detail fields.
   * @param developerName The source's developer name.
   * @return The source as a draft, with its detail fields and highlights.
   */
  @AuraEnabled
  public static SourceDraft getSource(String developerName) {
    requireSetupAccess();
    Time_Drive_Source__mdt s = TimeDriveConfig.source(developerName);
    if (s == null) {
      throw failure('That source no longer exists.');
    }
    SourceDraft d = new SourceDraft(s);
    for (Time_Drive_Detail_Field__mdt f : TimeDriveConfig.storedDetailFields(developerName)) {
      if (String.isNotBlank(f.Field__c)) {
        d.details.add(new DetailDraft(f));
      }
    }
    for (Time_Drive_Highlight__mdt h : TimeDriveConfig.storedHighlights(developerName)) {
      if (String.isNotBlank(h.Field__c)) {
        d.highlights.add(new HighlightDraft(h));
      }
    }
    return d;
  }

  // ---- the templates -------------------------------------------------------

  /**
   * The shipped templates this org can use, for a record page (all pages when
   * blank), each saying whether it has been added already. A template tied to
   * a setting (Shared Activities) is offered in the form that fits this org.
   * @param parentObject The record page's object, or blank for all pages.
   * @return The templates this org can use, each marked as added or not.
   */
  @AuraEnabled
  public static List<TemplateOption> getTemplates(String parentObject) {
    requireSetupAccess();
    Set<String> added = addedTemplates();
    List<TemplateOption> out = new List<TemplateOption>();
    for (Time_Drive_Source__mdt t : applicableTemplates(parentObject)) {
      out.add(new TemplateOption(t, added.contains(t.DeveloperName)));
    }
    out.sort();
    return out;
  }

  /**
   * Adds a copy of a template as a source of the admin's own.
   * @param templateKey The key (developer name) of the template to copy.
   * @return A ticket naming the new source.
   */
  @AuraEnabled
  public static SaveTicket useTemplate(String templateKey) {
    requireSetupAccess();
    Time_Drive_Source__mdt t = TimeDriveConfig.templates().get(templateKey);
    if (t == null) {
      throw failure('That template no longer exists.');
    }
    if (addedTemplates().contains(templateKey)) {
      throw failure(t.Label + ' is already added.');
    }
    Time_Drive_Record__c row = copyOf(t);
    write(new List<Time_Drive_Record__c>{ row });
    return new SaveTicket(row.Key__c);
  }

  /**
   * Adds every template this org can use for a record page that isn't added
   * yet. Variants of one group (Contact Tasks by Name, or through every
   * contact) plot the same records, so only one is ever on: when another
   * variant of the group is on, the one that fits the org now takes its place
   * and the other is switched off, not deleted. A group the admin has
   * switched off entirely is left off.
   * @param parentObject The record page's object, or blank for all pages.
   * @return What was added, and what was switched for the variant that fits.
   */
  @AuraEnabled
  public static QuickStartResult quickStart(String parentObject) {
    requireSetupAccess();
    Map<String, Boolean> fit = targets(orgFeatures());
    Map<String, List<Time_Drive_Record__c>> copiesByGroup = new Map<String, List<Time_Drive_Record__c>>();
    Map<String, Time_Drive_Record__c> copyOfTemplate = new Map<String, Time_Drive_Record__c>();
    for (Time_Drive_Record__c copy : addedCopies()) {
      Time_Drive_Source__mdt template = TimeDriveConfig.templates().get(copy.Template_Key__c);
      String g = template == null ? null : variantGroup(template, fit);
      if (g != null) {
        if (!copiesByGroup.containsKey(g)) {
          copiesByGroup.put(g, new List<Time_Drive_Record__c>());
        }
        copiesByGroup.get(g).add(copy);
      }
      if (!copyOfTemplate.containsKey(copy.Template_Key__c)) {
        copyOfTemplate.put(copy.Template_Key__c, copy);
      }
    }
    QuickStartResult done = new QuickStartResult();
    List<Time_Drive_Record__c> rows = new List<Time_Drive_Record__c>();
    for (Time_Drive_Source__mdt t : applicableTemplates(parentObject)) {
      String g = variantGroup(t, fit);
      List<Time_Drive_Record__c> others = new List<Time_Drive_Record__c>();
      Boolean grouped = g != null && copiesByGroup.containsKey(g);
      for (Time_Drive_Record__c copy : grouped ? copiesByGroup.get(g) : new List<Time_Drive_Record__c>()) {
        if (copy.Template_Key__c != t.DeveloperName && copy.Active__c) {
          others.add(copy);
        }
      }
      Time_Drive_Record__c mine = copyOfTemplate.get(t.DeveloperName);
      if (grouped && others.isEmpty()) {
        // This variant is on already, or the admin switched the group off.
        continue;
      }
      if (!grouped && mine != null) {
        continue;
      }
      String onKey;
      if (mine == null) {
        Time_Drive_Record__c row = copyOf(t);
        rows.add(row);
        onKey = row.Key__c;
        done.added.add(new TemplateOption(t, true));
      } else {
        rows.add(new Time_Drive_Record__c(Key__c = mine.Key__c, Active__c = true));
        onKey = mine.Key__c;
      }
      for (Time_Drive_Record__c other : others) {
        rows.add(new Time_Drive_Record__c(Key__c = other.Key__c, Active__c = false));
        done.switched.add(new VariantSwitch(t, sourceLabel(other), mine == null ? t.Label : sourceLabel(mine), onKey));
      }
    }
    if (!rows.isEmpty()) {
      write(rows);
    }
    return done;
  }

  // The template's variant group, by record page, when the org's settings
  // choose between its variants; null otherwise.
  private static String variantGroup(Time_Drive_Source__mdt t, Map<String, Boolean> fit) {
    if (String.isBlank(t.Variant_Group__c) || !fit.containsKey(t.DeveloperName)) {
      return null;
    }
    return (String.isBlank(t.Parent_Object__c) ? 'Contact' : t.Parent_Object__c) + '|' + t.Variant_Group__c;
  }

  private static String sourceLabel(Time_Drive_Record__c copy) {
    Time_Drive_Source__mdt s = TimeDriveConfig.source(copy.Key__c);
    return s == null ? copy.Key__c : s.Label;
  }

  // Reached only through Setup, after requireSetupAccess(); a record of the org's own configuration.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<Time_Drive_Record__c> addedCopies() {
    return [
      SELECT Key__c, Active__c, Template_Key__c
      FROM Time_Drive_Record__c
      WHERE Template_Key__c != NULL
      ORDER BY CreatedDate
    ];
  }

  /** What quick start did: the sources it added, and the variants it switched. */
  public class QuickStartResult {
    @AuraEnabled
    public List<TemplateOption> added = new List<TemplateOption>();
    @AuraEnabled
    public List<VariantSwitch> switched = new List<VariantSwitch>();
  }

  /** One source switched off for the variant of it that fits the org now. */
  public class VariantSwitch {
    @AuraEnabled
    public String parentObject;
    // The source switched off, and the one on in its place.
    @AuraEnabled
    public String offLabel;
    @AuraEnabled
    public String onLabel;
    @AuraEnabled
    public String onKey;

    /**
     * Builds the switch.
     * @param t The template that fits now.
     * @param offLabel The label of the source switched off.
     * @param onLabel The label of the source on in its place.
     * @param onKey The developer name of the source on in its place.
     */
    public VariantSwitch(Time_Drive_Source__mdt t, String offLabel, String onLabel, String onKey) {
      this.parentObject = String.isBlank(t.Parent_Object__c) ? 'Contact' : t.Parent_Object__c;
      this.offLabel = offLabel;
      this.onLabel = onLabel;
      this.onKey = onKey;
    }
  }

  // Reached only through Setup, after requireSetupAccess(); a record of the org's own configuration.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Set<String> addedTemplates() {
    Set<String> out = new Set<String>();
    for (Time_Drive_Record__c r : [SELECT Template_Key__c FROM Time_Drive_Record__c WHERE Template_Key__c != NULL]) {
      out.add(r.Template_Key__c);
    }
    return out;
  }

  private static List<Time_Drive_Source__mdt> applicableTemplates(String parentObject) {
    Map<String, Boolean> fit = targets(orgFeatures());
    List<Time_Drive_Source__mdt> out = new List<Time_Drive_Source__mdt>();
    for (Time_Drive_Source__mdt t : TimeDriveConfig.templates().values()) {
      Boolean onPage =
        String.isBlank(parentObject) ||
        (String.isBlank(t.Parent_Object__c) ? 'Contact' : t.Parent_Object__c) == parentObject;
      if (onPage && t.Removed__c != true && (!fit.containsKey(t.DeveloperName) || fit.get(t.DeveloperName))) {
        out.add(t);
      }
    }
    return out;
  }

  /**
   * A template as a new Time Drive Record: its details and highlight too, remembering where it came from.
   * @param t The template to copy.
   * @return The Time Drive Record to save.
   */
  private static Time_Drive_Record__c copyOf(Time_Drive_Source__mdt t) {
    SourceDraft d = new SourceDraft(t);
    d.developerName = TimeDriveConfig.source(t.DeveloperName) == null ? t.DeveloperName : uniqueName(t.Label);
    d.active = true;
    // All is a lens like the others: a template's copy starts in it, as well as its own.
    List<String> lenses = new List<String>{ TimeDriveConfig.ALL_VIEW };
    for (String lens : d.lenses == null ? new List<String>() : d.lenses) {
      if (!lenses.contains(lens)) {
        lenses.add(lens);
      }
    }
    d.lenses = lenses;
    d.details = new List<DetailDraft>();
    for (SObject part : templateParts(Time_Drive_Detail_Field__mdt.getAll().values(), t.DeveloperName)) {
      Time_Drive_Detail_Field__mdt f = (Time_Drive_Detail_Field__mdt) part;
      if (String.isNotBlank(f.Field__c) && d.details.size() < MAX_DETAILS) {
        d.details.add(new DetailDraft(f));
      }
    }
    d.highlights = new List<HighlightDraft>();
    for (SObject part : templateParts(Time_Drive_Highlight__mdt.getAll().values(), t.DeveloperName)) {
      Time_Drive_Highlight__mdt h = (Time_Drive_Highlight__mdt) part;
      if (String.isNotBlank(h.Field__c) && d.highlights.isEmpty()) {
        d.highlights.add(new HighlightDraft(h));
      }
    }
    Time_Drive_Record__c row = driveRecord(d);
    row.Template_Key__c = t.DeveloperName;
    row.Template_Version__c = 1;
    return row;
  }

  // A template's own detail or highlight records, in sequence order.
  private static List<SObject> templateParts(List<SObject> all, String templateKey) {
    List<SObject> mine = new List<SObject>();
    for (SObject part : all) {
      if (((SObject) part.getSObject('Source__r')).get('DeveloperName') == templateKey) {
        mine.add(part);
      }
    }
    mine.sort(new PartOrder());
    return mine;
  }

  private class PartOrder implements System.Comparator<SObject> {
    /**
     * Orders records by Sequence__c, with records that have none last.
     * @param a The first record.
     * @param b The second record.
     * @return A negative number when a comes first, zero when they tie, a positive number when b comes first.
     */
    public Integer compare(SObject a, SObject b) {
      Decimal sa = (Decimal) a.get('Sequence__c');
      Decimal sb = (Decimal) b.get('Sequence__c');
      return sa == sb ? 0 : (sa == null ? 1 : (sb == null ? -1 : (sa < sb ? -1 : 1)));
    }
  }

  /** A shipped template as the template picker lists it. */
  public class TemplateOption implements Comparable {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String parentObject;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String objectLabel;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String iconColour;
    @AuraEnabled
    public Boolean added;
    private Decimal sequence;

    /**
     * Builds the option from a template record.
     * @param t The template.
     * @param added Whether the template has been added already.
     */
    public TemplateOption(Time_Drive_Source__mdt t, Boolean added) {
      SourceSummary s = new SourceSummary(t);
      key = t.DeveloperName;
      label = t.Label;
      parentObject = s.parentObject;
      kind = s.kind;
      objectLabel = s.objectLabel;
      summary = s.summary;
      icon = t.Icon__c;
      iconColour = t.Icon_Colour__c;
      sequence = t.Sequence__c;
      this.added = added;
    }

    /**
     * Orders options by record page, then sequence, then label.
     * @param other The option to compare with.
     * @return A negative number, zero or a positive number.
     */
    public Integer compareTo(Object other) {
      TemplateOption that = (TemplateOption) other;
      if (parentObject != that.parentObject) {
        return parentObject.compareTo(that.parentObject);
      }
      Decimal mine = sequence == null ? 0 : sequence;
      Decimal theirs = that.sequence == null ? 0 : that.sequence;
      return mine == theirs ? label.compareTo(that.label) : (mine < theirs ? -1 : 1);
    }
  }

  // ---- the wizard's questions ---------------------------------------------

  /**
   * Objects to choose from: 'standard' or 'custom' Salesforce objects whose
   * records link to the parent object's (only those can be plotted), each
   * saying how; or 'dmo' Data 360 data model objects, which link through the
   * unified profile, leaving out its Profile objects and contact points. Labels first.
   * @param kind standard, custom or dmo.
   * @param parentObject The record page's object; Contact when blank.
   * @param dataSpace The Data 360 data space to read DMO names from (dmo only).
   * @return The objects to choose from, by label.
   */
  @AuraEnabled
  public static List<Option> getObjects(String kind, String parentObject, String dataSpace) {
    requireSetupAccess();
    List<Option> out = new List<Option>();
    if (kind == 'dmo') {
      // The DMOs the global describe lists, and those Data 360 names (it
      // doesn't list them in every org, though each describes by name).
      Set<String> names = new Set<String>();
      for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
        String name = t.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (name.toLowerCase().endsWith('__dlm')) {
          names.add(name);
        }
      }
      names.addAll(catalogDmoNames(dataSpace));
      // Profile DMOs (Individual, Party, Account) and contact points say who someone is, not what
      // they did: not offered.
      Set<String> seen = new Set<String>();
      for (String profile : TimeDriveData360Provider.profileDmoNames(dataSpace)) {
        seen.add(profile.toLowerCase());
      }
      for (String name : names) {
        if (CONTACT_POINT_DMO.matcher(name).matches()) {
          continue;
        }
        Schema.SObjectType t = TimeDriveConfig.sObjectType(name);
        Schema.DescribeSObjectResult d = t?.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (d != null && d.isQueryable() && seen.add(d.getName().toLowerCase())) {
          out.add(new Option(d.getName(), d.getLabel(), 'For the unified profile').plural(d.getLabelPlural()));
        }
      }
      out.sort();
      return out;
    }
    Map<String, List<Link>> links = linksFor(String.isBlank(parentObject) ? 'Contact' : parentObject);
    for (String name : links.keySet()) {
      Schema.DescribeSObjectResult d = TimeDriveConfig.sObjectType(name).getDescribe(SObjectDescribeOptions.DEFERRED);
      Boolean custom = d.isCustom();
      if ((kind == 'custom' && custom) || (kind == 'standard' && !custom)) {
        List<Link> ways = links.get(name);
        String how = ways.size() == 1 ? ways[0].how : ways.size() + ' ways to link';
        out.add(new Option(name, d.getLabel(), how).plural(d.getLabelPlural()));
      }
    }
    out.sort();
    return out;
  }

  private static Boolean skipped(String lower) {
    if (PLUMBING.contains(lower)) {
      return true;
    }
    // Platform events end in "event"; the calendar's Event doesn't count.
    if (lower == 'event') {
      return false;
    }
    for (String suffix : SKIPPED_SUFFIXES) {
      if (lower.endsWith(suffix)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Apex classes that can feed the timeline: ones extending
   * TimeDriveApexSource.
   * @return The classes.
   */
  // Setup only (requireSetupAccess()): class names, to offer as providers.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  @AuraEnabled
  public static List<Option> getApexProviders() {
    requireSetupAccess();
    List<Option> out = new List<Option>();
    for (ApexClass c : [
      SELECT Name
      FROM ApexClass
      WHERE NamespacePrefix = NULL AND Status = 'Active'
      ORDER BY Name
      LIMIT 2000
    ]) {
      if (c.Name.endsWithIgnoreCase('Test')) {
        continue;
      }
      // A class that no longer compiles (or can't be made) is skipped, so one
      // broken class never empties the list.
      Object instance;
      try {
        Type t = Type.forName(c.Name);
        if (t == null) {
          continue;
        }
        instance = t.newInstance();
      } catch (Exception e) {
        continue;
      }
      if (instance instanceof TimeDriveApexSource) {
        out.add(new Option(c.Name, c.Name, null));
      }
    }
    return out;
  }

  /**
   * A custom label's value in the user's language, for the wizard to show
   * what a legend name like $Label.Timeline_Follow_ups reads as; null when
   * there's no custom label by that name.
   * @param name The custom label's name.
   * @return The label's text, or null when there is none.
   */
  @AuraEnabled(cacheable=true)
  public static String getLabelText(String name) {
    requireSetupAccess();
    return TimeDriveConfig.customLabel(name);
  }

  /**
   * How records of an object link to the page's record (see linkMap).
   * @param parentObject The record page's object.
   * @param objectName The API name of the object to link.
   * @return The ways the object links to the page's record, with the diagram labels filled in.
   */
  @AuraEnabled
  public static List<Link> getLinks(String parentObject, String objectName) {
    requireSetupAccess();
    Schema.DescribeSObjectResult target = describe(objectName);
    List<Link> links = linksFor(parentObject).get(target.getName());
    if (links == null) {
      return new List<Link>();
    }
    for (Link l : links) {
      diagram(l, target, parentObject);
    }
    return links;
  }

  /**
   * Whether an object is the change event, history, feed or share companion of another object.
   * @param objectName The API name of the object.
   * @return True when the name ends in ChangeEvent, History, Feed or Share.
   */
  @TestVisible
  private static Boolean isCompanion(String objectName) {
    return objectName.endsWith('ChangeEvent') ||
      objectName.endsWith('History') ||
      objectName.endsWith('Feed') ||
      objectName.endsWith('Share');
  }

  /**
   * Every object whose records link to the parent's, and how: by a lookup on the object to the
   * parent (Case.ContactId), or through a junction under the parent with a required lookup to the
   * object, as OpportunityContactRole links Opportunities to a Contact. Junction lookups must each
   * point at one object: polymorphic ones (an attachment's parent) link anything to anything.
   * @param parent The describe of the parent object.
   * @return The links, by the API name of the linked object.
   */
  private static Map<String, List<Link>> linkMap(Schema.DescribeSObjectResult parent) {
    Map<String, List<Link>> out = new Map<String, List<Link>>();
    Set<String> seen = new Set<String>();
    for (Schema.ChildRelationship cr : parent.getChildRelationships()) {
      // The change-event, history, feed and share companions of the parent's
      // children are never sources: passed over by name, before any metadata is
      // loaded for them (a third of a big org's children are change events).
      if (isCompanion(String.valueOf(cr.getChildSObject()))) {
        continue;
      }
      Schema.DescribeSObjectResult child = cr.getChildSObject().getDescribe(SObjectDescribeOptions.DEFERRED);
      String childName = child.getName();
      // Objects that can't be a source are passed over before anything about
      // their fields is read: describing a lookup loads its whole object, which
      // is most of what this costs in an org with hundreds of children.
      if (
        !ACTIVITY_RELATIONS.containsKey(childName) &&
        (!child.isQueryable() ||
        !child.isAccessible() ||
        skipped(childName.toLowerCase()))
      ) {
        continue;
      }
      Schema.DescribeFieldResult lookup = cr.getField()?.getDescribe();
      // A task's or event's relations: every contact on it (with Shared
      // Activities, the primary one too; for events, invitees as well).
      // RelationId points at several objects, so these are named here.
      if (ACTIVITY_RELATIONS.containsKey(childName) && lookup?.getName() == 'RelationId') {
        String record = ACTIVITY_RELATIONS.get(childName);
        String target = record == 'TaskId' ? 'Task' : 'Event';
        Schema.DescribeSObjectResult targetDescribe = describe(target);
        if (seen.add(childName + '.' + record) && targetDescribe.isQueryable() && targetDescribe.isAccessible()) {
          Link every = new Link(
            childName,
            lookup.getName(),
            record,
            targetDescribe.getLabelPlural() + ' this ' + parent.getLabel() + ' is on, through ' + child.getLabel()
          );
          every.how = 'Every ' + parent.getLabel() + ' on it';
          every.everyContact = true;
          every.note = target == 'Task'
            ? 'Every contact on the task, not only its primary one (Shared Activities).'
            : 'Every contact on the event, invitees too, not only its primary one.';
          List<Link> ways = out.containsKey(target) ? out.get(target) : new List<Link>();
          ways.add(0, every);
          out.put(target, ways);
        }
        // The relation object as a source of its own (TaskRelation): one row
        // for each contact on a task, its date and filter read from the task
        // by path (Task.ActivityDate), counted from the relation, which is
        // faster than from the task for a contact on a great many.
        if (
          RELATION_RECORDS.containsKey(childName) &&
          child.isQueryable() &&
          child.isAccessible() &&
          seen.add(childName + '.' + lookup.getName() + '.own')
        ) {
          Link own = new Link(
            lookup.getName(),
            child.getLabelPlural() +
              ' whose ' +
              lookup.getLabel().removeEnd(' ID') +
              ' (' +
              lookup.getName() +
              ') is this ' +
              parent.getLabel()
          );
          String recordWord = RELATION_RECORDS.get(childName).toLowerCase();
          String aRecordWord = (recordWord.left(1).containsAny('aeiou') ? 'an ' : 'a ') + recordWord;
          own.how = 'One for each ' + parent.getLabel() + ' on ' + aRecordWord;
          own.everyContact = true;
          own.note =
            'Each is one ' +
            parent.getLabel().toLowerCase() +
            ' on ' +
            aRecordWord +
            '. Choose its ' +
            recordWord +
            '\'s fields by path (' +
            RELATION_RECORDS.get(childName) +
            ' › ...), and it opens the ' +
            recordWord +
            '.';
          addLink(out, childName, own);
        }
        continue;
      }
      if (
        lookup == null ||
        !child.isQueryable() ||
        // Not an object this user can see: they couldn't read its fields to set it up.
        !child.isAccessible() ||
        skipped(childName.toLowerCase()) ||
        !seen.add(childName + '.' + lookup.getName())
      ) {
        continue;
      }
      // A direct lookup: the object's own, to the parent or (like an
      // activity's Name) to the parent or a Lead. Wider ones (a relation's
      // "related to anything") and records people don't create are plumbing.
      // Only a field that can hold the parent's own record: a person
      // account's Contact relationships (Task.WhoId) come through the Contact.
      Boolean activity = childName == 'Task' || childName == 'Event';
      Boolean relatedTo = activity && lookup.getName() == 'WhatId';
      // A file is linked to a record by LinkedEntityId, which can be any of
      // them: the one lookup that is wider than two objects and still a choice.
      Boolean file = childName == 'ContentDocumentLink' && lookup.getName() == 'LinkedEntityId';
      if (
        lookup.isFilterable() &&
        child.isCreateable() &&
        lookup.getReferenceTo().contains(parent.getSObjectType()) &&
        (lookup.getReferenceTo().size() <= 2 ||
        relatedTo ||
        file)
      ) {
        String field = lookup.getLabel().removeEnd(' ID') + ' (' + lookup.getName() + ')';
        Link direct = new Link(
          lookup.getName(),
          child.getLabelPlural() + ' whose ' + field + ' is this ' + parent.getLabel()
        );
        direct.how = 'Linked by ' + lookup.getLabel().removeEnd(' ID');
        if (file) {
          direct.note =
            'Each is one file linked to this ' +
            parent.getLabel().toLowerCase() +
            '. A link has no date of its own but when it last changed: choose the file\'s by path ' +
            '(Content Document › Created Date), and its name with {ContentDocument.Title}.';
        }
        if (activity && lookup.getName() == 'AccountId') {
          direct.note =
            'Salesforce fills Account (AccountId) itself: from Related To when that\'s this account or one of its records, ' +
            'else from the Name contact\'s account. So it catches ' +
            child.getLabelPlural().toLowerCase() +
            ' linked either way.';
        }
        addLink(out, childName, direct);
      }
      if (lookup.getReferenceTo().size() != 1) {
        continue;
      }
      Map<String, Schema.SObjectField> childFields = child.fields.getMap();
      for (String fieldKey : childFields.keySet()) {
        // A lookup's name ends in Id (or __c): the rest aren't described.
        if (!fieldKey.endsWith('id') && !fieldKey.endsWith('__c')) {
          continue;
        }
        Schema.DescribeFieldResult fd = childFields.get(fieldKey).getDescribe();
        if (
          fd.getType() != Schema.DisplayType.REFERENCE ||
          fd.isNillable() ||
          fd.getReferenceTo().size() != 1 ||
          AUDIT_FIELDS.contains(fd.getName()) ||
          fd.getName() == lookup.getName()
        ) {
          continue;
        }
        Schema.DescribeSObjectResult target = fd.getReferenceTo()[0].getDescribe(SObjectDescribeOptions.DEFERRED);
        String targetName = target.getName();
        if (
          targetName == parent.getName() ||
          SETUP_OBJECTS.contains(targetName) ||
          childName == 'User' ||
          !target.isQueryable() ||
          !target.isAccessible() ||
          skipped(targetName.toLowerCase())
        ) {
          continue;
        }
        Link junction = new Link(
          childName,
          lookup.getName(),
          fd.getName(),
          target.getLabelPlural() + ' this ' + parent.getLabel() + ' is on, through ' + child.getLabel()
        );
        junction.how = 'Through ' + child.getLabel();
        addLink(out, targetName, junction);
      }
    }
    return out;
  }

  /**
   * What the Link step's diagram draws: each object's label and name field,
   * and each lookup's label, the object it points to, and whether it's a
   * master-detail (the record can't exist without its parent) or a lookup.
   * @param l The link to fill in.
   * @param target The describe of the linked object.
   * @param parentObject The record page's object.
   */
  private static void diagram(Link l, Schema.DescribeSObjectResult target, String parentObject) {
    l.objectLabel = target.getLabel();
    l.objectNameLabel = nameLabel(target);
    Schema.DescribeSObjectResult holder = String.isBlank(l.junctionObject) ? target : describe(l.junctionObject);
    Schema.DescribeFieldResult toParent = holder.fields.getMap()
      .get((String.isBlank(l.junctionObject) ? l.parentField : l.junctionParentField).toLowerCase())
      ?.getDescribe();
    if (toParent != null) {
      l.fieldLabel = toParent.getLabel();
      l.masterDetail = toParent.getRelationshipOrder() != null;
      Schema.DescribeSObjectResult parent = pageObject(toParent, parentObject)
        .getDescribe(SObjectDescribeOptions.DEFERRED);
      l.parentLabel = parent.getLabel();
      l.parentNameLabel = nameLabel(parent);
    }
    if (String.isNotBlank(l.junctionObject)) {
      l.junctionLabel = holder.getLabel();
      l.junctionNameLabel = nameLabel(holder);
      Schema.DescribeFieldResult toRecord = holder.fields.getMap()
        .get(l.junctionRecordField.toLowerCase())
        ?.getDescribe();
      if (toRecord != null) {
        l.recordFieldLabel = toRecord.getLabel();
        l.recordMasterDetail = toRecord.getRelationshipOrder() != null;
      }
    }
  }

  // The object a lookup points to on this page: the page's own when it can
  // point to several (an activity's RelationId), else its one.
  private static Schema.SObjectType pageObject(Schema.DescribeFieldResult lookup, String parentObject) {
    for (Schema.SObjectType t : lookup.getReferenceTo()) {
      String name = t.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
      if (
        name == parentObject ||
        (parentObject == TimeDriveController.PERSON_ACCOUNT && (name == 'Account' || name == 'Contact'))
      ) {
        return t;
      }
    }
    return lookup.getReferenceTo()[0];
  }

  private static String nameLabel(Schema.DescribeSObjectResult d) {
    String named = d.getName();
    if (nameLabels.containsKey(named)) {
      return nameLabels.get(named);
    }
    Map<String, Schema.SObjectField> fields = d.fields.getMap();
    String found;
    for (String guess : NAME_FIELD_GUESSES) {
      Schema.SObjectField f = fields.get(guess);
      if (f != null && f.getDescribe().isNameField()) {
        found = f.getDescribe().getLabel();
        break;
      }
    }
    if (found == null) {
      found = 'Name';
      for (Schema.SObjectField f : fields.values()) {
        Schema.DescribeFieldResult fd = f.getDescribe();
        if (fd.isNameField()) {
          found = fd.getLabel();
          break;
        }
      }
    }
    nameLabels.put(named, found);
    return found;
  }

  /**
   * The links for a record page. A person account is an Account with its
   * own Contact, so its records link either way: by an Account lookup
   * (Case.AccountId) or a Contact one (Task.WhoId, Case.ContactId).
   * @param parentObject The record page's object.
   * @return The links by linked object, without those that need a setting the org lacks.
   */
  private static Map<String, List<Link>> linksFor(String parentObject) {
    return withoutUnused(personLinks(parentObject));
  }

  // Links through a setting the org doesn't have (see linkNeeds) stay out of
  // sight.
  private static Map<String, List<Link>> withoutUnused(Map<String, List<Link>> links) {
    Set<String> used = orgFeatures();
    for (String objectName : links.keySet()) {
      List<Link> kept = new List<Link>();
      for (Link l : links.get(objectName)) {
        String need = linkNeeds(l);
        if (need == null || used.contains(need)) {
          kept.add(l);
        }
      }
      links.put(objectName, kept);
    }
    for (String objectName : new List<String>(links.keySet())) {
      if (links.get(objectName).isEmpty()) {
        links.remove(objectName);
      }
    }
    return links;
  }

  // The org setting a link needs: every contact on a task or event comes
  // with Shared Activities; an account's related contacts with Contacts to
  // Multiple Accounts.
  @TestVisible
  private static String linkNeeds(Link l) {
    if (l.everyContact == true) {
      return 'SharedActivities';
    }
    if (l.junctionObject == 'AccountContactRelation') {
      return 'ContactsToMultipleAccounts';
    }
    return null;
  }

  private static Map<String, List<Link>> personLinks(String parentObject) {
    if (parentObject != TimeDriveController.PERSON_ACCOUNT) {
      return linkMap(describe(parentObject));
    }
    // Say which side each link uses: the Account, or the person's Contact.
    Map<String, List<Link>> out = linkMap(describe('Account'));
    for (List<Link> ways : out.values()) {
      for (Link l : ways) {
        l.label = l.label.replace('is this Account', 'is this person account');
        l.kindText = 'A lookup to the person account (its Account)';
      }
    }
    Map<String, List<Link>> viaContact = linkMap(describe('Contact'));
    for (String objectName : viaContact.keySet()) {
      for (Link l : viaContact.get(objectName)) {
        l.label = l.label.replace('is this Contact', 'is this person (their Contact)')
          .replace('this Contact is on', 'this person is on');
        l.kindText = l.junctionObject == null
          ? 'A lookup to the person (their Contact)'
          : 'Through a related object, by the person\'s Contact';
        addLink(out, objectName, l);
      }
    }
    return out;
  }

  private static void addLink(Map<String, List<Link>> links, String objectName, Link link) {
    if (!links.containsKey(objectName)) {
      links.put(objectName, new List<Link>());
    }
    links.get(objectName).add(link);
  }

  /**
   * The object's fields the user can read, with what the wizard needs to know.
   * @param objectName The API name of the object.
   * @return The readable fields, by label.
   */
  @AuraEnabled(cacheable=true)
  public static List<FieldInfo> getFields(String objectName) {
    requireSetupAccess();
    List<FieldInfo> out = new List<FieldInfo>();
    for (Schema.SObjectField f : describe(objectName).fields.getMap().values()) {
      Schema.DescribeFieldResult fd = f.getDescribe();
      if (fd.isAccessible()) {
        out.add(new FieldInfo(fd));
      }
    }
    out.sort();
    return out;
  }
  private static List<String> catalogDmoNames(String dataSpace) {
    return testDmoNames != null ? testDmoNames : TimeDriveData360Provider.dmoNames(dataSpace);
  }

  /**
   * The org's active Data 360 data spaces, by name; none without Data 360.
   * Data 360 sources ask for one only when there's more than one.
   * @return The data spaces, or an empty list without Data 360.
   */
  @AuraEnabled(cacheable=true)
  public static List<Option> getDataSpaces() {
    requireSetupAccess();
    List<Option> out = new List<Option>();
    if (testDataSpaces != null) {
      return testDataSpaces;
    }
    try {
      // Queried by name: DataSpace exists only in orgs with Data 360.
      for (
        SObject ds : Database.query(
          'SELECT Name, DataSpaceApiName FROM DataSpace WHERE Status = \'ACTIVE\' ORDER BY Name',
          AccessLevel.USER_MODE
        )
      ) {
        String name = (String) ds.get('Name');
        String apiName = (String) ds.get('DataSpaceApiName');
        out.add(new Option(String.isBlank(apiName) ? name : apiName, name, (String) ds.get('DataSpaceApiName')));
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.WARN, 'Time Drive Setup: no data spaces read. ' + e.getMessage());
    }
    return out;
  }

  /**
   * Whether the wizard can offer Data 360 sources: the Data 360 add-on
   * (force-app-data360) is installed. When it isn't, the reason is a line
   * for the wizard, which says whether the org lacks Data 360 itself or
   * only the add-on.
   * @return Whether Data 360 sources can be offered, and the reason when they can't.
   */
  @AuraEnabled(cacheable=true)
  public static Data360Status getData360Status() {
    requireSetupAccess();
    if (testData360Status != null) {
      return testData360Status;
    }
    if (TimeDriveData360Provider.addOnInstalled()) {
      return new Data360Status(true, null);
    }
    // DataSpace exists only in orgs with Data 360.
    return TimeDriveConfig.sObjectType('DataSpace') == null
      ? new Data360Status(false, 'This org doesn\'t have Data 360.')
      : new Data360Status(false, 'Install the Time Drive Data 360 add-on package to use Data 360.');
  }

  /** Whether the Data 360 add-on is ready, and the reason when it is not. */
  public class Data360Status {
    @AuraEnabled
    public Boolean ready;
    @AuraEnabled
    public String reason;

    /**
     * Builds the status.
     * @param ready Whether Data 360 sources can be offered.
     * @param reason The line for the wizard when they can't, or null.
     */
    public Data360Status(Boolean ready, String reason) {
      this.ready = ready;
      this.reason = reason;
    }
  }

  private static Schema.DescribeSObjectResult describe(String objectName) {
    Schema.SObjectType t = TimeDriveConfig.sObjectType(objectName);
    if (t == null) {
      throw failure('There is no object called ' + objectName + ' in this org.');
    }
    return t.getDescribe(SObjectDescribeOptions.DEFERRED);
  }

  /**
   * How many records a draft would read, over each range the wizard offers
   * (3 months to 5 years, and all time), and how many parents have any, so
   * the page can say roughly how many each has. Counts what the user can
   * see; counts that can't be had (Data 360 without it, a junction) are null.
   * @param draftJson The source draft, as JSON.
   * @return The record counts, with null where a count can't be had.
   */
  // Setup only. The parent field is checked against the object's describe, condition fields are identifiers and their values escaped, and the query runs in user mode; only an admin's own fixed filter text is added as written.
  @SuppressWarnings('PMD.ApexSOQLInjection')
  @AuraEnabled
  public static Volume getVolumes(String draftJson) {
    requireSetupAccess();
    SourceDraft d = (SourceDraft) JSON.deserialize(draftJson, SourceDraft.class);
    Volume v = new Volume();
    if (String.isBlank(d.objectName) || String.isBlank(d.dateField) || d.kind == TimeDriveContext.KIND_APEX) {
      return v;
    }
    Schema.DescribeSObjectResult target = describe(d.objectName);
    // The date may be reached through a lookup (Task.ActivityDate on TaskRelation).
    Schema.DescribeFieldResult dateInfo = TimeDriveConfig.fieldDescribe(target.getName(), d.dateField);
    if (dateInfo == null) {
      return v;
    }
    TimeDriveConfig.PathField datePath = TimeDriveConfig.pathField(target.getName(), d.dateField);
    Boolean dateOnly = dateInfo.getType() == Schema.DisplayType.DATE;
    String filter = d.filterText();
    String base = 'SELECT COUNT() FROM ' + target.getName();
    // Archived Tasks and Events count too, as the timeline plots them.
    archived = TimeDriveSoqlProvider.ARCHIVED_OBJECTS.contains(datePath?.owner ?? target.getName());
    String reach = datePath?.prefix ?? '';
    String scope = archived
      ? (reach != '' && target.fields.getMap().containsKey('isdeleted') ? 'IsDeleted = false AND ' : '') +
        reach +
        'IsDeleted = false'
      : '';
    scope += String.isBlank(filter) ? '' : (String.isBlank(scope) ? '' : ' AND ') + '(' + filter + ')';
    v.total = count(base, scope, new Map<String, Object>());
    v.more = v.total != null && v.total > COUNT_CAP;
    Date today = Date.today();
    for (Integer months : RANGES) {
      Date first = today.addMonths(-months);
      Map<String, Object> binds = new Map<String, Object>{
        'first' => dateOnly ? (Object) first : Datetime.newInstance(first, Time.newInstance(0, 0, 0, 0))
      };
      String clause = d.dateField + ' >= :first' + (String.isBlank(scope) ? '' : ' AND ' + scope);
      VolumeRange r = new VolumeRange();
      r.months = months;
      r.count = count(base, clause, binds);
      r.more = r.count != null && r.count > COUNT_CAP;
      v.ranges.add(r);
    }
    // Parents with any: a direct lookup can be counted distinct; a junction
    // or Data 360's unified profile can't, cheaply.
    if (
      String.isNotBlank(d.parentField) &&
      target.fields.getMap().containsKey(d.parentField.toLowerCase()) &&
      String.isBlank(d.junctionObject) &&
      d.kind != TimeDriveContext.KIND_DATA_360
    ) {
      try {
        String q =
          'SELECT COUNT_DISTINCT(' +
          d.parentField +
          ') n FROM ' +
          target.getName() +
          (String.isBlank(scope) ? '' : ' WHERE ' + scope) +
          (archived ? ' ALL ROWS' : '');
        AggregateResult a = (AggregateResult) Database.query(q, AccessLevel.USER_MODE)[0];
        v.parents = (Integer) a.get('n');
      } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Time Drive Setup: parents not counted. ' + e.getMessage());
      }
    }
    return v;
  }

  private static Integer count(String base, String scope, Map<String, Object> binds) {
    try {
      String q =
        base +
        (String.isBlank(scope) ? '' : ' WHERE ' + scope) +
        ' LIMIT ' +
        (COUNT_CAP + 1) +
        (archived ? ' ALL ROWS' : '');
      return Database.countQueryWithBinds(q, binds, AccessLevel.USER_MODE);
    } catch (Exception e) {
      System.debug(LoggingLevel.WARN, 'Time Drive Setup: not counted. ' + e.getMessage());
      return null;
    }
  }

  // ---- preview -------------------------------------------------------------

  /**
   * The events a draft source would plot for a record, through the same
   * providers and plotter the timeline uses, over the last year (and the
   * next, for future-dated records).
   * @param draftJson The source draft, as JSON.
   * @param recordId The record to plot events for.
   * @return The first events found, how many there were, and any warnings or problems.
   */
  @AuraEnabled
  public static Preview preview(String draftJson, Id recordId) {
    requireSetupAccess();
    SourceDraft d = (SourceDraft) JSON.deserialize(draftJson, SourceDraft.class);
    Preview p = new Preview();
    if (recordId == null) {
      return p;
    }
    Time_Drive_Source__mdt s = d.toRecord();
    TimeDriveRowProvider provider = TimeDriveConfig.providerFor(s, p.warnings);
    if (provider == null) {
      return p;
    }
    TimeDriveContext context = new TimeDriveContext(
      recordId,
      recordId.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
      Datetime.now().addYears(-1),
      s,
      null,
      p.warnings
    );
    context.until = Datetime.now().addYears(1);
    context.personContactId = TimeDriveController.personContactOf(recordId);
    context.draftDetailFields = d.detailRecords();
    context.draftHighlights = d.highlightRecords();
    try {
      List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(provider, context);
      events.sort();
      p.total = events.size();
      for (Integer i = 0; i < Math.min(events.size(), 8); i++) {
        p.events.add(events[i]);
      }
    } catch (Exception e) {
      context.fail(s.Label, e);
    }
    p.problems = context.problems;
    return p;
  }

  // ---- saving --------------------------------------------------------------

  /**
   * Saves a source (new or changed) and its detail fields.
   * @param draftJson The source draft, as JSON.
   * @return A ticket with the source's name.
   */
  @AuraEnabled
  public static SaveTicket save(String draftJson) {
    requireSetupAccess();
    SourceDraft d = (SourceDraft) JSON.deserialize(draftJson, SourceDraft.class);
    if (d.highlights == null) {
      d.highlights = new List<HighlightDraft>();
    }
    // At most one highlight, with a field (a checkbox).
    List<HighlightDraft> kept = new List<HighlightDraft>();
    for (HighlightDraft h : d.highlights) {
      if (String.isNotBlank(h.field) && kept.size() < TimeDriveHighlights.MAX_RULES) {
        kept.add(h);
      }
    }
    d.highlights = kept;
    validate(d);
    if (String.isBlank(d.developerName)) {
      d.developerName = uniqueName(d.label);
    }
    // The legend's order, when the wizard sends one: this source's place,
    // and any other source whose place changed, in the same save.
    Map<String, Time_Drive_Record__c> rows = new Map<String, Time_Drive_Record__c>();
    for (Time_Drive_Record__c moved : reordered(d)) {
      rows.put(moved.Key__c, moved);
    }
    rows.put(d.developerName, driveRecord(d));
    write(rows.values());
    return new SaveTicket(d.developerName);
  }

  /**
   * Places the draft in its legend order (sequence 10, 20, …) and returns
   * the other sources whose sequence that changes, ready to save.
   * @param d The draft whose place in the legend is set.
   * @return The other sources whose sequence changed, as records to save.
   */
  @TestVisible
  private static List<Time_Drive_Record__c> reordered(SourceDraft d) {
    List<Time_Drive_Record__c> out = new List<Time_Drive_Record__c>();
    if (d.legendOrder == null || d.legendOrder.isEmpty()) {
      return out;
    }
    for (Integer i = 0; i < d.legendOrder.size(); i++) {
      String name = d.legendOrder[i];
      Decimal place = (i + 1) * 10;
      if (name == THIS_SOURCE || name == d.developerName) {
        d.sequence = place;
        continue;
      }
      Time_Drive_Source__mdt other = TimeDriveConfig.source(name);
      if (other == null || other.Sequence__c == place) {
        continue;
      }
      out.add(new Time_Drive_Record__c(Key__c = name, Sequence__c = place));
    }
    return out;
  }

  // ---- the timeline's views ------------------------------------------------

  /**
   * The views as Setup shows them: key, name in the viewer's language, the
   * custom label behind it (renaming is translating that), and whether the
   * picker offers it.
   * @return The views, with their labels and whether the picker offers them.
   */
  @AuraEnabled
  public static List<ViewDraft> getViewDrafts() {
    requireSetupAccess();
    List<ViewDraft> out = new List<ViewDraft>();
    for (Time_Drive_View__mdt v : TimeDriveConfig.views()) {
      ViewDraft d = new ViewDraft();
      d.developerName = v.DeveloperName;
      d.name = v.Label;
      d.menuLabel = v.Menu_Label__c;
      String raw = v.Menu_Label__c?.trim();
      d.labelName = String.isNotBlank(raw) && raw.startsWith(TimeDriveConfig.LABEL_PREFIX)
        ? raw.substring(TimeDriveConfig.LABEL_PREFIX.length())
        : null;
      d.sequence = v.Sequence__c;
      d.shown = TimeDriveConfig.viewLabel(v);
      d.active = TimeDriveConfig.isActive(v);
      out.add(d);
    }
    return out;
  }

  /**
   * Saves which views the picker offers: the ones switched off are kept on
   * the org's Time_Drive_Setup__c record. All is always offered. Names come
   * from custom labels, so a view is renamed by changing its label's
   * translation, not here.
   * @param viewsJson The views as JSON, each with the Active flag to save.
   * @return A ticket naming what was saved (Views).
   */
  @AuraEnabled
  public static SaveTicket saveViews(String viewsJson) {
    requireSetupAccess();
    List<ViewDraft> drafts = (List<ViewDraft>) JSON.deserialize(viewsJson, List<ViewDraft>.class);
    Set<String> known = new Set<String>();
    for (Time_Drive_View__mdt v : TimeDriveConfig.views()) {
      known.add(v.DeveloperName);
    }
    Set<String> hidden = new Set<String>(TimeDriveConfig.hiddenViews());
    for (ViewDraft d : drafts) {
      if (!known.contains(d.developerName)) {
        throw failure('There is no view called ' + d.developerName + '.');
      }
      Boolean active = d.active != false;
      if (d.developerName == TimeDriveConfig.ALL_VIEW && !active) {
        throw failure('All items is always offered.');
      }
      if (active) {
        hidden.remove(d.developerName);
      } else {
        hidden.add(d.developerName);
      }
    }
    // Views that no longer exist drop out of the list.
    hidden.retainAll(known);
    Time_Drive_Setup__c row = progressRow();
    if (row == null) {
      row = new Time_Drive_Setup__c(Name = 'Org');
    }
    List<String> names = new List<String>(hidden);
    names.sort();
    row.Hidden_Views__c = names.isEmpty() ? null : String.join(names, ',');
    // Setup access was checked above; the record is the org's, not each admin's.
    Database.upsert(row, AccessLevel.SYSTEM_MODE);
    TimeDriveConfig.forgetHiddenViews();
    return new SaveTicket('Views');
  }

  /** A timeline view as Setup lists and saves it. */
  public class ViewDraft {
    /** The view's developer name. */
    @AuraEnabled
    public String developerName { get; set; }
    /** The view's name in the viewer's language. */
    @AuraEnabled
    public String name { get; set; }
    /** The Menu Label as stored: plain words or a custom label reference. */
    @AuraEnabled
    public String menuLabel { get; set; }
    /** The custom label behind the name, or null when it is plain words. */
    @AuraEnabled
    public String labelName { get; set; }
    /** The view's place in the picker. */
    @AuraEnabled
    public Decimal sequence { get; set; }
    /** The menu name as it reads in the viewer's language. */
    @AuraEnabled
    public String shown { get; set; }
    /** Whether the picker offers the view. */
    @AuraEnabled
    public Boolean active { get; set; }
  }

  /**
   * Which of those features this org has: each a describe, read once when asked.
   * @return The names of the features the org has.
   */
  public static Set<String> orgFeatures() {
    if (testFeatures != null) {
      return testFeatures;
    }
    Set<String> enabled = new Set<String>();
    Map<String, Schema.SObjectType> objects = Schema.getGlobalDescribe();
    if (objects.containsKey('taskrelation')) {
      enabled.add('SharedActivities');
    }
    if (
      Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().containsKey('ispersonaccount')
    ) {
      enabled.add('PersonAccounts');
    }
    if (objects.containsKey('accountcontactrelation')) {
      enabled.add('ContactsToMultipleAccounts');
    }
    // Enhanced Email: its objects are in every org (Email-to-Case uses them),
    // so the sign is an email saved as an Email Message with its activity,
    // which only Enhanced Email does.
    try {
      if ([SELECT COUNT() FROM EmailMessage WHERE ActivityId != NULL LIMIT 1] > 0) {
        enabled.add('EnhancedEmail');
      }
    } catch (Exception e) {
      // No access to Email Messages: not something to fit to.
      System.debug(LoggingLevel.FINE, 'Time Drive: Email Messages not read. ' + e.getMessage());
    }
    return enabled;
  }

  /**
   * How far Setup has got, for the whole org (see Time_Drive_Setup__c: one record).
   * @return The steps done and the org check's report.
   */
  @AuraEnabled
  public static Progress getProgress() {
    requireSetupAccess();
    Time_Drive_Setup__c row = progressRow();
    Progress out = new Progress();
    out.steps = new List<String>();
    if (row != null && !String.isBlank(row.Steps_Done__c)) {
      for (String key : row.Steps_Done__c.split(',')) {
        out.steps.add(key.trim());
      }
    }
    out.report = row?.Org_Check_Report__c;
    return out;
  }

  /**
   * Keeps the steps done (a list of keys) and/or the org check's report; a null leaves that one as it is.
   * @param steps The keys of the steps done, or null to leave them as they are.
   * @param report The org check's report, or null to leave it as it is.
   */
  @AuraEnabled
  public static void saveProgress(List<String> steps, String report) {
    requireSetupAccess();
    Time_Drive_Setup__c row = progressRow();
    if (row == null) {
      row = new Time_Drive_Setup__c(Name = 'Org');
    }
    if (steps != null) {
      row.Steps_Done__c = String.join(steps, ',').left(255);
    }
    if (report != null) {
      row.Org_Check_Report__c = report.left(32768);
    }
    // Setup access was checked above; the record is the org's, not each admin's.
    Database.upsert(row, AccessLevel.SYSTEM_MODE);
  }

  private static Time_Drive_Setup__c progressRow() {
    List<Time_Drive_Setup__c> rows = [
      SELECT Id, Steps_Done__c, Org_Check_Report__c, Hidden_Views__c
      FROM Time_Drive_Setup__c
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** How far Setup has got. */
  public class Progress {
    @AuraEnabled
    public List<String> steps;
    @AuraEnabled
    public String report;
  }

  /**
   * The things Setup checks, in the order it checks them.
   * @return The checks, each with its label and the setting it reads.
   */
  @AuraEnabled
  public static List<OrgCheck> getOrgCheckSteps() {
    requireSetupAccess();
    List<OrgCheck> out = new List<OrgCheck>();
    for (String key : ORG_CHECKS) {
      OrgCheck check = new OrgCheck(key, CHECK_LABELS.get(key));
      check.setting = CHECK_SETTINGS.get(key)[0];
      check.settingWhere = CHECK_SETTINGS.get(key)[1];
      out.add(check);
    }
    return out;
  }

  /**
   * Runs one check: whether the org has it, what that means here, and the sources it brings.
   * @param key The check's key.
   * @return The check with its result filled in.
   */
  @AuraEnabled
  public static OrgCheck runOrgCheck(String key) {
    requireSetupAccess();
    if (!CHECK_LABELS.containsKey(key)) {
      throw failure('There is no check called ' + key + '.');
    }
    OrgCheck check = new OrgCheck(key, CHECK_LABELS.get(key));
    check.setting = CHECK_SETTINGS.get(key)[0];
    check.settingWhere = CHECK_SETTINGS.get(key)[1];
    try {
      if (FEATURE_LABELS.containsKey(key)) {
        check.present = orgFeatures().contains(key);
        for (Time_Drive_Source__mdt t : applicableTemplates(null)) {
          if (needs(t).contains(key)) {
            check.adds.add(pageLabel(t) + ' ' + t.Label);
          }
        }
        check.adds.sort();
      } else if (key == 'Data360') {
        check.present = getData360Status().ready == true;
      } else {
        check.present = activityCapture().inUse == true;
      }
    } catch (Exception e) {
      check.unknown = true;
    }
    check.found = foundText(key, check);
    check.meaning = meaningText(key, check);
    return check;
  }

  private static String foundText(String key, OrgCheck check) {
    if (check.unknown) {
      return 'Couldn\'t tell';
    }
    if (key == 'ActivityCapture') {
      return check.present ? 'In use' : 'Not in use';
    }
    if (key == 'Data360') {
      return check.present ? 'Connected' : 'Not available';
    }
    return check.present ? 'On' : 'Off';
  }

  private static String meaningText(String key, OrgCheck check) {
    if (check.unknown) {
      return 'We couldn\'t read this setting with your access. The recommended sources assume it is off; you can add the others yourself.';
    }
    Boolean has = check.present;
    if (key == 'SharedActivities') {
      return has
        ? 'Tasks and events can have several contacts. The timeline will include every contact on them, not only the primary one.'
        : 'Each task and event has one contact, its Name. The timeline reads them by that.';
    }
    if (key == 'ContactsToMultipleAccounts') {
      return has
        ? 'A contact can belong to several accounts. An account\'s timeline will include the contacts related to it, not only its direct ones.'
        : 'Each contact belongs to one account, so an account\'s timeline follows its direct contacts.';
    }
    if (key == 'PersonAccounts') {
      return has
        ? 'Person Accounts are in use, so they get a timeline page of their own.'
        : 'There are no Person Accounts here, so that timeline page isn\'t added.';
    }
    if (key == 'EnhancedEmail') {
      return has
        ? 'Emails are saved as Email Messages, so the timeline reads Email Messages instead of email tasks.'
        : 'Emails are logged as tasks, so the timeline reads email tasks.';
    }
    if (key == 'Data360') {
      return has
        ? 'Data 360 is connected, so you can plot engagement from it alongside your Salesforce records.'
        : 'Data 360 isn\'t set up here, so only Salesforce records are plotted.';
    }
    return has
      ? 'Einstein Activity Capture is in use. Its emails reach the timeline only when Sync Email as Salesforce Activity is on: please check that setting.'
      : 'Einstein Activity Capture isn\'t in use, so there is nothing to check for email sync.';
  }

  /** One org check and what it found. */
  public class OrgCheck {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean present = false;
    @AuraEnabled
    public Boolean unknown = false;
    // The setting read, and where it is in Setup.
    @AuraEnabled
    public String setting;
    @AuraEnabled
    public String settingWhere;
    @AuraEnabled
    public String found;
    @AuraEnabled
    public String meaning;
    // The sources this check brings with it ("Contact Tasks (every contact)").
    @AuraEnabled
    public List<String> adds = new List<String>();

    /**
     * Builds a check not yet run.
     * @param key The check's key.
     * @param label The check's label.
     */
    public OrgCheck(String key, String label) {
      this.key = key;
      this.label = label;
    }
  }

  /**
   * Which org-fitted sources tied to a setting should be active, given the
   * settings used: in a group, the one needing the most of them (and nothing
   * else); alone, one whose needs are all used. Sources tied to no setting
   * aren't in the map, so fitting never touches them.
   * @param used The settings the org uses.
   * @return Whether each tied source should be active, by developer name.
   */
  @TestVisible
  private static Map<String, Boolean> targets(Set<String> used) {
    Map<String, List<Time_Drive_Source__mdt>> groups = new Map<String, List<Time_Drive_Source__mdt>>();
    Map<String, Boolean> out = new Map<String, Boolean>();
    for (Time_Drive_Source__mdt s : fittedSources()) {
      if (String.isNotBlank(s.Variant_Group__c)) {
        String key = s.Parent_Object__c + '|' + s.Variant_Group__c;
        if (!groups.containsKey(key)) {
          groups.put(key, new List<Time_Drive_Source__mdt>());
        }
        groups.get(key).add(s);
      } else if (!needs(s).isEmpty()) {
        out.put(s.DeveloperName, used.containsAll(needs(s)));
      }
    }
    for (List<Time_Drive_Source__mdt> variants : groups.values()) {
      Boolean tied = false;
      Time_Drive_Source__mdt best;
      for (Time_Drive_Source__mdt s : variants) {
        tied = tied || !needs(s).isEmpty();
        if (used.containsAll(needs(s)) && (best == null || outranks(s, best))) {
          best = s;
        }
      }
      if (!tied) {
        continue;
      }
      for (Time_Drive_Source__mdt s : variants) {
        out.put(s.DeveloperName, s == best);
      }
    }
    return out;
  }

  /**
   * Einstein Activity Capture, when any of its permission set licences are
   * assigned. Its emails reach the timeline only when Sync Email as
   * Salesforce Activity saves them as Tasks and Email Messages; that setting
   * can't be read from here, so setup asks the admin to check it.
   * @return What was found about Activity Capture licences.
   */
  // Setup only: whether the org has Activity Capture licences in use.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static ActivityCapture activityCapture() {
    if (testActivityCapture != null) {
      return testActivityCapture;
    }
    ActivityCapture found = new ActivityCapture();
    try {
      for (PermissionSetLicense l : [
        SELECT MasterLabel, UsedLicenses
        FROM PermissionSetLicense
        WHERE (MasterLabel LIKE '%Activity Capture%' OR DeveloperName LIKE '%ActivityCapture%') AND UsedLicenses > 0
      ]) {
        found.users += l.UsedLicenses;
        found.licences.add(l.MasterLabel);
      }
    } catch (Exception e) {
      // Licences this admin can't read: nothing to warn about.
      System.debug(LoggingLevel.FINE, 'Time Drive: licences not read. ' + e.getMessage());
    }
    found.inUse = found.users > 0;
    return found;
  }

  // A variant beats another by needing more of the settings used; with as
  // many, by needing the one first in FEATURE_PRECEDENCE.
  private static Boolean outranks(Time_Drive_Source__mdt a, Time_Drive_Source__mdt b) {
    Integer sizeA = needs(a).size();
    Integer sizeB = needs(b).size();
    if (sizeA != sizeB) {
      return sizeA > sizeB;
    }
    return precedence(a) < precedence(b);
  }

  private static Integer precedence(Time_Drive_Source__mdt s) {
    Integer best = FEATURE_PRECEDENCE.size();
    for (String need : needs(s)) {
      Integer at = FEATURE_PRECEDENCE.indexOf(need);
      if (at >= 0 && at < best) {
        best = at;
      }
    }
    return best;
  }

  private static String pageLabel(Time_Drive_Source__mdt s) {
    String page = String.isBlank(s.Parent_Object__c) ? 'Contact' : s.Parent_Object__c;
    return page == TimeDriveController.PERSON_ACCOUNT ? 'Person Account' : page;
  }

  private static List<Time_Drive_Source__mdt> fittedSources() {
    List<SourceOrder> ordered = new List<SourceOrder>();
    for (Time_Drive_Source__mdt s : TimeDriveConfig.templates().values()) {
      if (s.getPopulatedFieldsAsMap().get('Org_Fit__c') == true && s.Removed__c != true) {
        ordered.add(new SourceOrder(s));
      }
    }
    ordered.sort();
    List<Time_Drive_Source__mdt> out = new List<Time_Drive_Source__mdt>();
    for (SourceOrder o : ordered) {
      out.add(o.source);
    }
    return out;
  }

  private static List<String> needs(Time_Drive_Source__mdt s) {
    List<String> out = new List<String>();
    Object raw = s.getPopulatedFieldsAsMap().get('Requires__c');
    for (String part : raw == null ? new List<String>() : String.valueOf(raw).split(';')) {
      if (String.isNotBlank(part)) {
        out.add(part.trim());
      }
    }
    return out;
  }

  // Record page, then sequence, then label.
  private class SourceOrder implements Comparable {
    Time_Drive_Source__mdt source;
    SourceOrder(Time_Drive_Source__mdt source) {
      this.source = source;
    }
    Integer page() {
      Integer i = PAGE_ORDER.indexOf(String.isBlank(source.Parent_Object__c) ? 'Contact' : source.Parent_Object__c);
      return i < 0 ? PAGE_ORDER.size() : i;
    }
    /**
     * Orders by record page, then sequence, then label.
     * @param other The source to compare with.
     * @return A negative number, zero or a positive number.
     */
    public Integer compareTo(Object other) {
      SourceOrder that = (SourceOrder) other;
      if (page() != that.page()) {
        return page() - that.page();
      }
      Decimal mine = source.Sequence__c == null ? 0 : source.Sequence__c;
      Decimal theirs = that.source.Sequence__c == null ? 0 : that.source.Sequence__c;
      if (mine != theirs) {
        return mine < theirs ? -1 : 1;
      }
      return source.Label.compareTo(that.source.Label);
    }
  }

  /**
   * Switches a source on or off.
   * @param developerName The source's developer name.
   * @param active Whether the source is switched on.
   * @return A ticket naming the source.
   */
  @AuraEnabled
  public static SaveTicket setActive(String developerName, Boolean active) {
    requireSetupAccess();
    requireSource(developerName);
    write(
      new List<Time_Drive_Record__c>{ new Time_Drive_Record__c(Key__c = developerName, Active__c = active == true) }
    );
    return new SaveTicket(developerName);
  }

  /**
   * Sets the lenses a source is in (the timeline's views, by key): it shows
   * when any of them is chosen. None: it is in no lens, and shows only under All.
   * @param developerName The source's developer name.
   * @param lenses The keys of the lenses it is in.
   * @return A ticket naming the source.
   */
  @AuraEnabled
  public static SaveTicket setLenses(String developerName, List<String> lenses) {
    requireSetupAccess();
    requireSource(developerName);
    List<String> kept = new List<String>();
    for (String lens : lenses == null ? new List<String>() : lenses) {
      String key = String.isBlank(lens) ? null : lens.trim();
      if (key == null || kept.contains(key)) {
        continue;
      }
      Boolean known = false;
      for (Time_Drive_View__mdt v : TimeDriveConfig.views()) {
        known = known || v.DeveloperName == key;
      }
      if (!known) {
        throw failure('There is no lens called ' + key + '.');
      }
      kept.add(key);
    }
    Time_Drive_Record__c row = new Time_Drive_Record__c(Key__c = developerName);
    row.Lenses__c = kept.isEmpty() ? null : String.join(kept, ';');
    // Its single Category is superseded by the lenses.
    row.Category__c = null;
    write(new List<Time_Drive_Record__c>{ row });
    return new SaveTicket(developerName);
  }

  /**
   * Removes a source, for good.
   * @param developerName The source's developer name.
   * @return A ticket naming the source.
   */
  @AuraEnabled
  public static SaveTicket remove(String developerName) {
    requireSetupAccess();
    requireSource(developerName);
    try {
      delete as user [SELECT Id FROM Time_Drive_Record__c WHERE Key__c = :developerName];
    } catch (DmlException e) {
      throw failure('The source couldn\'t be removed. ' + e.getDmlMessage(0));
    }
    TimeDriveConfig.reset();
    return new SaveTicket(developerName);
  }

  private static void requireSource(String developerName) {
    if (TimeDriveConfig.source(developerName) == null) {
      throw failure('That source no longer exists.');
    }
  }

  /**
   * Saves the records (new or existing, by Key), as the admin, and forgets what was read.
   * @param rows The records to save.
   */
  private static void write(List<Time_Drive_Record__c> rows) {
    try {
      Database.upsert(rows, Time_Drive_Record__c.Key__c, true, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      throw failure('The source couldn\'t be saved. ' + e.getDmlMessage(0));
    }
    TimeDriveConfig.reset();
  }

  /**
   * The Time Drive for a record page, made when there is none yet.
   * @param parentObject The record page's object; Contact when blank.
   * @return The id of the Time Drive.
   */
  // Setup only (every caller has passed requireSetupAccess()).
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Id driveFor(String parentObject) {
    String page = String.isBlank(parentObject) ? 'Contact' : parentObject;
    List<Time_Drive__c> found = [SELECT Id FROM Time_Drive__c WHERE Parent_Object__c = :page LIMIT 1];
    if (!found.isEmpty()) {
      return found[0].Id;
    }
    Time_Drive__c made = new Time_Drive__c(Name = page + ' Time Drive', Parent_Object__c = page, Active__c = true);
    insert as user made;
    return made.Id;
  }

  private static void validate(SourceDraft d) {
    List<String> missing = new List<String>();
    if (String.isBlank(d.label)) {
      missing.add('a name');
    }
    if (d.kind == TimeDriveContext.KIND_APEX) {
      if (String.isBlank(d.providerClass)) {
        missing.add('an Apex class');
      }
    } else {
      if (String.isBlank(d.objectName)) {
        missing.add('an object');
      }
      if (String.isBlank(d.dateField)) {
        missing.add('a date');
      }
      if (
        d.kind == TimeDriveContext.KIND_SALESFORCE &&
        String.isBlank(d.parentField) &&
        String.isBlank(d.junctionObject)
      ) {
        missing.add('how it links to the record');
      }
    }
    if (!missing.isEmpty()) {
      throw failure('Before saving, choose ' + String.join(missing, ', ') + '.');
    }
  }

  @TestVisible
  private static String uniqueName(String label) {
    String base = String.valueOf(label).replaceAll('[^A-Za-z0-9]+', '_').replaceAll('^_+|_+$', '');
    if (String.isBlank(base) || !base.substring(0, 1).isAlpha()) {
      base = 'Source_' + base;
    }
    base = base.left(36).replaceAll('_+$', '');
    Map<String, Time_Drive_Source__mdt> all = TimeDriveConfig.allSources();
    String name = base;
    Integer n = 2;
    while (all.containsKey(name)) {
      name = base + '_' + n++;
    }
    return name;
  }

  /**
   * The draft as a Time Drive Record: a new one is placed under its record page's Time Drive.
   * @param d The draft source.
   * @return The record to save.
   */
  @TestVisible
  private static Time_Drive_Record__c driveRecord(SourceDraft d) {
    Time_Drive_Record__c r = new Time_Drive_Record__c(
      Key__c = d.developerName,
      Name = d.label.trim().left(80),
      Active__c = d.active == true,
      Kind__c = d.kind,
      Object_Name__c = d.objectName,
      Parent_Field__c = d.parentField,
      Junction_Object__c = d.junctionObject,
      Junction_Parent_Field__c = d.junctionParentField,
      Junction_Record_Field__c = d.junctionRecordField,
      Individual_Field__c = d.individualField,
      Data_Space__c = String.isBlank(d.dataSpace) ? null : d.dataSpace,
      Provider_Class__c = d.providerClass,
      Date_Field__c = d.dateField,
      Filter__c = d.filterText(),
      Max_Records__c = d.maxRecords,
      History_Months__c = d.historyMonths,
      Event_Type__c = String.isBlank(d.eventType) ? d.developerName.toLowerCase().left(80) : d.eventType,
      Event_Label__c = d.eventLabel,
      Title__c = oneField(d.title),
      Subtitle__c = oneField(d.subtitle),
      Icon__c = d.icon,
      Icon_Colour__c = d.iconColour,
      Record_Id_Field__c = d.recordIdFieldOrRelated(),
      Sequence__c = d.sequence == null ? 50 : d.sequence
    );
    // The lenses chosen in the wizard (or, from an older page, its one category).
    List<String> chosen = d.lenses != null
      ? d.lenses
      : (String.isBlank(d.category) ? new List<String>() : new List<String>{ d.category });
    List<String> kept = new List<String>();
    for (String lens : chosen) {
      if (String.isNotBlank(lens) && !kept.contains(lens.trim())) {
        kept.add(lens.trim());
      }
    }
    r.Lenses__c = kept.isEmpty() ? null : String.join(kept, ';');
    r.Category__c = null;
    Integer n = 0;
    for (DetailDraft detail : d.details == null ? new List<DetailDraft>() : d.details) {
      if (String.isNotBlank(detail.field) && n < MAX_DETAILS) {
        n++;
        r.put('Detail_' + n + '_Field__c', detail.field);
        r.put('Detail_' + n + '_Label__c', String.isBlank(detail.label) ? null : detail.label.left(80));
        r.put('Detail_' + n + '_Format__c', String.isBlank(detail.format) ? 'Text' : detail.format);
      }
    }
    // The record is upserted: a detail or highlight taken out must be cleared, or its old field stays.
    for (Integer i = n + 1; i <= MAX_DETAILS; i++) {
      r.put('Detail_' + i + '_Field__c', null);
      r.put('Detail_' + i + '_Label__c', null);
      r.put('Detail_' + i + '_Format__c', null);
    }
    r.Highlight_Field__c = null;
    r.Highlight_Values__c = null;
    r.Highlight_Icon__c = null;
    r.Highlight_Colour__c = null;
    for (HighlightDraft h : d.highlights == null ? new List<HighlightDraft>() : d.highlights) {
      if (String.isNotBlank(h.field)) {
        r.Highlight_Field__c = h.field;
        r.Highlight_Values__c = 'true';
        r.Highlight_Icon__c = h.icon;
        r.Highlight_Colour__c = h.colour;
        break;
      }
    }
    if ([SELECT COUNT() FROM Time_Drive_Record__c WHERE Key__c = :d.developerName] == 0) {
      r.Time_Drive__c = driveFor(d.parentObject);
    }
    return r;
  }

  /**
   * A title or subtitle as one field ({Subject}): its first, or none (the title then shows the source's name).
   * @param text The title or subtitle as drafted.
   * @return The first {Field} in it, or null.
   */
  @TestVisible
  private static String oneField(String text) {
    Matcher m = Pattern.compile('\\{[^}]+\\}').matcher(text == null ? '' : text);
    return m.find() ? m.group() : null;
  }

  /** Sources are records only admins write: it needs the Setup permission set's access, or Customize Application. */
  private static void requireSetupAccess() {
    if (!Schema.sObjectType.Time_Drive_Record__c.isCreateable() && !userCanCustomize()) {
      throw failure('Only admins (with the Time Drive Setup permission set) can manage timeline sources.');
    }
  }

  // Only the running user's own permission set assignments are read.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Boolean userCanCustomize() {
    List<PermissionSetAssignment> grants = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.PermissionsCustomizeApplication = TRUE
      LIMIT 1
    ];
    return !grants.isEmpty();
  }

  private static AuraHandledException failure(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }

  // ---- shapes the page reads and sends ------------------------------------

  /** A save that's done: the source (or Views) it saved. */
  public class SaveTicket {
    @AuraEnabled
    public String developerName;

    /**
     * Builds the ticket.
     * @param developerName The source's developer name.
     */
    public SaveTicket(String developerName) {
      this.developerName = developerName;
    }
  }

  /** A choice for the wizard: a value, its label and a line of detail. */
  public class Option implements Comparable {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String detail;
    // An object's plural label ("Customer Orders"), for the wizard's sentence.
    @AuraEnabled
    public String pluralLabel;

    /**
     * Builds the option.
     * @param value The value the wizard sends back.
     * @param label The label shown.
     * @param detail A line of detail, or null.
     */
    public Option(String value, String label, String detail) {
      this.value = value;
      this.label = label;
      this.detail = detail;
    }

    /**
     * Sets the plural label.
     * @param pluralLabel The plural label.
     * @return This option, so calls can be chained.
     */
    public Option plural(String pluralLabel) {
      this.pluralLabel = pluralLabel;
      return this;
    }

    /**
     * Orders options by label, ignoring case.
     * @param other The option to compare with.
     * @return A negative number, zero or a positive number.
     */
    public Integer compareTo(Object other) {
      return label.toLowerCase().compareTo(((Option) other).label.toLowerCase());
    }
  }

  /** How an object's records link to the page's record. */
  public class Link {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String parentField;
    @AuraEnabled
    public String junctionObject;
    @AuraEnabled
    public String junctionParentField;
    @AuraEnabled
    public String junctionRecordField;
    // In a few words, for the object list: "Linked by Customer".
    @AuraEnabled
    public String how;
    // For the Link step's diagram (getLinks only): the objects, their name
    // fields, and the lookups that join them.
    @AuraEnabled
    public String parentLabel;
    @AuraEnabled
    public String parentNameLabel;
    @AuraEnabled
    public String objectLabel;
    @AuraEnabled
    public String objectNameLabel;
    @AuraEnabled
    public String fieldLabel;
    @AuraEnabled
    public Boolean masterDetail = false;
    @AuraEnabled
    public String junctionLabel;
    @AuraEnabled
    public String junctionNameLabel;
    @AuraEnabled
    public String recordFieldLabel;
    @AuraEnabled
    public Boolean recordMasterDetail = false;
    // A word on what the link finds, when it needs one.
    @AuraEnabled
    public String note;
    // How it links, when the wizard's own words won't do (person accounts).
    @AuraEnabled
    public String kindText;
    // A task's or event's relations: the link Guided setup's "every contact" uses.
    @AuraEnabled
    public Boolean everyContact = false;

    /**
     * A link by a lookup on the object itself.
     * @param parentField The lookup on the object to the page's record.
     * @param label The sentence saying what the link finds.
     */
    public Link(String parentField, String label) {
      this.key = parentField;
      this.label = label;
      this.parentField = parentField;
    }

    /**
     * A link through a junction object that has lookups to both.
     * @param junctionObject The junction object.
     * @param junctionParentField The junction's lookup to the page's record.
     * @param junctionRecordField The junction's lookup to the linked object.
     * @param label The sentence saying what the link finds.
     */
    public Link(String junctionObject, String junctionParentField, String junctionRecordField, String label) {
      this.key = junctionObject + '.' + junctionRecordField;
      this.label = label;
      this.junctionObject = junctionObject;
      this.junctionParentField = junctionParentField;
      this.junctionRecordField = junctionRecordField;
    }
  }

  /** A source as the home list shows it. */
  public class SourceSummary implements Comparable {
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String parentObject;
    // standard, custom, dmo or apex: what the page groups by.
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Boolean active;
    @AuraEnabled
    public String objectName;
    @AuraEnabled
    public String objectLabel;
    @AuraEnabled
    public String category;
    // Every lens it is in (category is the first).
    @AuraEnabled
    public List<String> lenses = new List<String>();
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String iconColour;
    @AuraEnabled
    public String eventType;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public Decimal sequence;
    // What the legend calls its items: as set (blank, $Label.Name or
    // words), and as it reads in the viewer's language.
    @AuraEnabled
    public String eventLabel;
    @AuraEnabled
    public String legendName;
    // Its filter as it is kept (Status = 'Closed'), or null for every record.
    @AuraEnabled
    public String filter;

    /**
     * Builds the summary from a source record.
     * @param s The source.
     */
    public SourceSummary(Time_Drive_Source__mdt s) {
      developerName = s.DeveloperName;
      label = s.Label;
      kind = new TimeDriveContext(null, null, null, s, null, null).kind();
      parentObject = String.isBlank(s.Parent_Object__c) ? 'Contact' : s.Parent_Object__c;
      type = kind == TimeDriveContext.KIND_APEX
        ? 'apex'
        : kind == TimeDriveContext.KIND_DATA_360
            ? 'dmo'
            : (String.isNotBlank(s.Object_Name__c) && s.Object_Name__c.endsWithIgnoreCase('__c')
                ? 'custom'
                : 'standard');
      active = s.Active__c;
      objectName = s.Object_Name__c;
      objectLabel = labelOf(s.Object_Name__c);
      lenses = TimeDriveConfig.lensesOf(s);
      category = lenses.isEmpty() ? null : lenses[0];
      icon = s.Icon__c;
      iconColour = s.Icon_Colour__c;
      eventType = s.Event_Type__c;
      eventLabel = s.Event_Label__c;
      legendName = TimeDriveConfig.legendLabel(s);
      sequence = s.Sequence__c;
      summary = describeSource(s, kind, objectLabel);
      filter = String.isBlank(s.Filter__c) ? null : s.Filter__c;
    }

    /**
     * Orders by sequence, then label.
     * @param other The summary to compare with.
     * @return A negative number, zero or a positive number.
     */
    public Integer compareTo(Object other) {
      Decimal mine = sequence == null ? 0 : sequence;
      Decimal theirs = ((SourceSummary) other).sequence == null ? 0 : ((SourceSummary) other).sequence;
      return mine == theirs ? label.compareTo(((SourceSummary) other).label) : (mine < theirs ? -1 : 1);
    }
  }

  // "Invoice__c records whose Customer is this Contact, dated by Invoice Date."
  private static String describeSource(Time_Drive_Source__mdt s, String kind, String objectLabel) {
    String parent = String.isBlank(s.Parent_Object__c) ? 'record' : labelOf(s.Parent_Object__c);
    if (kind == TimeDriveContext.KIND_APEX) {
      return 'Events from the Apex class ' + s.Provider_Class__c + '.';
    }
    String text = objectLabel + ' records';
    if (kind == TimeDriveContext.KIND_DATA_360) {
      text += ' for this ' + parent + '\'s unified profile';
    } else if (String.isNotBlank(s.Junction_Object__c)) {
      text += ' this ' + parent + ' is on, through ' + labelOf(s.Junction_Object__c);
    } else {
      text += ' whose ' + fieldLabel(s.Object_Name__c, s.Parent_Field__c) + ' is this ' + parent;
    }
    text += ', dated by ' + fieldLabel(s.Object_Name__c, s.Date_Field__c);
    if (String.isNotBlank(s.Filter__c)) {
      text += ', only where ' + s.Filter__c;
    }
    return text + '.';
  }

  private static String labelOf(String objectName) {
    Schema.SObjectType t = TimeDriveConfig.sObjectType(objectName);
    return t == null ? objectName : t.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
  }

  private static String fieldLabel(String objectName, String field) {
    Schema.SObjectType t = TimeDriveConfig.sObjectType(objectName);
    Schema.SObjectField f = t == null || String.isBlank(field)
      ? null
      : t.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().get(field.toLowerCase());
    return f == null ? field : f.getDescribe().getLabel();
  }

  /** A detail field as the wizard edits it. */
  public class DetailDraft {
    /** The detail field record's developer name. */
    @AuraEnabled
    public String developerName { get; set; }
    /** The field to show. */
    @AuraEnabled
    public String field { get; set; }
    /** The label to show, or blank to use the field's own. */
    @AuraEnabled
    public String label { get; set; }
    /** How the value is shown (Text by default). */
    @AuraEnabled
    public String format { get; set; }

    // Needed with the constructor below: the browser's JSON is deserialised into an empty draft first.
    /** Makes an empty draft. */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public DetailDraft() {
    }

    /**
     * Builds the draft from a stored detail field.
     * @param d The detail field record.
     */
    public DetailDraft(Time_Drive_Detail_Field__mdt d) {
      developerName = d.DeveloperName;
      field = d.Field__c;
      // Label = the field means none of its own (the field's label is used).
      label = d.Label == String.valueOf(d.Field__c).left(40) ? null : d.Label;
      format = d.Format__c;
    }
  }

  /** One highlight as the wizard edits it. */
  public class HighlightDraft {
    /** The highlight record's developer name. */
    @AuraEnabled
    public String developerName { get; set; }
    /** The checkbox field to highlight on. */
    @AuraEnabled
    public String field { get; set; }
    /** The icon to show when it is checked. */
    @AuraEnabled
    public String icon { get; set; }
    /** The colour of that icon. */
    @AuraEnabled
    public String colour { get; set; }

    // Needed with the constructor below: the browser's JSON is deserialised into an empty draft first.
    /** Makes an empty draft. */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public HighlightDraft() {
    }

    /**
     * Builds the draft from a stored highlight.
     * @param h The highlight record.
     */
    public HighlightDraft(Time_Drive_Highlight__mdt h) {
      developerName = h.DeveloperName;
      field = h.Field__c;
      icon = h.Icon__c;
      colour = h.Colour__c;
    }
  }

  /**
   * A source as the wizard edits it. A filter is either simple conditions
   * (field, operator, value: all must hold) or, for one written by hand,
   * the filter text as it is.
   */
  public class SourceDraft {
    /** The source's developer name; blank for a new one. */
    @AuraEnabled
    public String developerName { get; set; }
    /** The source's name. */
    @AuraEnabled
    public String label { get; set; }
    /** Where the events come from: Salesforce records, Data 360 or an Apex class. */
    @AuraEnabled
    public String kind { get; set; }
    /** Whether the source is switched on. */
    @AuraEnabled
    public Boolean active { get; set; }
    /** The record page's object it belongs to. */
    @AuraEnabled
    public String parentObject { get; set; }
    /** The object whose records are plotted. */
    @AuraEnabled
    public String objectName { get; set; }
    /** The lookup on the object to the page's record. */
    @AuraEnabled
    public String parentField { get; set; }
    /** The junction object under the page's record, when the link goes through one. */
    @AuraEnabled
    public String junctionObject { get; set; }
    /** The junction's lookup to the page's record. */
    @AuraEnabled
    public String junctionParentField { get; set; }
    /** The junction's lookup to the plotted object. */
    @AuraEnabled
    public String junctionRecordField { get; set; }
    /** The field linking a Data 360 record to the unified profile. */
    @AuraEnabled
    public String individualField { get; set; }
    /** Data 360: the data space its DMO is in (blank: the default). */
    @AuraEnabled
    public String dataSpace { get; set; }
    /** The field that dates each event. */
    @AuraEnabled
    public String dateField { get; set; }
    /** The simple conditions of the filter: all of them must hold, or any (see match). */
    @AuraEnabled
    public List<Condition> conditions { get; set; }
    /** all (AND) or any (OR): how the conditions combine. Blank is all. */
    @AuraEnabled
    public String match { get; set; }
    /** The filter text as written by hand, when it is not built from conditions. */
    @AuraEnabled
    public String filter { get; set; }
    /** The most records to read. */
    @AuraEnabled
    public Decimal maxRecords { get; set; }
    /** How many months back to read. */
    @AuraEnabled
    public Decimal historyMonths { get; set; }
    /** Whether the source is marked as removed. */
    @AuraEnabled
    public Boolean removed { get; set; }
    /** The event type key. */
    @AuraEnabled
    public String eventType { get; set; }
    /** What the legend calls the source's items. */
    @AuraEnabled
    public String eventLabel { get; set; }
    /** The first lens it is in, kept for older pages. */
    @AuraEnabled
    public String category { get; set; }
    /** Every lens it is in (category is the first). */
    @AuraEnabled
    public List<String> lenses { get; set; }
    /** The title of each event. */
    @AuraEnabled
    public String title { get; set; }
    /** The subtitle of each event. */
    @AuraEnabled
    public String subtitle { get; set; }
    /** The icon name. */
    @AuraEnabled
    public String icon { get; set; }
    /** The icon colour. */
    @AuraEnabled
    public String iconColour { get; set; }
    /** Where a click goes (blank: the item's own record). */
    @AuraEnabled
    public String recordIdField { get; set; }
    /** Whether the source is fitted to the org; kept as shipped through edits and switches. */
    @AuraEnabled
    public Boolean orgFit { get; set; }
    /** The org settings an org-fitted source needs, separated by semicolons. */
    @AuraEnabled
    public String requires { get; set; }
    /** The group of variants an org-fitted source belongs to. */
    @AuraEnabled
    public String variantGroup { get; set; }
    /** The Apex class that supplies the events. */
    @AuraEnabled
    public String providerClass { get; set; }
    /** The source's place in the legend. */
    @AuraEnabled
    public Decimal sequence { get; set; }
    /** The detail fields. */
    @AuraEnabled
    public List<DetailDraft> details { get; set; }
    /** The highlights: one icon for a checkbox that is checked (TimeDriveHighlights). */
    @AuraEnabled
    public List<HighlightDraft> highlights { get; set; }
    /**
     * The record page's sources in legend order, this one as __this__ (sent from the wizard's
     * Fine-tune step; blank leaves the order be).
     */
    @AuraEnabled
    public List<String> legendOrder { get; set; }

    /** Makes an empty draft, switched on, with no details, highlights or conditions. */
    public SourceDraft() {
      details = new List<DetailDraft>();
      highlights = new List<HighlightDraft>();
      conditions = new List<Condition>();
      active = true;
    }

    /**
     * Builds the draft from a source record.
     * @param s The source.
     */
    public SourceDraft(Time_Drive_Source__mdt s) {
      this();
      developerName = s.DeveloperName;
      label = s.Label;
      kind = new TimeDriveContext(null, null, null, s, null, null).kind();
      active = s.Active__c;
      parentObject = s.Parent_Object__c;
      objectName = s.Object_Name__c;
      parentField = s.Parent_Field__c;
      junctionObject = s.Junction_Object__c;
      junctionParentField = s.Junction_Parent_Field__c;
      junctionRecordField = s.Junction_Record_Field__c;
      individualField = s.Individual_Field__c;
      dataSpace = s.Data_Space__c;
      dateField = s.Date_Field__c;
      filter = s.Filter__c;
      // A filter the builder made opens as its conditions; any other stays text.
      FilterParts parsed = filterParts(s.Filter__c);
      if (parsed != null && !parsed.conditions.isEmpty()) {
        conditions = parsed.conditions;
        match = parsed.match;
        filter = null;
      }
      maxRecords = s.Max_Records__c;
      historyMonths = s.History_Months__c;
      removed = s.Removed__c;
      eventType = s.Event_Type__c;
      eventLabel = s.Event_Label__c;
      List<String> inLenses = TimeDriveConfig.lensesOf(s);
      category = inLenses.isEmpty() ? null : inLenses[0];
      lenses = inLenses;
      title = s.Title__c;
      subtitle = s.Subtitle__c;
      icon = s.Icon__c;
      iconColour = s.Icon_Colour__c;
      recordIdField = s.Record_Id_Field__c;
      Map<String, Object> populated = s.getPopulatedFieldsAsMap();
      orgFit = populated.get('Org_Fit__c') == true;
      requires = (String) populated.get('Requires__c');
      variantGroup = (String) populated.get('Variant_Group__c');
      providerClass = s.Provider_Class__c;
      sequence = s.Sequence__c;
    }

    // A relation object whose date is its record's (TaskRelation, Task.ActivityDate)
    // opens that record, its task: the lookup to it, unless the source says otherwise.
    private String relatedRecordField() {
      // A file always opens its document, whatever it is dated by.
      if ('ContentDocumentLink'.equalsIgnoreCase(objectName)) {
        return 'ContentDocumentId';
      }
      String record = RELATION_RECORDS.get(objectName);
      return record != null &&
        String.isNotBlank(dateField) &&
        dateField.startsWith(record + '.')
        ? record + 'Id'
        : null;
    }

    /**
     * The field whose record a click opens: the one set, else the related record's.
     * @return The field name, or null.
     */
    public String recordIdFieldOrRelated() {
      return String.isBlank(recordIdField) ? relatedRecordField() : recordIdField;
    }

    /**
     * The conditions as a SOQL filter (values bound as literals, quoted and escaped by type), or
     * the filter text written by hand.
     * @return The filter, or null when there is none.
     */
    public String filterText() {
      if (conditions == null || conditions.isEmpty()) {
        return String.isBlank(filter) ? null : filter;
      }
      List<String> parts = new List<String>();
      for (Condition c : conditions) {
        String part = c.soql();
        if (part != null) {
          parts.add(part);
        }
      }
      return parts.isEmpty() ? null : String.join(parts, match == MATCH_ANY ? ' OR ' : ' AND ');
    }

    /**
     * The draft as a source record held in memory, as the timeline reads it (for the preview).
     * @return The source record.
     */
    public Time_Drive_Source__mdt toRecord() {
      return new Time_Drive_Source__mdt(
        DeveloperName = String.isBlank(developerName) ? 'Preview' : developerName,
        Label = String.isBlank(label) ? 'Preview' : label,
        Active__c = true,
        Kind__c = kind,
        Source_Mode__c = 'Always',
        Parent_Object__c = parentObject,
        Object_Name__c = objectName,
        Parent_Field__c = parentField,
        Junction_Object__c = junctionObject,
        Junction_Parent_Field__c = junctionParentField,
        Junction_Record_Field__c = junctionRecordField,
        Individual_Field__c = individualField,
        Data_Space__c = dataSpace,
        Date_Field__c = dateField,
        Filter__c = filterText(),
        Max_Records__c = maxRecords,
        History_Months__c = historyMonths,
        Event_Type__c = String.isBlank(eventType) ? 'preview' : eventType,
        Event_Label__c = eventLabel,
        Category__c = category,
        Title__c = title,
        Subtitle__c = subtitle,
        Icon__c = icon,
        Icon_Colour__c = iconColour,
        Record_Id_Field__c = recordIdFieldOrRelated(),
        Provider_Class__c = providerClass
      );
    }

    /**
     * The highlights as records, for the preview (at most the two a source keeps).
     * @return The highlight records.
     */
    public List<Time_Drive_Highlight__mdt> highlightRecords() {
      List<Time_Drive_Highlight__mdt> out = new List<Time_Drive_Highlight__mdt>();
      for (HighlightDraft h : highlights == null ? new List<HighlightDraft>() : highlights) {
        if (String.isNotBlank(h.field) && out.size() < TimeDriveHighlights.MAX_RULES) {
          out.add(
            new Time_Drive_Highlight__mdt(
              Label = h.field,
              Field__c = h.field,
              Values__c = 'true',
              Icon__c = h.icon,
              Colour__c = h.colour,
              Sequence__c = (out.size() + 1) * 10
            )
          );
        }
      }
      return out;
    }

    /**
     * The detail fields as records, for the preview (at most four).
     * @return The detail field records.
     */
    public List<Time_Drive_Detail_Field__mdt> detailRecords() {
      List<Time_Drive_Detail_Field__mdt> out = new List<Time_Drive_Detail_Field__mdt>();
      Integer i = 0;
      for (DetailDraft d : details == null ? new List<DetailDraft>() : details) {
        // At most four fields besides the title and subtitle.
        if (String.isNotBlank(d.field) && i < MAX_DETAILS) {
          out.add(
            new Time_Drive_Detail_Field__mdt(
              Label = String.isBlank(d.label) ? d.field : d.label,
              Field__c = d.field,
              Format__c = String.isBlank(d.format) ? 'Text' : d.format,
              Sequence__c = ++i * 10
            )
          );
        }
      }
      return out;
    }
  }

  /**
   * The conditions a filter was built from (Condition.soql() joined by AND,
   * or by OR), or null when it is anything else (AND and OR mixed, NOT,
   * a subquery ...): such a filter is kept as the text it is.
   * @param filter The filter text.
   * @return The conditions, or null when the filter is not a plain AND or OR of them.
   */
  @TestVisible
  private static List<Condition> conditionsOf(String filter) {
    FilterParts parts = filterParts(filter);
    return parts == null ? null : parts.conditions;
  }

  /** A filter read back as its conditions and how they combine. */
  @TestVisible
  private class FilterParts {
    @TestVisible
    List<Condition> conditions = new List<Condition>();
    @TestVisible
    String match = MATCH_ALL;
  }

  // The filter split at its AND or OR (outside quotes and brackets), each
  // part a condition. Brackets around the whole filter, or a part, are dropped.
  @TestVisible
  private static FilterParts filterParts(String filter) {
    if (String.isBlank(filter)) {
      return null;
    }
    String text = withoutOuterBrackets(filter.trim());
    List<String> parts = new List<String>();
    Set<String> joins = new Set<String>();
    String current = '';
    Boolean quoted = false;
    Integer depth = 0;
    Integer i = 0;
    while (i < text.length()) {
      String ch = text.substring(i, i + 1);
      if (quoted) {
        current += ch;
        if (ch == '\\' && i + 1 < text.length()) {
          current += text.substring(i + 1, i + 2);
          i++;
        } else if (ch == '\'') {
          quoted = false;
        }
        i++;
        continue;
      }
      String joiner = depth > 0 ? null : joinAt(text, i);
      if (joiner != null) {
        joins.add(joiner.trim());
        parts.add(current);
        current = '';
        i += joiner.length();
        continue;
      }
      if (ch == '\'') {
        quoted = true;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      current += ch;
      i++;
    }
    if (quoted || depth != 0 || joins.size() > 1) {
      return null;
    }
    parts.add(current);
    FilterParts out = new FilterParts();
    out.match = joins.contains('OR') ? MATCH_ANY : MATCH_ALL;
    for (String part : parts) {
      // Brackets around one condition are only brackets.
      Condition c = conditionOf(withoutOuterBrackets(part.trim()));
      if (c == null) {
        return null;
      }
      out.conditions.add(c);
    }
    return out;
  }

  // ' AND ' or ' OR ' starting at i, or null.
  private static String joinAt(String text, Integer i) {
    for (String joiner : new List<String>{ ' AND ', ' OR ' }) {
      if (text.substring(i, Math.min(i + joiner.length(), text.length())) == joiner) {
        return joiner;
      }
    }
    return null;
  }

  // "(A OR B)" as "A OR B", when the brackets hold the whole of it.
  private static String withoutOuterBrackets(String text) {
    while (text.startsWith('(') && text.endsWith(')')) {
      Integer depth = 0;
      Boolean quoted = false;
      Boolean wholly = true;
      for (Integer i = 0; i < text.length() - 1; i++) {
        String ch = text.substring(i, i + 1);
        if (quoted) {
          if (ch == '\\') {
            i++;
          } else if (ch == '\'') {
            quoted = false;
          }
        } else if (ch == '\'') {
          quoted = true;
        } else if (ch == '(') {
          depth++;
        } else if (ch == ')' && --depth == 0) {
          wholly = false;
          break;
        }
      }
      if (!wholly) {
        return text;
      }
      text = text.substring(1, text.length() - 1).trim();
    }
    return text;
  }

  private static Condition conditionOf(String part) {
    Matcher listed = Pattern.compile('^([A-Za-z0-9_.]+) (IN|NOT IN) \\((.+)\\)$').matcher(part);
    if (listed.matches()) {
      List<String> values = quotedList(listed.group(3));
      if (values == null) {
        return null;
      }
      Condition c = condition(listed.group(1), listed.group(2) == 'IN' ? 'oneOf' : 'notOneOf', '', 'text');
      c.values = values;
      return c;
    }
    Matcher blank = Pattern.compile('^([A-Za-z0-9_.]+) (=|!=) null$').matcher(part);
    if (blank.matches()) {
      return condition(blank.group(1), blank.group(2) == '=' ? 'blank' : 'notBlank', '', 'text');
    }
    Matcher likeMatch = Pattern.compile('^([A-Za-z0-9_.]+) LIKE \'%(.*)%\'$').matcher(part);
    if (likeMatch.matches() && Pattern.matches('(?:[^\'\\\\]|\\\\.)*', likeMatch.group(2))) {
      return condition(likeMatch.group(1), 'contains', unescaped(likeMatch.group(2)), 'text');
    }
    Matcher compare = Pattern.compile('^([A-Za-z0-9_.]+) (=|!=|>|<) (.+)$').matcher(part);
    if (!compare.matches()) {
      return null;
    }
    Map<String, String> ops = new Map<String, String>{
      '=' => 'equals',
      '!=' => 'notEquals',
      '>' => 'greater',
      '<' => 'less'
    };
    String op = ops.get(compare.group(2));
    String literal = compare.group(3);
    if (literal == 'true' || literal == 'false') {
      return condition(compare.group(1), op, literal, 'boolean');
    }
    if (Pattern.matches('-?[0-9]+(\\.[0-9]+)?', literal)) {
      return condition(compare.group(1), op, literal, 'number');
    }
    if (Pattern.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z', literal)) {
      return condition(compare.group(1), op, literal.left(10), 'datetime');
    }
    if (Pattern.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}', literal)) {
      return condition(compare.group(1), op, literal, 'date');
    }
    if (Pattern.matches('\'((?:[^\'\\\\]|\\\\.)*)\'', literal)) {
      return condition(compare.group(1), op, unescaped(literal.substring(1, literal.length() - 1)), 'text');
    }
    return null;
  }

  // 'A', 'B' as A and B; null when any item isn't a quoted text.
  private static List<String> quotedList(String text) {
    List<String> out = new List<String>();
    Matcher item = Pattern.compile('\\s*\'((?:[^\'\\\\]|\\\\.)*)\'\\s*(,|$)').matcher(text);
    Integer at = 0;
    while (at < text.length()) {
      if (!item.find(at) || item.start() != at) {
        return null;
      }
      out.add(unescaped(item.group(1)));
      at = item.end();
    }
    return out.isEmpty() ? null : out;
  }

  private static Condition condition(String field, String operator, String value, String valueType) {
    Condition c = new Condition();
    c.field = field;
    c.operator = operator;
    c.value = value;
    c.valueType = valueType;
    return c;
  }

  // Undoes String.escapeSingleQuotes and the LIKE escapes: a backslash
  // takes the character after it as it is.
  private static String unescaped(String text) {
    String out = '';
    Integer i = 0;
    while (i < text.length()) {
      String ch = text.substring(i, i + 1);
      if (ch == '\\' && i + 1 < text.length()) {
        i++;
        ch = text.substring(i, i + 1);
      }
      out += ch;
      i++;
    }
    return out;
  }

  /** One condition of a simple filter: Status__c equals 'Canceled'. */
  public class Condition {
    /** The field the condition tests, by path. */
    @AuraEnabled
    public String field { get; set; }
    /** equals, notEquals, greater, less, contains, blank, notBlank, oneOf or notOneOf. */
    @AuraEnabled
    public String operator { get; set; }
    /** The value to compare with. */
    @AuraEnabled
    public String value { get; set; }
    /** The values, for oneOf and notOneOf. */
    @AuraEnabled
    public List<String> values { get; set; }
    /** boolean, number, date, datetime or text: how the value is written. */
    @AuraEnabled
    public String valueType { get; set; }

    /**
     * The condition as SOQL text.
     * @return The SOQL text, or null when the condition can't be written.
     */
    public String soql() {
      if (String.isBlank(field) || !Pattern.matches('[A-Za-z0-9_.]+', field)) {
        return null;
      }
      if (operator == 'oneOf' || operator == 'notOneOf') {
        List<String> quoted = new List<String>();
        for (String v : values == null ? new List<String>() : values) {
          if (String.isNotBlank(v)) {
            quoted.add('\'' + String.escapeSingleQuotes(v.trim()) + '\'');
          }
        }
        return quoted.isEmpty()
          ? null
          : field + (operator == 'oneOf' ? ' IN (' : ' NOT IN (') + String.join(quoted, ', ') + ')';
      }
      Map<String, String> ops = new Map<String, String>{
        'equals' => '=',
        'notEquals' => '!=',
        'greater' => '>',
        'less' => '<',
        'contains' => 'LIKE',
        'blank' => '= null',
        'notBlank' => '!= null'
      };
      String op = ops.get(operator);
      if (op == null) {
        return null;
      }
      if (operator == 'blank' || operator == 'notBlank') {
        return field + ' ' + op;
      }
      if (operator == 'contains') {
        String v = value == null ? '' : value.trim();
        return field + ' LIKE \'%' + String.escapeSingleQuotes(v).replace('%', '\\%').replace('_', '\\_') + '%\'';
      }
      return field + ' ' + op + ' ' + literal();
    }

    private String literal() {
      String v = value == null ? '' : value.trim();
      if (valueType == 'boolean') {
        return v.equalsIgnoreCase('true') ? 'true' : 'false';
      }
      if (valueType == 'number' && Pattern.matches('-?[0-9]+(\\.[0-9]+)?', v)) {
        return v;
      }
      if (valueType == 'date' && Pattern.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}', v)) {
        return v;
      }
      // A date for a date/time field: from the start of that day (GMT).
      if (valueType == 'datetime' && Pattern.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}', v)) {
        return v + 'T00:00:00Z';
      }
      return '\'' + String.escapeSingleQuotes(v) + '\'';
    }
  }

  /** A field as the wizard lists it. */
  public class FieldInfo implements Comparable {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Boolean filterable;
    @AuraEnabled
    public List<Option> values = new List<Option>();
    // A lookup: the object it points to and the name to reach through it
    // (Campaign, Account), so the wizard can follow it. Lookups to
    // more than one object (WhoId) aren't followed.
    @AuraEnabled
    public String referenceTo;
    @AuraEnabled
    public String relationshipName;
    // That object's names, for a source named after it (a TaskRelation
    // source reading "Tasks").
    @AuraEnabled
    public String referenceLabel;
    @AuraEnabled
    public String referencePlural;

    /**
     * Builds the entry from a field describe, with its picklist values and the object it points to.
     * @param fd The field's describe.
     */
    public FieldInfo(Schema.DescribeFieldResult fd) {
      name = fd.getName();
      label = fd.getLabel();
      type = String.valueOf(fd.getType()).toLowerCase();
      filterable = fd.isFilterable();
      List<Schema.SObjectType> targets = fd.getReferenceTo();
      if (targets.size() == 1 && String.isNotBlank(fd.getRelationshipName())) {
        Schema.DescribeSObjectResult target = targets[0].getDescribe(SObjectDescribeOptions.DEFERRED);
        referenceTo = target.getName();
        referenceLabel = target.getLabel();
        referencePlural = target.getLabelPlural();
        relationshipName = fd.getRelationshipName();
      }
      if (fd.getType() == Schema.DisplayType.PICKLIST || fd.getType() == Schema.DisplayType.MULTIPICKLIST) {
        for (Schema.PicklistEntry e : fd.getPicklistValues()) {
          if (e.isActive()) {
            values.add(new Option(e.getValue(), e.getLabel(), null));
          }
        }
      }
    }

    /**
     * Orders fields by label, ignoring case.
     * @param other The field to compare with.
     * @return A negative number, zero or a positive number.
     */
    public Integer compareTo(Object other) {
      return label.toLowerCase().compareTo(((FieldInfo) other).label.toLowerCase());
    }
  }

  /** What was found about Einstein Activity Capture licences. */
  public class ActivityCapture {
    @AuraEnabled
    public Boolean inUse = false;
    @AuraEnabled
    public Integer users = 0;
    @AuraEnabled
    public List<String> licences = new List<String>();
  }

  /** How many records a draft would read, in all and over each range. */
  public class Volume {
    @AuraEnabled
    public Integer total;
    @AuraEnabled
    public Boolean more = false;
    @AuraEnabled
    public Integer parents;
    @AuraEnabled
    public List<VolumeRange> ranges = new List<VolumeRange>();
  }

  /** The record count over the months back from today. */
  public class VolumeRange {
    @AuraEnabled
    public Integer months;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public Boolean more = false;
  }

  /** The events a draft would plot, with what went wrong. */
  public class Preview {
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public List<TimeDriveController.EngagementEvent> events = new List<TimeDriveController.EngagementEvent>();
    @AuraEnabled
    public List<String> warnings = new List<String>();
    @AuraEnabled
    public List<TimeDriveController.Problem> problems = new List<TimeDriveController.Problem>();
  }
}
