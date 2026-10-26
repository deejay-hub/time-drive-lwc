/**
 * The Time Trail Setup page: lists the Time Trail Source records in plain
 * words, answers the setup wizard's questions from the org's own schema
 * (objects, how they link to the page's record, their fields), previews a
 * draft source against a real record, and saves sources (new, changed or
 * switched off) through the Metadata API. Saving is asynchronous: the
 * deployment's result arrives as a Time_Shift_Setup_Result__e event.
 */
public with sharing class TimeShiftSetupController {
  private static final String SOURCE_TYPE = 'Time_Shift_Source';
  private static final String DETAIL_TYPE = 'Time_Shift_Detail_Field';
  private static final String HIGHLIGHT_TYPE = 'Time_Shift_Highlight';
  private static final Integer MAX_DETAILS = 4;
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
    'contentdocumentlink',
    'entitysubscription',
    'duplicaterecorditem',
    'flowrecordrelation',
    'processinstance',
    'recordaction'
  };

  // ---- the sources ---------------------------------------------------------

  /** Every source, in sequence, with a sentence saying what it plots. */
  @AuraEnabled
  public static List<SourceSummary> getSources() {
    requireSetupAccess();
    List<Time_Shift_Source__mdt> all = TimeShiftConfig.allSources().values();
    // Sources for a setting the timeline doesn't use stay out of sight
    // until it does (see applyOrgFit).
    Set<String> used = usedFeatures();
    List<SourceSummary> out = new List<SourceSummary>();
    for (Time_Shift_Source__mdt s : all) {
      if (s.Removed__c != true && used.containsAll(needs(s))) {
        out.add(new SourceSummary(s));
      }
    }
    out.sort();
    return out;
  }

  /** One source as the wizard edits it, with its detail fields. */
  @AuraEnabled
  public static SourceDraft getSource(String developerName) {
    requireSetupAccess();
    Time_Shift_Source__mdt s = TimeShiftConfig.source(developerName);
    if (s == null) {
      throw failure('That source no longer exists.');
    }
    SourceDraft d = new SourceDraft(s);
    for (Time_Shift_Detail_Field__mdt f : TimeShiftConfig.storedDetailFields(developerName)) {
      if (String.isNotBlank(f.Field__c)) {
        d.details.add(new DetailDraft(f));
      }
    }
    for (Time_Shift_Highlight__mdt h : TimeShiftConfig.storedHighlights(developerName)) {
      if (String.isNotBlank(h.Field__c)) {
        d.highlights.add(new HighlightDraft(h));
      }
    }
    return d;
  }

  // ---- the wizard's questions ---------------------------------------------

  /**
   * Objects to choose from: 'standard' or 'custom' Salesforce objects whose
   * records link to the parent object's (only those can be plotted), each
   * saying how; or 'dmo' Data 360 data model objects, which link through the
   * unified profile. Labels first.
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
        String name = t.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getName();
        if (name.toLowerCase().endsWith('__dlm')) {
          names.add(name);
        }
      }
      names.addAll(catalogDmoNames(dataSpace));
      Set<String> seen = new Set<String>();
      for (String name : names) {
        Schema.SObjectType t = TimeShiftConfig.sObjectType(name);
        Schema.DescribeSObjectResult d = t?.getDescribe(Schema.SObjectDescribeOptions.DEFERRED);
        if (d != null && d.isQueryable() && seen.add(d.getName().toLowerCase())) {
          out.add(new Option(d.getName(), d.getLabel(), 'For the unified profile').plural(d.getLabelPlural()));
        }
      }
      out.sort();
      return out;
    }
    Map<String, List<Link>> links = linksFor(String.isBlank(parentObject) ? 'Contact' : parentObject);
    Map<String, Schema.SObjectType> types = Schema.getGlobalDescribe();
    for (String name : links.keySet()) {
      Schema.DescribeSObjectResult d = types.get(name.toLowerCase())
        .getDescribe(Schema.SObjectDescribeOptions.DEFERRED);
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
   * Apex classes that can feed the timeline: ones implementing
   * TimeShiftProvider or TimeShiftRowProvider (the built-in Salesforce
   * and Data 360 providers are left out: those kinds need no class).
   */
  @AuraEnabled
  public static List<Option> getApexProviders() {
    requireSetupAccess();
    Set<String> builtIn = new Set<String>{ 'TimeShiftSoqlProvider', 'TimeShiftData360Provider' };
    List<Option> out = new List<Option>();
    for (ApexClass c : [
      SELECT Name
      FROM ApexClass
      WHERE NamespacePrefix = NULL AND Status = 'Active'
      ORDER BY Name
      LIMIT 2000
    ]) {
      if (builtIn.contains(c.Name) || c.Name.endsWithIgnoreCase('Test')) {
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
      Boolean rows = instance instanceof TimeShiftRowProvider;
      Boolean events = instance instanceof TimeShiftProvider;
      if (rows || events) {
        out.add(new Option(c.Name, c.Name, rows ? 'Returns rows to plot' : 'Returns finished events'));
      }
    }
    return out;
  }

  /**
   * A custom label's value in the user's language, for the wizard to show
   * what a legend name like $Label.Timeline_Follow_ups reads as; null when
   * there's no custom label by that name.
   */
  @AuraEnabled(cacheable=true)
  public static String getLabelText(String name) {
    requireSetupAccess();
    return TimeShiftConfig.customLabel(name);
  }

  /** How records of an object link to the page's record (see linkMap). */
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
    'MaintenanceAsset' => 'MaintenancePlan'
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

  /**
   * Every object whose records link to the parent's, and how: by a lookup on
   * the object to the parent (Case.ContactId), or through a junction under
   * the parent with a required lookup to the object, as
   * OpportunityContactRole links Opportunities to a Contact. Junction lookups
   * must each point at one object: polymorphic ones (an attachment's parent)
   * link anything to anything.
   */
  private static Map<String, List<Link>> linkMap(Schema.DescribeSObjectResult parent) {
    Map<String, List<Link>> out = new Map<String, List<Link>>();
    Set<String> seen = new Set<String>();
    for (Schema.ChildRelationship cr : parent.getChildRelationships()) {
      Schema.DescribeFieldResult lookup = cr.getField()?.getDescribe();
      Schema.DescribeSObjectResult child = cr.getChildSObject().getDescribe(Schema.SObjectDescribeOptions.DEFERRED);
      String childName = child.getName();
      // A task's or event's relations: every contact on it (with Shared
      // Activities, the primary one too; for events, invitees as well).
      // RelationId points at several objects, so these are named here.
      if (ACTIVITY_RELATIONS.containsKey(childName) && lookup?.getName() == 'RelationId') {
        String record = ACTIVITY_RELATIONS.get(childName);
        String target = record == 'TaskId' ? 'Task' : 'Event';
        Schema.DescribeSObjectResult targetDescribe = describe(target);
        if (seen.add(childName + '.' + record) && targetDescribe.isQueryable()) {
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
        if (RELATION_RECORDS.containsKey(childName) && child.isQueryable() && seen.add(childName + '.' + lookup.getName() + '.own')) {
          Link own = new Link(
            lookup.getName(),
            child.getLabelPlural() + ' whose ' + lookup.getLabel().removeEnd(' ID') + ' (' + lookup.getName() + ') is this ' + parent.getLabel()
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
      if (
        lookup.isFilterable() &&
        child.isCreateable() &&
        lookup.getReferenceTo().contains(parent.getSObjectType()) &&
        (lookup.getReferenceTo().size() <= 2 || relatedTo)
      ) {
        String field = lookup.getLabel().removeEnd(' ID') + ' (' + lookup.getName() + ')';
        Link direct = new Link(
          lookup.getName(),
          child.getLabelPlural() + ' whose ' + field + ' is this ' + parent.getLabel()
        );
        direct.how = 'Linked by ' + lookup.getLabel().removeEnd(' ID');
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
      for (Schema.SObjectField f : child.fields.getMap().values()) {
        Schema.DescribeFieldResult fd = f.getDescribe();
        if (
          fd.getType() != Schema.DisplayType.REFERENCE ||
          fd.isNillable() ||
          fd.getReferenceTo().size() != 1 ||
          AUDIT_FIELDS.contains(fd.getName()) ||
          fd.getName() == lookup.getName()
        ) {
          continue;
        }
        Schema.DescribeSObjectResult target = fd.getReferenceTo()[0]
          .getDescribe(Schema.SObjectDescribeOptions.DEFERRED);
        String targetName = target.getName();
        if (
          targetName == parent.getName() ||
          SETUP_OBJECTS.contains(targetName) ||
          childName == 'User' ||
          !target.isQueryable() ||
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
      Schema.DescribeSObjectResult parent = pageObject(toParent, parentObject).getDescribe();
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
      String name = t.getDescribe().getName();
      if (
        name == parentObject ||
        (parentObject == TimeShiftController.PERSON_ACCOUNT && (name == 'Account' || name == 'Contact'))
      ) {
        return t;
      }
    }
    return lookup.getReferenceTo()[0];
  }

  // The field that names an object's records: Name, Subject, Case Number.
  private static String nameLabel(Schema.DescribeSObjectResult d) {
    for (Schema.SObjectField f : d.fields.getMap().values()) {
      Schema.DescribeFieldResult fd = f.getDescribe();
      if (fd.isNameField()) {
        return fd.getLabel();
      }
    }
    return 'Name';
  }

  /**
   * The links for a record page. A person account is an Account with its
   * own Contact, so its records link either way: by an Account lookup
   * (Case.AccountId) or a Contact one (Task.WhoId, Case.ContactId).
   */
  private static Map<String, List<Link>> linksFor(String parentObject) {
    return withoutUnused(personLinks(parentObject));
  }

  // Links through a setting the timeline doesn't use (see linkNeeds) stay
  // out of sight until it does.
  private static Map<String, List<Link>> withoutUnused(Map<String, List<Link>> links) {
    Set<String> used = usedFeatures();
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
    if (parentObject != TimeShiftController.PERSON_ACCOUNT) {
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

  /** The object's fields the user can read, with what the wizard needs to know. */
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

  // Data 360's DMO names, where force-app-data360's catalog is deployed.
  @TestVisible
  private static List<String> testDmoNames;
  private static List<String> catalogDmoNames(String dataSpace) {
    return testDmoNames != null ? testDmoNames : TimeShiftData360Provider.dmoNames(dataSpace);
  }

  /**
   * The org's active Data 360 data spaces, by name; none without Data 360.
   * Data 360 sources ask for one only when there's more than one.
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
      System.debug(LoggingLevel.WARN, 'Time Trail Setup: no data spaces read. ' + e.getMessage());
    }
    return out;
  }
  @TestVisible
  private static List<Option> testDataSpaces;

  /**
   * Whether the wizard can offer Data 360 sources: the Data 360 add-on
   * (force-app-data360) is installed. When it isn't, the reason is a line
   * for the wizard, which says whether the org lacks Data 360 itself or
   * only the add-on.
   */
  @AuraEnabled(cacheable=true)
  public static Data360Status getData360Status() {
    requireSetupAccess();
    if (testData360Status != null) {
      return testData360Status;
    }
    if (TimeShiftData360Provider.addOnInstalled()) {
      return new Data360Status(true, null);
    }
    // DataSpace exists only in orgs with Data 360.
    return TimeShiftConfig.sObjectType('DataSpace') == null
      ? new Data360Status(false, 'This org doesn\'t have Data 360.')
      : new Data360Status(false, 'Install the Time Trail Data 360 add-on package to use Data 360.');
  }
  @TestVisible
  private static Data360Status testData360Status;

  public class Data360Status {
    @AuraEnabled
    public Boolean ready;
    @AuraEnabled
    public String reason;

    public Data360Status(Boolean ready, String reason) {
      this.ready = ready;
      this.reason = reason;
    }
  }

  private static Schema.DescribeSObjectResult describe(String objectName) {
    Schema.SObjectType t = TimeShiftConfig.sObjectType(objectName);
    if (t == null) {
      throw failure('There is no object called ' + objectName + ' in this org.');
    }
    return t.getDescribe();
  }

  // ---- data volumes --------------------------------------------------------

  private static final List<Integer> RANGES = new List<Integer>{ 3, 6, 12, 24, 60 };
  // Counting stops here: past it, "more than" is all that matters.
  private static final Integer COUNT_CAP = 200000;

  /**
   * How many records a draft would read, over each range the wizard offers
   * (3 months to 5 years, and all time), and how many parents have any, so
   * the page can say roughly how many each has. Counts what the user can
   * see; counts that can't be had (Data 360 without it, a junction) are null.
   */
  @AuraEnabled
  public static Volume getVolumes(String draftJson) {
    requireSetupAccess();
    SourceDraft d = (SourceDraft) JSON.deserialize(draftJson, SourceDraft.class);
    Volume v = new Volume();
    if (String.isBlank(d.objectName) || String.isBlank(d.dateField) || d.kind == TimeShiftContext.KIND_APEX) {
      return v;
    }
    Schema.DescribeSObjectResult target = describe(d.objectName);
    // The date may be reached through a lookup (Task.ActivityDate on TaskRelation).
    Schema.DescribeFieldResult dateInfo = TimeShiftConfig.fieldDescribe(target.getName(), d.dateField);
    if (dateInfo == null) {
      return v;
    }
    TimeShiftConfig.PathField datePath = TimeShiftConfig.pathField(target.getName(), d.dateField);
    Boolean dateOnly = dateInfo.getType() == Schema.DisplayType.DATE;
    String filter = d.filterText();
    String base = 'SELECT COUNT() FROM ' + target.getName();
    // Archived Tasks and Events count too, as the timeline plots them.
    archived = TimeShiftSoqlProvider.ARCHIVED_OBJECTS.contains(datePath?.owner ?? target.getName());
    String reach = datePath?.prefix ?? '';
    String scope = archived
      ? (reach != '' && target.fields.getMap().containsKey('isdeleted') ? 'IsDeleted = false AND ' : '') + reach + 'IsDeleted = false'
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
      d.kind != TimeShiftContext.KIND_DATA_360
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
        System.debug(LoggingLevel.WARN, 'Time Trail Setup: parents not counted. ' + e.getMessage());
      }
    }
    return v;
  }

  // The object being counted is a Task or Event: archived ones count too.
  private static Boolean archived = false;

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
      System.debug(LoggingLevel.WARN, 'Time Trail Setup: not counted. ' + e.getMessage());
      return null;
    }
  }

  // ---- preview -------------------------------------------------------------

  /**
   * The events a draft source would plot for a record, through the same
   * providers and plotter the timeline uses, over the last year (and the
   * next, for future-dated records).
   */
  @AuraEnabled
  public static Preview preview(String draftJson, Id recordId) {
    requireSetupAccess();
    SourceDraft d = (SourceDraft) JSON.deserialize(draftJson, SourceDraft.class);
    Preview p = new Preview();
    if (recordId == null) {
      return p;
    }
    Time_Shift_Source__mdt s = d.toRecord();
    Object provider = TimeShiftConfig.providerFor(s, p.warnings);
    if (provider == null) {
      return p;
    }
    TimeShiftContext context = new TimeShiftContext(
      recordId,
      recordId.getSObjectType().getDescribe().getName(),
      Datetime.now().addYears(-1),
      s,
      null,
      p.warnings
    );
    context.until = Datetime.now().addYears(1);
    context.personContactId = TimeShiftController.personContactOf(recordId);
    context.draftDetailFields = d.detailRecords();
    context.draftHighlights = d.highlightRecords();
    try {
      List<TimeShiftController.EngagementEvent> events = TimeShiftPlotter.run(provider, context);
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
   * Saves a source (new or changed) and its detail fields. Returns the
   * deployment's id and the source's name; the result arrives as a
   * Time_Shift_Setup_Result__e.
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
      if (String.isNotBlank(h.field) && kept.size() < TimeShiftHighlights.MAX_RULES) {
        kept.add(h);
      }
    }
    d.highlights = kept;
    validate(d);
    if (String.isBlank(d.developerName)) {
      d.developerName = uniqueName(d.label);
    }
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    // The legend's order, when the wizard sends one: this source's place,
    // and any other source whose place changed, in the same deployment.
    for (Metadata.CustomMetadata moved : reordered(d)) {
      container.addMetadata(moved);
    }
    container.addMetadata(sourceMetadata(d));
    // Each detail keeps its own record; new ones are numbered, and ones no
    // longer used are blanked (Apex can't delete metadata records).
    Set<String> existing = new Set<String>();
    for (Time_Shift_Detail_Field__mdt f : TimeShiftConfig.storedDetailFields(d.developerName)) {
      existing.add(f.DeveloperName);
    }
    Set<String> taken = new Set<String>(existing);
    List<String> names = new List<String>();
    Integer n = 1;
    for (DetailDraft detail : d.details) {
      String name = detail.developerName;
      if (String.isBlank(name) || !existing.contains(name) || names.contains(name)) {
        do {
          name = d.developerName.left(34) + '_D' + n++;
        } while (!taken.add(name));
      }
      names.add(name);
    }
    for (String name : existing) {
      if (!names.contains(name)) {
        names.add(name);
      }
    }
    for (Integer i = 0; i < names.size(); i++) {
      container.addMetadata(detailMetadata(d, i, names[i]));
    }
    // Highlights the same way: their own records, unused ones blanked.
    Set<String> storedHighlights = new Set<String>();
    for (Time_Shift_Highlight__mdt h : TimeShiftConfig.storedHighlights(d.developerName)) {
      storedHighlights.add(h.DeveloperName);
    }
    Set<String> takenHighlights = new Set<String>(storedHighlights);
    List<String> highlightNames = new List<String>();
    Integer hn = 1;
    for (HighlightDraft h : d.highlights) {
      String name = h.developerName;
      if (String.isBlank(name) || !storedHighlights.contains(name) || highlightNames.contains(name)) {
        do {
          name = d.developerName.left(34) + '_H' + hn++;
        } while (!takenHighlights.add(name));
      }
      highlightNames.add(name);
    }
    for (String name : storedHighlights) {
      if (!highlightNames.contains(name)) {
        highlightNames.add(name);
      }
    }
    for (Integer i = 0; i < highlightNames.size(); i++) {
      container.addMetadata(highlightMetadata(d, i, highlightNames[i]));
    }
    return new SaveTicket(deploy(container, d.developerName), d.developerName);
  }

  // The legend order's stand-in for the source being saved (it may not have
  // a name yet).
  public static final String THIS_SOURCE = '__this__';

  /**
   * Places the draft in its legend order (sequence 10, 20, …) and returns
   * the other sources whose sequence that changes, ready to deploy.
   */
  @TestVisible
  private static List<Metadata.CustomMetadata> reordered(SourceDraft d) {
    List<Metadata.CustomMetadata> out = new List<Metadata.CustomMetadata>();
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
      Time_Shift_Source__mdt other = TimeShiftConfig.source(name);
      if (other == null || other.Sequence__c == place) {
        continue;
      }
      SourceDraft moved = new SourceDraft(other);
      moved.sequence = place;
      out.add(sourceMetadata(moved));
    }
    return out;
  }

  // ---- the timeline's views ------------------------------------------------

  /**
   * The views as Setup shows them: key, name in the viewer's language, the
   * custom label behind it (renaming is translating that), and whether the
   * picker offers it.
   */
  @AuraEnabled
  public static List<ViewDraft> getViewDrafts() {
    requireSetupAccess();
    List<ViewDraft> out = new List<ViewDraft>();
    for (Time_Shift_View__mdt v : TimeShiftConfig.views()) {
      ViewDraft d = new ViewDraft();
      d.developerName = v.DeveloperName;
      d.name = v.Label;
      d.menuLabel = v.Menu_Label__c;
      String raw = v.Menu_Label__c?.trim();
      d.labelName = String.isNotBlank(raw) && raw.startsWith(TimeShiftConfig.LABEL_PREFIX)
        ? raw.substring(TimeShiftConfig.LABEL_PREFIX.length())
        : null;
      d.sequence = v.Sequence__c;
      d.shown = TimeShiftConfig.viewLabel(v);
      d.active = TimeShiftConfig.isActive(v);
      out.add(d);
    }
    return out;
  }

  /**
   * Saves which views the picker offers, in one deployment. All is always
   * offered. Names come from custom labels, so a view is renamed by
   * changing its label's translation, not here.
   */
  @AuraEnabled
  public static SaveTicket saveViews(String viewsJson) {
    requireSetupAccess();
    List<ViewDraft> drafts = (List<ViewDraft>) JSON.deserialize(viewsJson, List<ViewDraft>.class);
    Map<String, Time_Shift_View__mdt> existing = new Map<String, Time_Shift_View__mdt>();
    for (Time_Shift_View__mdt v : TimeShiftConfig.views()) {
      existing.put(v.DeveloperName, v);
    }
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    Integer changed = 0;
    for (ViewDraft d : drafts) {
      Time_Shift_View__mdt v = existing.get(d.developerName);
      if (v == null) {
        throw failure('There is no view called ' + d.developerName + '.');
      }
      Boolean active = d.active != false;
      if (v.DeveloperName == TimeShiftConfig.ALL_VIEW && !active) {
        throw failure('All items is always offered.');
      }
      if (active == TimeShiftConfig.isActive(v)) {
        continue;
      }
      container.addMetadata(viewMetadata(v, active));
      changed++;
    }
    return changed == 0 ? new SaveTicket(null, 'Views') : new SaveTicket(deploy(container, 'Views'), 'Views');
  }

  // A view's record as it is, but for Active (a deploy replaces it whole).
  @TestVisible
  private static Metadata.CustomMetadata viewMetadata(Time_Shift_View__mdt v, Boolean active) {
    Metadata.CustomMetadata m = new Metadata.CustomMetadata();
    m.fullName = 'Time_Shift_View.' + v.DeveloperName;
    m.label = v.Label;
    Map<String, Object> values = new Map<String, Object>{
      'Active__c' => active,
      'Menu_Label__c' => v.Menu_Label__c,
      'Sequence__c' => v.Sequence__c
    };
    for (String field : values.keySet()) {
      Metadata.CustomMetadataValue value = new Metadata.CustomMetadataValue();
      value.field = field;
      value.value = values.get(field);
      m.values.add(value);
    }
    return m;
  }

  public class ViewDraft {
    @AuraEnabled
    public String developerName { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String menuLabel { get; set; }
    @AuraEnabled
    public String labelName { get; set; }
    @AuraEnabled
    public Decimal sequence { get; set; }
    @AuraEnabled
    public String shown { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
  }

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
    TimeShiftController.PERSON_ACCOUNT
  };

  @TestVisible
  private static Set<String> testFeatures;

  /** Which of those features this org has: each a describe, read once when asked. */
  public static Set<String> orgFeatures() {
    if (testFeatures != null) {
      return testFeatures;
    }
    Set<String> enabled = new Set<String>();
    Map<String, Schema.SObjectType> objects = Schema.getGlobalDescribe();
    if (objects.containsKey('taskrelation')) {
      enabled.add('SharedActivities');
    }
    if (Account.SObjectType.getDescribe().fields.getMap().containsKey('ispersonaccount')) {
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
    }
    return enabled;
  }

  /**
   * The settings the timeline can fit to, each with whether this org has it,
   * whether the timeline uses it now (an active source needs it), and what
   * switching would turn on and off. The install assumes none are used.
   */
  @AuraEnabled
  public static OrgFit getOrgFit() {
    requireSetupAccess();
    Set<String> enabled = orgFeatures();
    Set<String> used = usedFeatures();
    OrgFit fit = new OrgFit();
    for (String key : FEATURE_LABELS.keySet()) {
      FitFeature f = new FitFeature(key, FEATURE_LABELS.get(key), enabled.contains(key));
      f.used = used.contains(key);
      Set<String> withIt = used.clone();
      Set<String> without = used.clone();
      withIt.add(key);
      without.remove(key);
      Map<String, Boolean> withMap = targets(withIt);
      Map<String, Boolean> withoutMap = targets(without);
      for (Time_Shift_Source__mdt s : fittedSources()) {
        if (!withMap.containsKey(s.DeveloperName) || withMap.get(s.DeveloperName) == withoutMap.get(s.DeveloperName)) {
          continue;
        }
        String name = pageLabel(s) + ' ' + s.Label;
        // What using it turns on, and what it turns off.
        (withMap.get(s.DeveloperName) ? f.turnsOn : f.turnsOff).add(name);
      }
      fit.features.add(f);
    }
    fit.activityCapture = activityCapture();
    return fit;
  }

  /**
   * Fits the timeline to the settings named (only ones this org has): the
   * sources tied to a setting are made active or inactive to match, in one
   * deployment. Other sources are left as they are.
   */
  @AuraEnabled
  public static SaveTicket applyOrgFit(List<String> usedFeatures) {
    requireSetupAccess();
    Set<String> used = new Set<String>(usedFeatures == null ? new List<String>() : usedFeatures);
    Set<String> enabled = orgFeatures();
    for (String key : used) {
      if (!enabled.contains(key)) {
        throw failure((FEATURE_LABELS.containsKey(key) ? FEATURE_LABELS.get(key) : key) + ' is off in this org.');
      }
    }
    Map<String, Boolean> target = targets(used);
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    Integer changed = 0;
    for (Time_Shift_Source__mdt s : fittedSources()) {
      if (!target.containsKey(s.DeveloperName) || (s.Active__c == true) == target.get(s.DeveloperName)) {
        continue;
      }
      SourceDraft d = new SourceDraft(s);
      d.active = target.get(s.DeveloperName);
      container.addMetadata(sourceMetadata(d));
      changed++;
    }
    return changed == 0 ? new SaveTicket(null, 'Org_Fit') : new SaveTicket(deploy(container, 'Org_Fit'), 'Org_Fit');
  }

  // The settings the timeline uses now: those an active org-fitted source needs.
  private static Set<String> usedFeatures() {
    Set<String> used = new Set<String>();
    for (Time_Shift_Source__mdt s : fittedSources()) {
      if (s.Active__c == true) {
        used.addAll(needs(s));
      }
    }
    used.retainAll(FEATURE_LABELS.keySet());
    return used;
  }

  /**
   * Which org-fitted sources tied to a setting should be active, given the
   * settings used: in a group, the one needing the most of them (and nothing
   * else); alone, one whose needs are all used. Sources tied to no setting
   * aren't in the map, so fitting never touches them.
   */
  @TestVisible
  private static Map<String, Boolean> targets(Set<String> used) {
    Map<String, List<Time_Shift_Source__mdt>> groups = new Map<String, List<Time_Shift_Source__mdt>>();
    Map<String, Boolean> out = new Map<String, Boolean>();
    for (Time_Shift_Source__mdt s : fittedSources()) {
      if (String.isNotBlank(s.Variant_Group__c)) {
        String key = s.Parent_Object__c + '|' + s.Variant_Group__c;
        if (!groups.containsKey(key)) {
          groups.put(key, new List<Time_Shift_Source__mdt>());
        }
        groups.get(key).add(s);
      } else if (!needs(s).isEmpty()) {
        out.put(s.DeveloperName, used.containsAll(needs(s)));
      }
    }
    for (List<Time_Shift_Source__mdt> variants : groups.values()) {
      Boolean tied = false;
      Time_Shift_Source__mdt best;
      for (Time_Shift_Source__mdt s : variants) {
        tied = tied || !needs(s).isEmpty();
        if (used.containsAll(needs(s)) && (best == null || outranks(s, best))) {
          best = s;
        }
      }
      if (!tied) {
        continue;
      }
      for (Time_Shift_Source__mdt s : variants) {
        out.put(s.DeveloperName, s == best);
      }
    }
    return out;
  }

  @TestVisible
  private static ActivityCapture testActivityCapture;

  /**
   * Einstein Activity Capture, when any of its permission set licences are
   * assigned. Its emails reach the timeline only when Sync Email as
   * Salesforce Activity saves them as Tasks and Email Messages; that setting
   * can't be read from here, so setup asks the admin to check it.
   */
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
    }
    found.inUse = found.users > 0;
    return found;
  }

  // A variant beats another by needing more of the settings used; with as
  // many, by needing the one first in FEATURE_PRECEDENCE.
  private static Boolean outranks(Time_Shift_Source__mdt a, Time_Shift_Source__mdt b) {
    Integer sizeA = needs(a).size();
    Integer sizeB = needs(b).size();
    if (sizeA != sizeB) {
      return sizeA > sizeB;
    }
    return precedence(a) < precedence(b);
  }

  private static Integer precedence(Time_Shift_Source__mdt s) {
    Integer best = FEATURE_PRECEDENCE.size();
    for (String need : needs(s)) {
      Integer at = FEATURE_PRECEDENCE.indexOf(need);
      if (at >= 0 && at < best) {
        best = at;
      }
    }
    return best;
  }

  private static String pageLabel(Time_Shift_Source__mdt s) {
    String page = String.isBlank(s.Parent_Object__c) ? 'Contact' : s.Parent_Object__c;
    return page == TimeShiftController.PERSON_ACCOUNT ? 'Person Account' : page;
  }

  private static List<Time_Shift_Source__mdt> fittedSources() {
    List<SourceOrder> ordered = new List<SourceOrder>();
    for (Time_Shift_Source__mdt s : TimeShiftConfig.allSources().values()) {
      if (s.getPopulatedFieldsAsMap().get('Org_Fit__c') == true && s.Removed__c != true) {
        ordered.add(new SourceOrder(s));
      }
    }
    ordered.sort();
    List<Time_Shift_Source__mdt> out = new List<Time_Shift_Source__mdt>();
    for (SourceOrder o : ordered) {
      out.add(o.source);
    }
    return out;
  }

  private static List<String> needs(Time_Shift_Source__mdt s) {
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
    Time_Shift_Source__mdt source;
    SourceOrder(Time_Shift_Source__mdt source) {
      this.source = source;
    }
    Integer page() {
      Integer i = PAGE_ORDER.indexOf(String.isBlank(source.Parent_Object__c) ? 'Contact' : source.Parent_Object__c);
      return i < 0 ? PAGE_ORDER.size() : i;
    }
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

  /** Switches a source on or off. */
  @AuraEnabled
  public static SaveTicket setActive(String developerName, Boolean active) {
    requireSetupAccess();
    Time_Shift_Source__mdt s = TimeShiftConfig.source(developerName);
    if (s == null) {
      throw failure('That source no longer exists.');
    }
    SourceDraft d = new SourceDraft(s);
    d.active = active == true;
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    container.addMetadata(sourceMetadata(d));
    return new SaveTicket(deploy(container, developerName), developerName);
  }

  /**
   * Removes a source: switched off and marked removed, so the timeline and
   * this page leave it out. (Apex can't delete metadata records; Setup can.)
   */
  @AuraEnabled
  public static SaveTicket remove(String developerName) {
    requireSetupAccess();
    Time_Shift_Source__mdt s = TimeShiftConfig.source(developerName);
    if (s == null) {
      throw failure('That source no longer exists.');
    }
    SourceDraft d = new SourceDraft(s);
    d.active = false;
    d.removed = true;
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    container.addMetadata(sourceMetadata(d));
    return new SaveTicket(deploy(container, developerName), developerName);
  }

  @TestVisible
  private static String deploy(Metadata.DeployContainer container, String developerName) {
    if (Test.isRunningTest()) {
      return 'test-job';
    }
    try {
      return Metadata.Operations.enqueueDeployment(container, new SaveResult(developerName));
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Time Trail Setup: save failed. ' + e.getMessage());
      throw failure('The source couldn\'t be saved. You need permission to customise the application.');
    }
  }

  private static void validate(SourceDraft d) {
    List<String> missing = new List<String>();
    if (String.isBlank(d.label)) {
      missing.add('a name');
    }
    if (d.kind == TimeShiftContext.KIND_APEX) {
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
        d.kind == TimeShiftContext.KIND_SALESFORCE &&
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
    Map<String, Time_Shift_Source__mdt> all = TimeShiftConfig.allSources();
    String name = base;
    Integer n = 2;
    while (all.containsKey(name)) {
      name = base + '_' + n++;
    }
    return name;
  }

  @TestVisible
  private static Metadata.CustomMetadata sourceMetadata(SourceDraft d) {
    Metadata.CustomMetadata m = new Metadata.CustomMetadata();
    m.fullName = SOURCE_TYPE + '.' + d.developerName;
    m.label = d.label.left(40);
    Map<String, Object> values = new Map<String, Object>{
      'Active__c' => d.active,
      'Removed__c' => d.removed == true,
      'Kind__c' => d.kind,
      // Every source runs, whatever its kind.
      'Source_Mode__c' => 'Always',
      'Parent_Object__c' => String.isBlank(d.parentObject) ? 'Contact' : d.parentObject,
      'Object_Name__c' => d.objectName,
      'Parent_Field__c' => d.parentField,
      'Junction_Object__c' => d.junctionObject,
      'Junction_Parent_Field__c' => d.junctionParentField,
      'Junction_Record_Field__c' => d.junctionRecordField,
      'Individual_Field__c' => d.individualField,
      'Data_Space__c' => String.isBlank(d.dataSpace) ? null : d.dataSpace,
      'Date_Field__c' => d.dateField,
      'Filter__c' => d.filterText(),
      'Max_Records__c' => d.maxRecords,
      'History_Months__c' => d.historyMonths,
      'Event_Type__c' => String.isBlank(d.eventType) ? d.developerName.toLowerCase() : d.eventType,
      'Event_Label__c' => d.eventLabel,
      'Category__c' => d.category,
      'Title__c' => d.title,
      'Subtitle__c' => d.subtitle,
      'Icon__c' => d.icon,
      'Icon_Colour__c' => d.iconColour,
      'Use_Compact_Layout__c' => d.useCompactLayout == true,
      'Record_Id_Field__c' => d.recordIdFieldOrRelated(),
      'Org_Fit__c' => d.orgFit == true,
      'Requires__c' => d.requires,
      'Variant_Group__c' => d.variantGroup,
      'Details_Record_Field__c' => d.detailsRecordFieldOrRelated(),
      'Details_Object__c' => String.isBlank(d.detailsRecordFieldOrRelated()) ? null : d.detailsObject,
      'Provider_Class__c' => d.providerClass,
      'Sequence__c' => d.sequence == null ? 50 : d.sequence
    };
    for (String field : values.keySet()) {
      Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
      v.field = field;
      v.value = values.get(field);
      m.values.add(v);
    }
    return m;
  }

  private static Metadata.CustomMetadata detailMetadata(SourceDraft d, Integer i, String name) {
    DetailDraft detail = i < d.details.size() ? d.details[i] : null;
    Metadata.CustomMetadata m = new Metadata.CustomMetadata();
    m.fullName = DETAIL_TYPE + '.' + name;
    // No label of its own is saved as the field itself (a label is required):
    // the timeline then uses the field's own label, in the user's language.
    m.label = detail == null
      ? 'Unused'
      : (String.isBlank(detail.label) ? String.valueOf(detail.field) : detail.label).left(40);
    Map<String, Object> values = new Map<String, Object>{
      'Source__c' => d.developerName,
      'Field__c' => detail == null ? null : detail.field,
      'Format__c' => detail == null || String.isBlank(detail.format) ? 'Text' : detail.format,
      'Sequence__c' => (i + 1) * 10
    };
    for (String field : values.keySet()) {
      Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
      v.field = field;
      v.value = values.get(field);
      m.values.add(v);
    }
    return m;
  }

  private static Metadata.CustomMetadata highlightMetadata(SourceDraft d, Integer i, String name) {
    HighlightDraft h = i < d.highlights.size() ? d.highlights[i] : null;
    Metadata.CustomMetadata m = new Metadata.CustomMetadata();
    m.fullName = HIGHLIGHT_TYPE + '.' + name;
    m.label = h == null ? 'Unused' : String.valueOf(h.field).left(40);
    Map<String, Object> values = new Map<String, Object>{
      'Source__c' => d.developerName,
      'Field__c' => h == null ? null : h.field,
      'Values__c' => h == null ? null : 'true',
      'Icon__c' => h == null ? null : h.icon,
      'Colour__c' => h == null ? null : h.colour,
      'Sequence__c' => (i + 1) * 10
    };
    for (String field : values.keySet()) {
      Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
      v.field = field;
      v.value = values.get(field);
      m.values.add(v);
    }
    return m;
  }

  /** Sources are metadata: managing them needs "Customize Application". */
  private static void requireSetupAccess() {
    if (!userCanCustomize()) {
      throw failure('Only admins (with Customize Application) can manage timeline sources.');
    }
  }

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

  // ---- the deployment's result --------------------------------------------

  /** Publishes the deployment's outcome for the page to show. */
  public class SaveResult implements Metadata.DeployCallback {
    private String developerName;

    public SaveResult(String developerName) {
      this.developerName = developerName;
    }

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
      String message = '';
      if (result.status != Metadata.DeployStatus.Succeeded && result.details != null) {
        for (Metadata.DeployMessage m : result.details.componentFailures) {
          message += m.fullName + ': ' + m.problem + ' ';
        }
        System.debug(LoggingLevel.ERROR, 'Time Trail Setup: ' + developerName + ' failed. ' + message);
      }
      EventBus.publish(
        new Time_Shift_Setup_Result__e(
          Job_Id__c = result.id,
          Source__c = developerName,
          Status__c = String.valueOf(result.status),
          Message__c = message.left(255)
        )
      );
    }
  }

  // ---- shapes the page reads and sends ------------------------------------

  /** A save under way: the deployment to wait for, and the source it saves. */
  public class SaveTicket {
    @AuraEnabled
    public String jobId;
    @AuraEnabled
    public String developerName;

    public SaveTicket(String jobId, String developerName) {
      this.jobId = jobId;
      this.developerName = developerName;
    }
  }

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

    public Option(String value, String label, String detail) {
      this.value = value;
      this.label = label;
      this.detail = detail;
    }

    public Option plural(String pluralLabel) {
      this.pluralLabel = pluralLabel;
      return this;
    }

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

    // A lookup on the object itself.
    public Link(String parentField, String label) {
      this.key = parentField;
      this.label = label;
      this.parentField = parentField;
    }

    // A junction object with lookups to both.
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

    public SourceSummary(Time_Shift_Source__mdt s) {
      developerName = s.DeveloperName;
      label = s.Label;
      kind = new TimeShiftContext(null, null, null, s, null, null).kind();
      parentObject = String.isBlank(s.Parent_Object__c) ? 'Contact' : s.Parent_Object__c;
      type = kind == TimeShiftContext.KIND_APEX
        ? 'apex'
        : kind == TimeShiftContext.KIND_DATA_360
            ? 'dmo'
            : (String.isNotBlank(s.Object_Name__c) && s.Object_Name__c.endsWithIgnoreCase('__c')
                ? 'custom'
                : 'standard');
      active = s.Active__c;
      objectName = s.Object_Name__c;
      objectLabel = labelOf(s.Object_Name__c);
      category = s.Category__c;
      icon = s.Icon__c;
      iconColour = s.Icon_Colour__c;
      eventType = s.Event_Type__c;
      eventLabel = s.Event_Label__c;
      legendName = TimeShiftConfig.legendLabel(s);
      sequence = s.Sequence__c;
      summary = describeSource(s, kind, objectLabel);
    }

    public Integer compareTo(Object other) {
      Decimal mine = sequence == null ? 0 : sequence;
      Decimal theirs = ((SourceSummary) other).sequence == null ? 0 : ((SourceSummary) other).sequence;
      return mine == theirs ? label.compareTo(((SourceSummary) other).label) : (mine < theirs ? -1 : 1);
    }
  }

  // "Invoice__c records whose Customer is this Contact, dated by Invoice Date."
  private static String describeSource(Time_Shift_Source__mdt s, String kind, String objectLabel) {
    String parent = String.isBlank(s.Parent_Object__c) ? 'record' : labelOf(s.Parent_Object__c);
    if (kind == TimeShiftContext.KIND_APEX) {
      return 'Events from the Apex class ' + s.Provider_Class__c + '.';
    }
    String text = objectLabel + ' records';
    if (kind == TimeShiftContext.KIND_DATA_360) {
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
    Schema.SObjectType t = TimeShiftConfig.sObjectType(objectName);
    return t == null ? objectName : t.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getLabel();
  }

  private static String fieldLabel(String objectName, String field) {
    Schema.SObjectType t = TimeShiftConfig.sObjectType(objectName);
    Schema.SObjectField f = t == null || String.isBlank(field)
      ? null
      : t.getDescribe().fields.getMap().get(field.toLowerCase());
    return f == null ? field : f.getDescribe().getLabel();
  }

  /** A detail field as the wizard edits it. */
  public class DetailDraft {
    @AuraEnabled
    public String developerName { get; set; }
    @AuraEnabled
    public String field { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String format { get; set; }

    public DetailDraft() {
    }

    public DetailDraft(Time_Shift_Detail_Field__mdt d) {
      developerName = d.DeveloperName;
      field = d.Field__c;
      // Label = the field means none of its own (the field's label is used).
      label = d.Label == String.valueOf(d.Field__c).left(40) ? null : d.Label;
      format = d.Format__c;
    }
  }

  /** One highlight as the wizard edits it. */
  public class HighlightDraft {
    @AuraEnabled
    public String developerName { get; set; }
    @AuraEnabled
    public String field { get; set; }
    @AuraEnabled
    public String icon { get; set; }
    @AuraEnabled
    public String colour { get; set; }

    public HighlightDraft() {
    }

    public HighlightDraft(Time_Shift_Highlight__mdt h) {
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
    @AuraEnabled
    public String developerName { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String kind { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
    @AuraEnabled
    public String parentObject { get; set; }
    @AuraEnabled
    public String objectName { get; set; }
    @AuraEnabled
    public String parentField { get; set; }
    @AuraEnabled
    public String junctionObject { get; set; }
    @AuraEnabled
    public String junctionParentField { get; set; }
    @AuraEnabled
    public String junctionRecordField { get; set; }
    @AuraEnabled
    public String individualField { get; set; }
    // Data 360: the data space its DMO is in (blank: the default).
    @AuraEnabled
    public String dataSpace { get; set; }
    @AuraEnabled
    public String dateField { get; set; }
    @AuraEnabled
    public List<Condition> conditions { get; set; }
    @AuraEnabled
    public String filter { get; set; }
    @AuraEnabled
    public Decimal maxRecords { get; set; }
    @AuraEnabled
    public Decimal historyMonths { get; set; }
    @AuraEnabled
    public Boolean removed { get; set; }
    @AuraEnabled
    public String eventType { get; set; }
    @AuraEnabled
    public String eventLabel { get; set; }
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String subtitle { get; set; }
    @AuraEnabled
    public String icon { get; set; }
    @AuraEnabled
    public String iconColour { get; set; }
    @AuraEnabled
    public Boolean useCompactLayout { get; set; }
    // Where a click goes, and whose compact layout an opened item shows
    // (blank: the item's own record).
    @AuraEnabled
    public String recordIdField { get; set; }
    // Org-fitted sources: kept as shipped through edits and switches.
    @AuraEnabled
    public Boolean orgFit { get; set; }
    @AuraEnabled
    public String requires { get; set; }
    @AuraEnabled
    public String variantGroup { get; set; }
    @AuraEnabled
    public String detailsRecordField { get; set; }
    @AuraEnabled
    public String detailsObject { get; set; }
    @AuraEnabled
    public String providerClass { get; set; }
    @AuraEnabled
    public Decimal sequence { get; set; }
    @AuraEnabled
    public List<DetailDraft> details { get; set; }
    // One icon for a checkbox that is checked (TimeShiftHighlights).
    @AuraEnabled
    public List<HighlightDraft> highlights { get; set; }
    // The record page's sources in legend order, this one as __this__
    // (sent from the wizard's Fine-tune step; blank leaves the order be).
    @AuraEnabled
    public List<String> legendOrder { get; set; }

    public SourceDraft() {
      details = new List<DetailDraft>();
      highlights = new List<HighlightDraft>();
      conditions = new List<Condition>();
      active = true;
    }

    public SourceDraft(Time_Shift_Source__mdt s) {
      this();
      developerName = s.DeveloperName;
      label = s.Label;
      kind = new TimeShiftContext(null, null, null, s, null, null).kind();
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
      List<Condition> parsed = conditionsOf(s.Filter__c);
      if (parsed != null && !parsed.isEmpty()) {
        conditions = parsed;
        filter = null;
      }
      maxRecords = s.Max_Records__c;
      historyMonths = s.History_Months__c;
      removed = s.Removed__c;
      eventType = s.Event_Type__c;
      eventLabel = s.Event_Label__c;
      category = s.Category__c;
      title = s.Title__c;
      subtitle = s.Subtitle__c;
      icon = s.Icon__c;
      iconColour = s.Icon_Colour__c;
      useCompactLayout = s.Use_Compact_Layout__c;
      recordIdField = s.Record_Id_Field__c;
      Map<String, Object> populated = s.getPopulatedFieldsAsMap();
      orgFit = populated.get('Org_Fit__c') == true;
      requires = (String) populated.get('Requires__c');
      variantGroup = (String) populated.get('Variant_Group__c');
      detailsRecordField = s.Details_Record_Field__c;
      detailsObject = s.Details_Object__c;
      providerClass = s.Provider_Class__c;
      sequence = s.Sequence__c;
    }

    // A relation object whose date is its record's (TaskRelation, Task.ActivityDate)
    // opens that record, its task: the lookup to it, unless the source says otherwise.
    private String relatedRecordField() {
      String record = RELATION_RECORDS.get(objectName);
      return record != null && String.isNotBlank(dateField) && dateField.startsWith(record + '.') ? record + 'Id' : null;
    }

    public String recordIdFieldOrRelated() {
      return String.isBlank(recordIdField) ? relatedRecordField() : recordIdField;
    }

    public String detailsRecordFieldOrRelated() {
      return String.isBlank(detailsRecordField) ? relatedRecordField() : detailsRecordField;
    }

    // The conditions as a SOQL filter (values bound as literals, quoted and
    // escaped by type), or the filter text written by hand.
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
      return parts.isEmpty() ? null : String.join(parts, ' AND ');
    }

    // In memory, as the timeline reads it (for the preview).
    public Time_Shift_Source__mdt toRecord() {
      return new Time_Shift_Source__mdt(
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
        Use_Compact_Layout__c = useCompactLayout == true,
        Record_Id_Field__c = recordIdFieldOrRelated(),
        Details_Record_Field__c = detailsRecordFieldOrRelated(),
        Details_Object__c = detailsObject,
        Provider_Class__c = providerClass
      );
    }

    /** The highlights as records, for the preview (at most the two a source keeps). */
    public List<Time_Shift_Highlight__mdt> highlightRecords() {
      List<Time_Shift_Highlight__mdt> out = new List<Time_Shift_Highlight__mdt>();
      for (HighlightDraft h : highlights == null ? new List<HighlightDraft>() : highlights) {
        if (String.isNotBlank(h.field) && out.size() < TimeShiftHighlights.MAX_RULES) {
          out.add(
            new Time_Shift_Highlight__mdt(
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

    public List<Time_Shift_Detail_Field__mdt> detailRecords() {
      List<Time_Shift_Detail_Field__mdt> out = new List<Time_Shift_Detail_Field__mdt>();
      Integer i = 0;
      for (DetailDraft d : details == null ? new List<DetailDraft>() : details) {
        // At most four fields besides the title and subtitle.
        if (String.isNotBlank(d.field) && i < MAX_DETAILS) {
          out.add(
            new Time_Shift_Detail_Field__mdt(
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
   * The conditions a filter was built from (Condition.soql() joined by AND),
   * or null when it is anything else (an OR, NOT IN, brackets ...): such a
   * filter, as one that ships with a source, is kept as the text it is.
   */
  @TestVisible
  private static List<Condition> conditionsOf(String filter) {
    if (String.isBlank(filter)) {
      return null;
    }
    List<String> parts = new List<String>();
    String current = '';
    Boolean quoted = false;
    Integer i = 0;
    while (i < filter.length()) {
      String ch = filter.substring(i, i + 1);
      if (quoted) {
        current += ch;
        if (ch == '\\' && i + 1 < filter.length()) {
          current += filter.substring(i + 1, i + 2);
          i++;
        } else if (ch == '\'') {
          quoted = false;
        }
      } else if (ch == '\'') {
        quoted = true;
        current += ch;
      } else if (filter.substring(i, Math.min(i + 5, filter.length())) == ' AND ') {
        parts.add(current);
        current = '';
        i += 5;
        continue;
      } else {
        current += ch;
      }
      i++;
    }
    if (quoted) {
      return null;
    }
    parts.add(current);
    List<Condition> out = new List<Condition>();
    for (String part : parts) {
      Condition c = conditionOf(part.trim());
      if (c == null) {
        return null;
      }
      out.add(c);
    }
    return out;
  }

  private static Condition conditionOf(String part) {
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
    Map<String, String> ops = new Map<String, String>{ '=' => 'equals', '!=' => 'notEquals', '>' => 'greater', '<' => 'less' };
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
    @AuraEnabled
    public String field { get; set; }
    @AuraEnabled
    public String operator { get; set; }
    @AuraEnabled
    public String value { get; set; }
    // boolean, number, date, datetime or text (how the value is written).
    @AuraEnabled
    public String valueType { get; set; }

    public String soql() {
      if (String.isBlank(field) || !Pattern.matches('[A-Za-z0-9_.]+', field)) {
        return null;
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

    public FieldInfo(Schema.DescribeFieldResult fd) {
      name = fd.getName();
      label = fd.getLabel();
      type = String.valueOf(fd.getType()).toLowerCase();
      filterable = fd.isFilterable();
      List<Schema.SObjectType> targets = fd.getReferenceTo();
      if (targets.size() == 1 && String.isNotBlank(fd.getRelationshipName())) {
        Schema.DescribeSObjectResult target = targets[0].getDescribe();
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

    public Integer compareTo(Object other) {
      return label.toLowerCase().compareTo(((FieldInfo) other).label.toLowerCase());
    }
  }

  public class OrgFit {
    @AuraEnabled
    public List<FitFeature> features = new List<FitFeature>();
    // Einstein Activity Capture, when its licences are assigned (see
    // activityCapture): users, and the licences' names.
    @AuraEnabled
    public ActivityCapture activityCapture;
  }

  public class ActivityCapture {
    @AuraEnabled
    public Boolean inUse = false;
    @AuraEnabled
    public Integer users = 0;
    @AuraEnabled
    public List<String> licences = new List<String>();
  }

  public class FitFeature {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    // This org has it.
    @AuraEnabled
    public Boolean enabled;
    // The timeline uses it now.
    @AuraEnabled
    public Boolean used = false;
    // Sources using it turns on, and turns off (Contact Tasks, …).
    @AuraEnabled
    public List<String> turnsOn = new List<String>();
    @AuraEnabled
    public List<String> turnsOff = new List<String>();
    public FitFeature(String key, String label, Boolean enabled) {
      this.key = key;
      this.label = label;
      this.enabled = enabled;
    }
  }

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

  public class VolumeRange {
    @AuraEnabled
    public Integer months;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public Boolean more = false;
  }

  public class Preview {
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public List<TimeShiftController.EngagementEvent> events = new List<TimeShiftController.EngagementEvent>();
    @AuraEnabled
    public List<String> warnings = new List<String>();
    @AuraEnabled
    public List<TimeShiftController.Problem> problems = new List<TimeShiftController.Problem>();
  }
}
