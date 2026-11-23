// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings(
  'PMD.ApexUnitTestClassShouldHaveRunAs, PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.NcssCount'
)
@IsTest
private class TimeDriveSetupControllerTest {
  // A well-formed Id for tests: the object's key prefix and a number.
  private static Id fakeId(String prefix, Integer n) {
    return Id.valueOf(prefix + String.valueOf(n).leftPad(12, '0'));
  }

  // The sources the timeline once shipped with, in place of the org's.
  static {
    TimeDriveTestData.useShipped();
  }

  @TestSetup
  static void makeData() {
    // Standard objects only: the orders are Tasks.
    Contact customer = new Contact(FirstName = 'Ada', LastName = 'Shift');
    insert customer;
    Date placed = Date.today().addDays(-3);
    insert new List<Task>{
      new Task(WhoId = customer.Id, Subject = 'Order 1001', Status = 'Completed', ActivityDate = placed),
      new Task(WhoId = customer.Id, Subject = 'Order 1002', Status = 'Deferred', ActivityDate = placed.addDays(-10))
    };
  }

  static TimeDriveSetupController.SourceDraft orderDraft() {
    TimeDriveSetupController.SourceDraft d = new TimeDriveSetupController.SourceDraft();
    d.label = 'Orders from setup';
    d.kind = 'Salesforce';
    d.parentObject = 'Contact';
    d.objectName = 'Task';
    d.parentField = 'WhoId';
    d.dateField = 'ActivityDate';
    d.title = 'Order {Status}';
    return d;
  }

  static TimeDriveSetupController.Condition condition(String field, String op, String value, String type) {
    TimeDriveSetupController.Condition c = new TimeDriveSetupController.Condition();
    c.field = field;
    c.operator = op;
    c.value = value;
    c.valueType = type;
    return c;
  }

  @IsTest
  static void listsEverySourceInPlainWords() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      List<TimeDriveSetupController.SourceSummary> sources = TimeDriveSetupController.getSources();
      Assert.areEqual(TimeDriveTestData.sources().size(), sources.size());
      for (TimeDriveSetupController.SourceSummary s : sources) {
        Assert.isTrue(String.isNotBlank(s.summary), s.developerName + ' has no summary');
        Assert.isNotNull(s.kind);
      }
    }
  }

  @IsTest
  static void editsASourceWithItsDetailFields() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = TimeDriveSetupController.getSource('Order_Placed');
      Assert.areEqual('Task', d.objectName);
      Assert.areEqual('WhoId', d.parentField);
      Assert.areEqual('Salesforce', d.kind);
      try {
        TimeDriveSetupController.getSource('No_Such_Source');
        Assert.fail('A missing source should say so');
      } catch (AuraHandledException e) {
        Assert.areEqual('That source no longer exists.', e.getMessage());
      }
    }
  }

  @IsTest
  static void offersObjectsByKindWithoutPlumbing() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Set<String> standard = new Set<String>();
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('standard', 'Contact', null)) {
        standard.add(o.value);
      }
      Assert.isTrue(standard.contains('Case'));
      Assert.isTrue(standard.contains('Opportunity'), 'Opportunities link through OpportunityContactRole');
      Assert.isFalse(standard.contains('Pricebook2'), 'Nothing links a price book to a Contact');
      Assert.isTrue(standard.contains('Event'), 'The calendar Event is a record, not a platform event');
      Assert.isFalse(standard.contains('CaseHistory'));
      Assert.isTrue(standard.contains('Task'), 'tasks link by WhoId');
      // Change-event, history, feed and share companions are passed over by name.
      for (
        String name : new List<String>{
          'ContactChangeEvent',
          'AccountHistory',
          'CaseFeed',
          'Project__Share',
          'X__ChangeEvent'
        }
      ) {
        Assert.isTrue(TimeDriveSetupController.isCompanion(name), name);
      }
      for (
        String name : new List<String>{
          'Case',
          'Task',
          'OpportunityContactRole',
          'Project_History__c',
          'CampaignMember'
        }
      ) {
        Assert.isFalse(TimeDriveSetupController.isCompanion(name), name);
      }
      for (String name : standard) {
        Assert.isFalse(name.endsWith('ChangeEvent'), name);
      }
      // Custom objects are custom (whatever this org has), and never metadata.
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('custom', 'Contact', null)) {
        Assert.isTrue(o.value.endsWith('__c'), o.value);
        Assert.isFalse(standard.contains(o.value));
      }
    }
  }

  @IsTest
  static void findsLookupsAndJunctionsToTheContact() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Boolean who = false;
      for (TimeDriveSetupController.Link l : TimeDriveSetupController.getLinks('Contact', 'Task')) {
        who |= l.parentField == 'WhoId';
      }
      Assert.isTrue(who, 'Task.WhoId links to the Contact');

      Boolean contactRole = false;
      for (TimeDriveSetupController.Link l : TimeDriveSetupController.getLinks('Contact', 'Opportunity')) {
        contactRole |= l.junctionObject == 'OpportunityContactRole' && l.junctionRecordField == 'OpportunityId';
        Assert.areNotEqual('Attachment', l.junctionObject, 'Polymorphic lookups are not junctions');
      }
      Assert.isTrue(contactRole, 'Opportunities link through OpportunityContactRole');

      // What the diagram draws: the objects and the lookups between them, in the org's own labels.
      for (TimeDriveSetupController.Link l : TimeDriveSetupController.getLinks('Contact', 'Opportunity')) {
        if (l.junctionObject == 'OpportunityContactRole') {
          Assert.areEqual(Contact.SObjectType.getDescribe().getLabel(), l.parentLabel);
          Assert.areEqual(Opportunity.SObjectType.getDescribe().getLabel(), l.objectLabel);
          Assert.areEqual(OpportunityContactRole.ContactId.getDescribe().getLabel(), l.fieldLabel);
          Assert.areEqual(OpportunityContactRole.OpportunityId.getDescribe().getLabel(), l.recordFieldLabel);
          Assert.isNotNull(l.junctionLabel);
        }
      }
      TimeDriveSetupController.Link taskLink = TimeDriveSetupController.getLinks('Contact', 'Task')[0];
      Assert.areEqual(Task.SObjectType.getDescribe().getLabel(), taskLink.objectLabel);
      Assert.areEqual(Task.Subject.getDescribe().getLabel(), taskLink.objectNameLabel);
      Assert.isFalse(taskLink.masterDetail, 'a Task points at its Contact by a lookup');
    }
  }

  static Time_Drive_Source__mdt fitted(String name, String page, String requires, String variantGroup, Boolean active) {
    return new Time_Drive_Source__mdt(
      DeveloperName = name,
      Label = name,
      Active__c = active,
      Parent_Object__c = page,
      Object_Name__c = 'Task',
      Parent_Field__c = 'WhoId',
      Date_Field__c = 'ActivityDate',
      Requires__c = requires,
      Variant_Group__c = variantGroup,
      Sequence__c = 10
    );
  }

  @IsTest
  static void choosesTheTimelineViews() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testViews = new List<Time_Drive_View__mdt>{
        new Time_Drive_View__mdt(
          DeveloperName = 'Service',
          Label = 'Service',
          Menu_Label__c = '$Label.Time_Drive_View_Service',
          Sequence__c = 40
        ),
        new Time_Drive_View__mdt(
          DeveloperName = 'All',
          Label = 'All',
          Menu_Label__c = '$Label.Time_Drive_View_All',
          Sequence__c = 99
        ),
        new Time_Drive_View__mdt(DeveloperName = 'Sales', Label = 'Sales', Sequence__c = 10),
        new Time_Drive_View__mdt(DeveloperName = 'Digital', Label = 'Digital', Sequence__c = 30)
      };
      // Switched off in Setup before (Gone is a view that's since been deleted).
      insert new Time_Drive_Setup__c(Name = 'Org', Hidden_Views__c = 'Digital,Gone');
      // All first, then alphabetically; names come from custom labels (a blank
      // one reads as the view's label); an inactive view isn't offered.
      List<TimeDriveController.ViewOption> views = TimeDriveController.getViews();
      Assert.areEqual(3, views.size());
      Assert.areEqual('All', views[0].value);
      Assert.areEqual(System.Label.Time_Drive_View_All, views[0].label);
      Assert.areEqual('Sales', views[1].value);
      Assert.areEqual('Sales', views[1].label);
      Assert.areEqual(System.Label.Time_Drive_View_Service, views[2].label);

      // Setup sees every view, with the label behind its name.
      List<TimeDriveSetupController.ViewDraft> drafts = TimeDriveSetupController.getViewDrafts();
      Assert.areEqual(4, drafts.size());
      Assert.areEqual('Time_Drive_View_All', drafts[0].labelName);
      Assert.isTrue(drafts[0].active, 'All is always offered');
      Assert.areEqual('Digital', drafts[1].developerName, 'All, then alphabetically');
      Assert.isFalse(drafts[1].active, drafts[1].developerName);

      // Switching views off and on is kept on the org's Setup record at once;
      // views not sent keep their state, and deleted ones drop out.
      Assert.areEqual(
        'Views',
        TimeDriveSetupController.saveViews(
            '[{"developerName":"Service","active":false},{"developerName":"Sales","active":true}]'
          )
          .developerName
      );
      Assert.areEqual('Digital,Service', [SELECT Hidden_Views__c FROM Time_Drive_Setup__c].Hidden_Views__c);
      Assert.areEqual(1, [SELECT COUNT() FROM Time_Drive_Setup__c], 'one record for the org');
      views = TimeDriveController.getViews();
      Assert.areEqual(2, views.size(), 'All and Sales');
      Assert.areEqual('Sales', views[1].value);

      TimeDriveSetupController.saveViews(
        '[{"developerName":"Service","active":true},{"developerName":"Digital","active":true}]'
      );
      Assert.isNull([SELECT Hidden_Views__c FROM Time_Drive_Setup__c].Hidden_Views__c, 'every view offered');
      Assert.areEqual(4, TimeDriveController.getViews().size());
      for (String bad : new List<String>{ '[{"developerName":"Nope"}]', '[{"developerName":"All","active":false}]' }) {
        try {
          TimeDriveSetupController.saveViews(bad);
          Assert.fail('not saved: ' + bad);
        } catch (AuraHandledException e) {
          Assert.isNotNull(e.getMessage());
        }
      }
    }
  }

  @IsTest
  static void reportsEinsteinActivityCaptureForTheEmailSyncCheck() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // No licences assigned: not in use, and nothing to check.
      TimeDriveSetupController.ActivityCapture none = new TimeDriveSetupController.ActivityCapture();
      none.inUse = false;
      TimeDriveSetupController.testActivityCapture = none;
      TimeDriveSetupController.OrgCheck unused = TimeDriveSetupController.runOrgCheck('ActivityCapture');
      Assert.isFalse(unused.present);
      Assert.areEqual('Not in use', unused.found);
      Assert.isTrue(unused.meaning.contains('nothing to check'), unused.meaning);
      // With licences assigned, setup says it is in use and asks for the email sync check.
      TimeDriveSetupController.ActivityCapture assigned = new TimeDriveSetupController.ActivityCapture();
      assigned.inUse = true;
      assigned.users = 12;
      TimeDriveSetupController.testActivityCapture = assigned;
      TimeDriveSetupController.OrgCheck reported = TimeDriveSetupController.runOrgCheck('ActivityCapture');
      Assert.isTrue(reported.present);
      Assert.areEqual('In use', reported.found);
      Assert.isTrue(reported.meaning.contains('Sync Email as Salesforce Activity'), reported.meaning);
    }
  }

  @IsTest
  static void listsDataModelObjectsDataCloudNamesAndSkipsUnknownOnes() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // A name Data 360 offers that this org can't describe is left out; no
      // DMOs here, so the list is empty rather than an error.
      TimeDriveSetupController.testDmoNames = new List<String>{ 'NotHere__dlm' };
      Assert.isTrue(TimeDriveSetupController.getObjects('dmo', 'Contact', null).isEmpty());
      // Objects the global describe lists are still found by name.
      Assert.areEqual(Contact.SObjectType, TimeDriveConfig.sObjectType('Contact'));
      Assert.isNull(TimeDriveConfig.sObjectType('NotHere__dlm'));
      Assert.isNull(TimeDriveConfig.sObjectType(''));
    }
  }

  @IsTest
  static void aLookupToManyObjectsLeadsToTheirNames() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.FieldInfo what;
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('Task')) {
        if (f.name == 'WhatId') {
          what = f;
        }
      }
      // Related To points at many objects: no one object, but it leads on (What.Name).
      Assert.isTrue(what.polymorphic, 'Related To is a lookup to many');
      Assert.areEqual('What', what.relationshipName);
      Assert.isNull(what.referenceTo, 'no one object, so nothing treats it as one');
      Boolean hasName = false;
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('Name')) {
        hasName = hasName || f.name == 'Name';
        Assert.isNull(f.relationshipName, 'a query goes no further than What.Name: ' + f.name);
        Assert.isFalse(f.polymorphic, f.name);
      }
      Assert.isTrue(hasName, 'the Name object has its Name');
    }
  }

  @IsTest
  static void aTitleIsOneFieldAndASubtitleUpToTwo() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Assert.areEqual('{Subject}', TimeDriveSetupController.oneField('{Subject}'));
      Assert.areEqual('{Status}', TimeDriveSetupController.oneField('{Status} · {Priority}'), 'the first is kept');
      Assert.areEqual('{Name}', TimeDriveSetupController.oneField('Order {Name} placed'), 'words go');
      Assert.areEqual('{Who.Name}', TimeDriveSetupController.oneField('{Who.Name}'), 'a related field is one field');
      Assert.isNull(TimeDriveSetupController.oneField('Order placed'), 'no field: the title shows the name');
      Assert.isNull(TimeDriveSetupController.oneField(null));

      // A subtitle keeps two, with the timeline's dot between them.
      Assert.areEqual(
        '{Owner.Name} · {What.Name}',
        TimeDriveSetupController.subtitleFields('{Owner.Name} · {What.Name}')
      );
      Assert.areEqual('{Status}', TimeDriveSetupController.subtitleFields('{Status}'), 'one is fine');
      Assert.areEqual(
        '{Status} · {Priority}',
        TimeDriveSetupController.subtitleFields('{Status} and {Priority} then {Type}'),
        'the first two, words gone'
      );
      Assert.isNull(TimeDriveSetupController.subtitleFields('Nothing here'));
      Assert.isNull(TimeDriveSetupController.subtitleFields(null));
    }
  }

  @IsTest
  static void leavesDataCloudProfileObjectsOut() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // No DMOs in a test: two objects that describe stand in, one of them a Profile object.
      TimeDriveSetupController.testDmoNames = new List<String>{ 'Contact', 'Account' };
      TimeDriveData360Provider.testProfileDmoNames = new Set<String>{ 'account' };
      List<String> offered = new List<String>();
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('dmo', 'Contact', null)) {
        offered.add(o.value);
      }
      Assert.isTrue(offered.contains('Contact'), 'Others are offered as before');
      Assert.isFalse(offered.contains('Account'), 'Profile objects are left out, whatever their case');

      // Contact points are left out too, whichever category Data 360 gives them.
      for (String name : new List<String>{ 'ssot__ContactPointEmail__dlm', 'SSOT__CONTACTPOINTPHONE__DLM' }) {
        Assert.isTrue(TimeDriveSetupController.CONTACT_POINT_DMO.matcher(name).matches(), name);
      }
      for (
        String name : new List<String>{ 'ssot__EmailEngagement__dlm', 'ssot__Campaign__dlm', 'ContactPointNotes__dlm' }
      ) {
        Assert.isFalse(TimeDriveSetupController.CONTACT_POINT_DMO.matcher(name).matches(), name);
      }
    }
  }

  @IsTest
  static void data360StatusSaysWhetherTheAddOnIsThere() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // Ready where the add-on is deployed; where it isn't, a reason says
      // whether the org lacks Data 360 or only the add-on. Either way it holds
      // in any org.
      TimeDriveSetupController.Data360Status status = TimeDriveSetupController.getData360Status();
      Assert.areEqual(TimeDriveData360Provider.addOnInstalled(), status.ready);
      Assert.areEqual(status.ready, status.reason == null);
      if (!status.ready) {
        Assert.isTrue(status.reason.contains('Data 360'), status.reason);
      }

      TimeDriveSetupController.testData360Status = new TimeDriveSetupController.Data360Status(false, 'Not here.');
      Assert.isFalse(TimeDriveSetupController.getData360Status().ready);
      Assert.areEqual('Not here.', TimeDriveSetupController.getData360Status().reason);
    }
  }

  @IsTest
  static void data360SourcesKeepTheirDataSpace() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // Without Data 360 there are none to choose from, and that's no error.
      Assert.isNotNull(TimeDriveSetupController.getDataSpaces());
      TimeDriveSetupController.testDataSpaces = new List<TimeDriveSetupController.Option>{
        new TimeDriveSetupController.Option('default', 'default', null),
        new TimeDriveSetupController.Option('Europe', 'Europe', null)
      };
      Assert.areEqual(2, TimeDriveSetupController.getDataSpaces().size());

      // Saved on the record, and read back for editing.
      TimeDriveConfig.testSources = null;
      TimeDriveConfig.testDetailFields = null;
      String key = TimeDriveSetupController.save(
          '{"label": "Reservations", "kind": "Data 360", "parentObject": "Contact", ' +
          '"objectName": "Reservation__dlm", "dateField": "Booked__c", "dataSpace": "Europe"}'
        )
        .developerName;
      Assert.areEqual('Europe', [SELECT Data_Space__c FROM Time_Drive_Record__c WHERE Key__c = :key].Data_Space__c);
      TimeDriveConfig.reset();
      Assert.areEqual('Europe', TimeDriveSetupController.getSource(key).dataSpace);
    }
  }

  @IsTest
  static void enhancedEmailReadsEmailMessagesInsteadOfEmailTasks() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
        fitted('Emails', 'Contact', null, 'Contact Emails', true),
        fitted('Emails_Every', 'Contact', 'SharedActivities', 'Contact Emails', false),
        fitted('Email_Messages', 'Contact', 'EnhancedEmail', 'Contact Emails', false)
      };
      // Enhanced Email alone: Email Messages, not the email tasks.
      Map<String, Boolean> target = TimeDriveSetupController.targets(new Set<String>{ 'EnhancedEmail' });
      Assert.isTrue(target.get('Email_Messages'));
      Assert.isFalse(target.get('Emails'));
      // With Shared Activities too, each needing one setting: Enhanced Email wins,
      // so emails are never read twice.
      target = TimeDriveSetupController.targets(new Set<String>{ 'EnhancedEmail', 'SharedActivities' });
      Assert.isTrue(target.get('Email_Messages'));
      Assert.isFalse(target.get('Emails_Every'));
      Assert.isFalse(target.get('Emails'));
      // Neither: the email tasks.
      target = TimeDriveSetupController.targets(new Set<String>());
      Assert.isTrue(target.get('Emails'));
      Assert.isFalse(target.get('Email_Messages'));
    }
  }

  @IsTest
  static void theOrgIsCheckedOneThingAtATimeAndEachSaysWhatItMeans() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      List<TimeDriveSetupController.OrgCheck> steps = TimeDriveSetupController.getOrgCheckSteps();
      Assert.areEqual(5, steps.size());
      Assert.areEqual('SharedActivities', steps[0].key);
      // Data 360 isn't asked about: the Data 360 package brings its own sources.
      for (TimeDriveSetupController.OrgCheck step : steps) {
        Assert.areNotEqual('Data360', step.key);
      }

      // An org with Shared Activities, and a source that comes with it.
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
        fitted('Tasks', 'Contact', null, 'Contact Tasks', true),
        fitted('Tasks_Every', 'Contact', 'SharedActivities', 'Contact Tasks', false)
      };
      TimeDriveSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
      TimeDriveSetupController.OrgCheck shared = TimeDriveSetupController.runOrgCheck('SharedActivities');
      Assert.isTrue(shared.present);
      Assert.areEqual('On', shared.found);
      Assert.areEqual('Allow Users to Relate Multiple Contacts to Tasks and Events', shared.setting);
      Assert.areEqual('Setup › Activity Settings', shared.settingWhere);
      Assert.isTrue(shared.meaning.contains('every contact'), shared.meaning);
      Assert.areEqual(new List<String>{ 'Contact Tasks_Every' }, shared.adds);

      TimeDriveSetupController.OrgCheck person = TimeDriveSetupController.runOrgCheck('PersonAccounts');
      Assert.isFalse(person.present);
      Assert.areEqual('Off', person.found);
      Assert.isTrue(person.adds.isEmpty());

      // Einstein Activity Capture is checked in reportsEinsteinActivityCaptureForTheEmailSyncCheck.
      try {
        TimeDriveSetupController.runOrgCheck('NoSuchCheck');
        Assert.fail('An unknown check should say so');
      } catch (AuraHandledException e) {
        Assert.areEqual('There is no check called NoSuchCheck.', e.getMessage());
      }
    }
  }

  @IsTest
  static void eventsLinkThroughEveryContactOnThem() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // Every contact on an event comes with Shared Activities: out of sight
      // where the org doesn't have it.
      TimeDriveSetupController.testFeatures = new Set<String>();
      for (TimeDriveSetupController.Link l : TimeDriveSetupController.getLinks('Contact', 'Event')) {
        Assert.isFalse(l.everyContact, 'hidden without Shared Activities');
      }
      TimeDriveSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
      List<TimeDriveSetupController.Link> links = TimeDriveSetupController.getLinks('Contact', 'Event');
      // Found by its junction: some orgs list EventWhoRelation before it.
      TimeDriveSetupController.Link every;
      for (TimeDriveSetupController.Link l : links) {
        every = every == null && l.junctionObject == 'EventRelation' ? l : every;
      }
      Assert.isNotNull(every, 'every contact on it, through EventRelation');
      Assert.areEqual('RelationId', every.junctionParentField);
      Assert.areEqual('EventId', every.junctionRecordField);
      Assert.areEqual('Contact', every.parentLabel, 'the diagram shows the page, not Calendar');
      Assert.isTrue(every.note.contains('invitees'));
      Boolean who = false;
      for (TimeDriveSetupController.Link l : links) {
        who = who || l.parentField == 'WhoId';
      }
      Assert.isTrue(who, 'the primary contact (WhoId) is still a choice');
    }
  }

  @IsTest
  static void aRelationObjectLeadsToItsRecordThroughItsLookup() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // EventRelation has next to no dates of its own: the wizard follows its
      // Event lookup to the event's fields, one object at a time, so the first
      // list stays short.
      Map<String, TimeDriveSetupController.FieldInfo> byName = new Map<String, TimeDriveSetupController.FieldInfo>();
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('EventRelation')) {
        byName.put(f.name, f);
      }
      for (String name : byName.keySet()) {
        Assert.isFalse(name.contains('.'), 'no related fields in the first list: ' + name);
      }
      TimeDriveSetupController.FieldInfo event = byName.get('EventId');
      Assert.isNotNull(event);
      Assert.areEqual('Event', event.referenceTo, 'the lookup says where it leads');
      Assert.areEqual('Event', event.relationshipName);
      Assert.areEqual('Events', event.referencePlural, 'and what that is called');
      Assert.areEqual('Event', event.referenceLabel);
      // Its own fields are short of dates; the event's are one step in.
      Boolean eventHasStart = false;
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('Event')) {
        eventHasStart = eventHasStart || (f.name == 'StartDateTime' && f.type == 'datetime');
      }
      Assert.isTrue(eventHasStart);
    }
  }

  @IsTest
  static void filesLinkedToTheRecordAreOfferedAsAChoice() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // ContentDocumentLink points at any record by LinkedEntityId: wider than the
      // two objects a direct lookup is otherwise limited to.
      Boolean listed = false;
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('standard', 'Contact', null)) {
        listed = listed || o.value == 'ContentDocumentLink';
      }
      Assert.isTrue(listed, 'files are an object choice for a Contact');
      List<TimeDriveSetupController.Link> links = TimeDriveSetupController.getLinks('Contact', 'ContentDocumentLink');
      Assert.areEqual(1, links.size());
      Assert.areEqual('LinkedEntityId', links[0].parentField);
      Assert.isNull(links[0].junctionObject, 'linked directly');
      Assert.isTrue(links[0].note.contains('Content Document'), links[0].note);
      // The file's own dates are one step in, through its Content Document.
      Boolean toDocument = false;
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('ContentDocumentLink')) {
        toDocument = toDocument || (f.name == 'ContentDocumentId' && f.referenceTo == 'ContentDocument');
        Assert.isFalse(f.name == 'LinkedEntityId' && f.referenceTo != null, 'a lookup to any record is not followed');
      }
      Assert.isTrue(toDocument);
    }
  }

  @IsTest
  static void aRelationObjectIsOfferedAsASourceOfItsOwn() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
      // Where the org links event relations to a Contact (Shared Activities).
      List<TimeDriveSetupController.Link> eventLinks = TimeDriveSetupController.getLinks('Contact', 'Event');
      if (eventLinks.isEmpty() || eventLinks[0].junctionObject != 'EventRelation') {
        return;
      }
      List<TimeDriveSetupController.Link> own = TimeDriveSetupController.getLinks('Contact', 'EventRelation');
      Assert.isFalse(own.isEmpty(), 'EventRelation is a choice of its own');
      Assert.areEqual('RelationId', own[0].parentField);
      Assert.isNull(own[0].junctionObject, 'it is linked directly, by its own lookup');
      Assert.isTrue(own[0].note.contains('Event'), own[0].note);
      Boolean listed = false;
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('standard', 'Contact', null)) {
        listed = listed || o.value == 'EventRelation';
      }
      Assert.isTrue(listed, 'the object list has it');
    }
  }

  @IsTest
  static void aRelationSourceWhoseDateIsItsRecordsOpensThatRecord() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = new TimeDriveSetupController.SourceDraft();
      d.developerName = 'Shared_Events';
      d.label = 'Shared events';
      d.kind = TimeDriveContext.KIND_SALESFORCE;
      d.objectName = 'EventRelation';
      d.parentField = 'RelationId';
      d.dateField = 'Event.StartDateTime';
      Time_Drive_Source__mdt s = d.toRecord();
      Assert.areEqual('EventId', s.Record_Id_Field__c, 'it opens the event');
      d.recordIdField = 'Id';
      Assert.areEqual('Id', d.toRecord().Record_Id_Field__c, 'unless the source says otherwise');
      // A relation read by its own date opens itself, as before.
      d.recordIdField = null;
      d.dateField = 'CreatedDate';
      Assert.isNull(d.toRecord().Record_Id_Field__c);
      // A file always opens its document, dated by whatever.
      d.objectName = 'ContentDocumentLink';
      d.parentField = 'LinkedEntityId';
      d.dateField = 'SystemModstamp';
      Assert.areEqual('ContentDocumentId', d.toRecord().Record_Id_Field__c);
    }
  }

  @IsTest
  static void aHighlightOnARelatedRecordsFieldKeepsItsPath() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      List<Time_Drive_Highlight__mdt> stored = new List<Time_Drive_Highlight__mdt>{
        new Time_Drive_Highlight__mdt(Field__c = 'Event.IsAllDayEvent', Icon__c = 'dot')
      };
      List<TimeDriveHighlights.Rule> rules = TimeDriveHighlights.rulesFor('EventRelation', stored);
      Assert.areEqual(1, rules.size());
      Assert.areEqual('Event.IsAllDayEvent', rules[0].field, 'the query reads it across the relation');
      stored = new List<Time_Drive_Highlight__mdt>{ new Time_Drive_Highlight__mdt(Field__c = 'isalldayevent') };
      Assert.areEqual(
        'IsAllDayEvent',
        TimeDriveHighlights.rulesFor('Event', stored)[0].field,
        'a plain field is as before'
      );
    }
  }

  @IsTest
  static void accountAndPersonAccountPagesLinkTheirOwnWays() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Set<String> forAccounts = new Set<String>();
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('standard', 'Account', null)) {
        forAccounts.add(o.value);
      }
      Assert.isTrue(forAccounts.contains('Case'), 'cases link to an Account');
      Assert.isTrue(forAccounts.contains('Opportunity'));

      // A person account links by its Account lookups and its Contact ones.
      Set<String> fields = new Set<String>();
      for (TimeDriveSetupController.Link l : TimeDriveSetupController.getLinks('PersonAccount', 'Case')) {
        fields.add(l.parentField);
      }
      Assert.isTrue(fields.contains('AccountId'), String.valueOf(fields));
      Assert.isTrue(fields.contains('ContactId'), String.valueOf(fields));
      // Tasks: Related To (the Account side), Name (the Contact side), and
      // Account, which Salesforce fills from either; never "Name is this Account".
      Map<String, TimeDriveSetupController.Link> taskLinks = new Map<String, TimeDriveSetupController.Link>();
      for (TimeDriveSetupController.Link l : TimeDriveSetupController.getLinks('PersonAccount', 'Task')) {
        if (l.junctionObject == null) {
          Assert.isFalse(taskLinks.containsKey(l.parentField), 'one link per field: ' + l.parentField);
          taskLinks.put(l.parentField, l);
        }
      }
      Assert.isTrue(taskLinks.containsKey('WhatId'), String.valueOf(taskLinks.keySet()));
      Assert.isTrue(taskLinks.get('WhatId').label.contains('person account'));
      Assert.isTrue(taskLinks.get('WhoId').label.contains('person (their Contact)'));
      Assert.isTrue(taskLinks.get('AccountId').note.contains('either way'));
      Boolean tasks = false;
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getObjects('standard', 'PersonAccount', null)) {
        tasks = tasks || o.value == 'Task';
      }
      Assert.isTrue(tasks, 'tasks link to the person through WhoId');
    }
  }

  @IsTest
  static void describesFieldsWithPicklistValues() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.FieldInfo status;
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('Task')) {
        if (f.name == 'Status') {
          status = f;
        }
      }
      Assert.isNotNull(status);
      Assert.areEqual('picklist', status.type);
      Assert.isFalse(status.values.isEmpty());
      // Lookups say where they lead, so the wizard can follow them.
      TimeDriveSetupController.FieldInfo account;
      for (TimeDriveSetupController.FieldInfo f : TimeDriveSetupController.getFields('Contact')) {
        if (f.name == 'AccountId') {
          account = f;
        }
      }
      Assert.areEqual('Account', account.referenceTo);
      Assert.areEqual('Account', account.relationshipName);
      try {
        TimeDriveSetupController.getFields('No_Such_Object__c');
        Assert.fail('A missing object should say so');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('No_Such_Object__c'));
      }
    }
  }

  @IsTest
  static void previewPlotsADraftForARecord() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Id customer = [SELECT Id FROM Contact LIMIT 1].Id;
      TimeDriveSetupController.SourceDraft d = orderDraft();
      TimeDriveSetupController.Preview all = TimeDriveSetupController.preview(JSON.serialize(d), customer);
      Assert.areEqual(2, all.total);
      Assert.isTrue(all.events[0].title.startsWith('Order '));

      d.conditions.add(condition('Status', 'equals', 'Completed', 'text'));
      TimeDriveSetupController.Preview delivered = TimeDriveSetupController.preview(JSON.serialize(d), customer);
      Assert.areEqual(1, delivered.total);
      Assert.areEqual(0, TimeDriveSetupController.preview(JSON.serialize(d), null).total);
    }
  }

  @IsTest
  static void previewSaysWhenADraftCantBeRead() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Id customer = [SELECT Id FROM Contact LIMIT 1].Id;
      TimeDriveSetupController.SourceDraft d = orderDraft();
      d.filter = 'Not_A_Field__c = 1';
      TimeDriveSetupController.Preview p = TimeDriveSetupController.preview(JSON.serialize(d), customer);
      Assert.areEqual(0, p.total);
      Assert.isFalse(p.problems.isEmpty(), 'A broken filter is a problem, not an error');
    }
  }

  @IsTest
  static void countsTheRecordsEachRangeWouldRead() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.Volume v = TimeDriveSetupController.getVolumes(JSON.serialize(orderDraft()));
      Assert.areEqual(2, v.total);
      Assert.areEqual(1, v.parents, 'Both orders are one Contact\'s');
      Assert.areEqual(5, v.ranges.size());
      Assert.areEqual(2, v.ranges[0].count, 'Both orders are in the last 3 months');

      TimeDriveSetupController.SourceDraft delivered = orderDraft();
      delivered.conditions.add(condition('Status', 'equals', 'Completed', 'text'));
      Assert.areEqual(1, TimeDriveSetupController.getVolumes(JSON.serialize(delivered)).total);

      TimeDriveSetupController.SourceDraft apex = new TimeDriveSetupController.SourceDraft();
      apex.kind = 'Apex';
      Assert.isNull(TimeDriveSetupController.getVolumes(JSON.serialize(apex)).total);
    }
  }

  @IsTest
  static void aSourceCanLookBackLessFarThanTheTimeline() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Id customer = [SELECT Id FROM Contact LIMIT 1].Id;
      TimeDriveSetupController.SourceDraft d = orderDraft();
      d.historyMonths = 0;
      // Both orders are due in the past (done or not, a task is on its due date): no history, none.
      Assert.areEqual(0, TimeDriveSetupController.preview(JSON.serialize(d), customer).total);
      d.historyMonths = 1;
      Assert.areEqual(2, TimeDriveSetupController.preview(JSON.serialize(d), customer).total);
    }
  }

  @IsTest
  static void conditionsBecomeSafeFilters() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = new TimeDriveSetupController.SourceDraft();
      d.conditions.add(condition('Status__c', 'notEquals', 'O\'Brien', 'text'));
      d.conditions.add(condition('IsWon', 'equals', 'true', 'boolean'));
      d.conditions.add(condition('Amount', 'greater', '10.5', 'number'));
      d.conditions.add(condition('CloseDate', 'less', '2026-01-31', 'date'));
      d.conditions.add(condition('CreatedDate', 'greater', '2026-01-31', 'datetime'));
      d.conditions.add(condition('Name', 'contains', '50%', 'text'));
      d.conditions.add(condition('Email', 'blank', null, 'text'));
      d.conditions.add(condition('Bad field; DELETE', 'equals', 'x', 'text'));
      d.conditions.add(condition('Amount', 'greater', '1 OR Id != null', 'number'));
      Assert.areEqual(
        'Status__c != \'O\\\'Brien\' AND IsWon = true AND Amount > 10.5 AND CloseDate < 2026-01-31' +
          ' AND CreatedDate > 2026-01-31T00:00:00Z AND Name LIKE \'%50\\%%\' AND Email = null' +
          ' AND Amount > \'1 OR Id != null\'',
        d.filterText()
      );
      d.conditions.clear();
      d.filter = 'IsClosed = true';
      Assert.areEqual('IsClosed = true', d.filterText());
    }
  }

  // A source saved for real, as the admin's own record.
  static String saved(String label) {
    TimeDriveConfig.testSources = null;
    TimeDriveConfig.testDetailFields = null;
    TimeDriveSetupController.SourceDraft d = orderDraft();
    d.label = label;
    return TimeDriveSetupController.save(JSON.serialize(d)).developerName;
  }

  @IsTest
  static void savesANewSourceUnderAFreshName() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      TimeDriveConfig.testDetailFields = null;
      TimeDriveSetupController.SourceDraft d = orderDraft();
      TimeDriveSetupController.DetailDraft detail = new TimeDriveSetupController.DetailDraft();
      detail.field = 'Description';
      detail.label = 'Notes';
      detail.format = 'Text';
      d.details.add(detail);
      d.active = true;
      TimeDriveSetupController.SaveTicket ticket = TimeDriveSetupController.save(JSON.serialize(d));
      Assert.areEqual('Orders_from_setup', ticket.developerName);

      Time_Drive_Record__c r = [
        SELECT
          Name,
          Active__c,
          Object_Name__c,
          Parent_Field__c,
          Detail_1_Field__c,
          Detail_1_Label__c,
          Time_Drive__r.Parent_Object__c
        FROM Time_Drive_Record__c
        WHERE Key__c = 'Orders_from_setup'
      ];
      Assert.areEqual('Orders from setup', r.Name);
      Assert.areEqual('Task', r.Object_Name__c);
      Assert.areEqual('WhoId', r.Parent_Field__c);
      Assert.areEqual('Description', r.Detail_1_Field__c);
      Assert.areEqual('Notes', r.Detail_1_Label__c);
      Assert.areEqual('Contact', r.Time_Drive__r.Parent_Object__c, 'It sits under its record page\'s Time Drive');

      // The timeline reads it back as a source, with its detail field.
      TimeDriveConfig.reset();
      Assert.areEqual(1, TimeDriveConfig.sources('Contact').size());
      Assert.areEqual(1, TimeDriveConfig.detailFields('Orders_from_setup').size());

      // Saving it again edits it, under the same Time Drive.
      d.developerName = ticket.developerName;
      d.title = 'Order again {Status}';
      TimeDriveSetupController.save(JSON.serialize(d));
      Assert.areEqual(1, [SELECT COUNT() FROM Time_Drive_Record__c]);
      Assert.areEqual(1, [SELECT COUNT() FROM Time_Drive__c]);

      // A detail taken out is cleared, not left behind in its old slot.
      d.details.clear();
      TimeDriveSetupController.save(JSON.serialize(d));
      Time_Drive_Record__c cleared = [
        SELECT Detail_1_Field__c, Detail_1_Label__c, Highlight_Field__c
        FROM Time_Drive_Record__c
        WHERE Key__c = 'Orders_from_setup'
      ];
      Assert.isNull(cleared.Detail_1_Field__c, 'The removed detail is gone');
      Assert.isNull(cleared.Detail_1_Label__c);
      Assert.isNull(cleared.Highlight_Field__c);
      TimeDriveConfig.reset();
      Assert.areEqual(0, TimeDriveConfig.detailFields('Orders_from_setup').size());

      Assert.areEqual('Orders_from_setup_2', TimeDriveSetupController.uniqueName('Orders from setup'));
      Assert.areEqual('Source_2026_orders', TimeDriveSetupController.uniqueName('2026 orders!'));
    }
  }

  @IsTest
  static void aSourceKeepsAtMostFourDetailFields() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      TimeDriveConfig.testDetailFields = null;
      TimeDriveSetupController.SourceDraft d = orderDraft();
      for (String field : new List<String>{ 'Description', 'Status', 'Name', 'Type', 'Phone' }) {
        TimeDriveSetupController.DetailDraft detail = new TimeDriveSetupController.DetailDraft();
        detail.field = field;
        d.details.add(detail);
      }
      String key = TimeDriveSetupController.save(JSON.serialize(d)).developerName;
      Time_Drive_Record__c saved = [
        SELECT Detail_1_Field__c, Detail_4_Field__c
        FROM Time_Drive_Record__c
        WHERE Key__c = :key
      ];
      Assert.areEqual('Description', saved.Detail_1_Field__c);
      Assert.areEqual('Type', saved.Detail_4_Field__c, 'the fifth has no slot');
      TimeDriveConfig.reset();
      List<TimeDriveSetupController.DetailDraft> back = TimeDriveSetupController.getSource(key).details;
      Assert.areEqual(4, back.size());
      Assert.areEqual('Type', back[3].field);
    }
  }

  @IsTest
  static void aSourceKeepsOneHighlightAndItRoundTrips() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      TimeDriveConfig.testDetailFields = null;
      TimeDriveSetupController.SourceDraft d = orderDraft();
      // Without a field a highlight is no highlight, even first.
      d.highlights.add(new TimeDriveSetupController.HighlightDraft());
      for (String field : new List<String>{ 'IsHighPriority', 'IsClosed' }) {
        TimeDriveSetupController.HighlightDraft h = new TimeDriveSetupController.HighlightDraft();
        h.field = field;
        h.icon = 'utility:flag';
        h.colour = '#C23934';
        d.highlights.add(h);
      }
      String key = TimeDriveSetupController.save(JSON.serialize(d)).developerName;
      Time_Drive_Record__c saved = [
        SELECT Highlight_Field__c, Highlight_Icon__c, Highlight_Colour__c
        FROM Time_Drive_Record__c
        WHERE Key__c = :key
      ];
      Assert.areEqual('IsHighPriority', saved.Highlight_Field__c, 'the first with a field is kept');
      TimeDriveConfig.reset();
      List<TimeDriveSetupController.HighlightDraft> back = TimeDriveSetupController.getSource(key).highlights;
      Assert.areEqual(1, back.size());
      Assert.areEqual('IsHighPriority', back[0].field);
      Assert.areEqual('utility:flag', back[0].icon);
      Assert.areEqual('#C23934', back[0].colour);
    }
  }

  @IsTest
  static void savingPlacesTheSourceInItsLegendOrder() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = orderDraft();
      // New at the top, then the two order sources (sequence 10 and 11 now).
      d.legendOrder = new List<String>{ TimeDriveSetupController.THIS_SOURCE, 'Order_Placed', 'Order_Delivered' };
      List<Time_Drive_Record__c> moved = TimeDriveSetupController.reordered(d);
      Assert.areEqual(10, d.sequence);
      Assert.areEqual(2, moved.size(), 'both move down a place');
      Assert.areEqual('Order_Placed', moved[0].Key__c);
      Assert.areEqual(20, moved[0].Sequence__c);

      // A source already in its place isn't saved again; no order, no change.
      d.legendOrder = new List<String>{ 'Order_Placed', TimeDriveSetupController.THIS_SOURCE };
      Assert.areEqual(0, TimeDriveSetupController.reordered(d).size());
      Assert.areEqual(20, d.sequence);
      d.legendOrder = null;
      Assert.areEqual(0, TimeDriveSetupController.reordered(d).size());
    }
  }

  @IsTest
  static void saveSaysWhatIsMissing() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = new TimeDriveSetupController.SourceDraft();
      d.kind = 'Salesforce';
      try {
        TimeDriveSetupController.save(JSON.serialize(d));
        Assert.fail('An empty draft should not save');
      } catch (AuraHandledException e) {
        Assert.areEqual('Before saving, choose a name, an object, a date, how it links to the record.', e.getMessage());
      }
      d.kind = 'Apex';
      d.label = 'Mine';
      try {
        TimeDriveSetupController.save(JSON.serialize(d));
        Assert.fail('An Apex source needs a class');
      } catch (AuraHandledException e) {
        Assert.areEqual('Before saving, choose an Apex class.', e.getMessage());
      }
    }
  }

  @IsTest
  static void aSourceIsSwitchedOnAndOffAndRemovedStraightAway() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      String key = saved('Switched');
      Assert.areEqual(key, TimeDriveSetupController.setActive(key, false).developerName);
      Assert.isFalse([SELECT Active__c FROM Time_Drive_Record__c WHERE Key__c = :key].Active__c);
      TimeDriveSetupController.setActive(key, true);
      Assert.isTrue([SELECT Active__c FROM Time_Drive_Record__c WHERE Key__c = :key].Active__c);
      Assert.areEqual(key, TimeDriveSetupController.remove(key).developerName);
      Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Record__c WHERE Key__c = :key], 'Removing deletes it');
      // A source that isn't there says so, whichever way it is changed.
      for (Integer i = 0; i < 2; i++) {
        try {
          if (i == 0) {
            TimeDriveSetupController.setActive('No_Such_Source', true);
          } else {
            TimeDriveSetupController.remove('No_Such_Source');
          }
          Assert.fail('A missing source should say so');
        } catch (AuraHandledException e) {
          Assert.areEqual('That source no longer exists.', e.getMessage());
        }
      }
    }
  }

  @IsTest
  static void aSourceIsInSeveralLensesOrNoneAndTheyAreReadBack() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // How a source's lenses are read: its Lenses, else its Category as the one lens.
      Assert.areEqual(
        new List<String>{ 'Sales', 'Service' },
        TimeDriveConfig.lensesOf(
          new Time_Drive_Source__mdt(Lenses__c = ' Sales; Service ;Sales', Category__c = 'Digital')
        )
      );
      Assert.areEqual(
        new List<String>{ 'Digital' },
        TimeDriveConfig.lensesOf(new Time_Drive_Source__mdt(Category__c = 'Digital'))
      );
      Assert.isTrue(TimeDriveConfig.lensesOf(new Time_Drive_Source__mdt()).isEmpty());
      Assert.areEqual(
        'Sales;Service',
        TimeDriveConfig.lensKey(new Time_Drive_Source__mdt(Lenses__c = 'Sales;Service'))
      );
      Assert.isNull(TimeDriveConfig.lensKey(new Time_Drive_Source__mdt()));

      String key = saved('In lenses');
      // Into lenses that exist: the lenses are kept in order, once each.
      TimeDriveSetupController.SaveTicket ticket = TimeDriveSetupController.setLenses(
        key,
        new List<String>{ 'Sales', 'Service', 'Sales' }
      );
      Assert.areEqual(key, ticket.developerName);
      Assert.areEqual('Sales;Service', [SELECT Lenses__c FROM Time_Drive_Record__c WHERE Key__c = :key].Lenses__c);
      TimeDriveConfig.reset();
      TimeDriveSetupController.SourceSummary summary;
      for (TimeDriveSetupController.SourceSummary s : TimeDriveSetupController.getSources()) {
        summary = s.developerName == key ? s : summary;
      }
      Assert.areEqual(new List<String>{ 'Sales', 'Service' }, summary.lenses);
      Assert.areEqual('Sales', summary.category, 'the first is the one the wizard shows');
      // The wizard saving it with that first lens leaves the others alone.
      TimeDriveSetupController.SourceDraft d = TimeDriveSetupController.getSource(key);
      d.title = 'Changed {Status}';
      TimeDriveSetupController.save(JSON.serialize(d));
      Assert.areEqual('Sales;Service', [SELECT Lenses__c FROM Time_Drive_Record__c WHERE Key__c = :key].Lenses__c);
      // Out of them all, with none.
      TimeDriveSetupController.setLenses(key, new List<String>());
      Assert.isNull([SELECT Lenses__c FROM Time_Drive_Record__c WHERE Key__c = :key].Lenses__c);
      // All is a lens like the others.
      TimeDriveSetupController.setLenses(key, new List<String>{ TimeDriveConfig.ALL_VIEW, 'Service' });
      Assert.areEqual('All;Service', [SELECT Lenses__c FROM Time_Drive_Record__c WHERE Key__c = :key].Lenses__c);
      // A lens that isn't one, or a source that isn't there.
      try {
        TimeDriveSetupController.setLenses(key, new List<String>{ 'NoSuchLens' });
        Assert.fail('NoSuchLens is not a lens to put a source in');
      } catch (AuraHandledException e) {
        Assert.areEqual('There is no lens called NoSuchLens.', e.getMessage());
      }
      try {
        TimeDriveSetupController.setLenses('No_Such_Source', new List<String>{ 'Sales' });
        Assert.fail('A missing source should say so');
      } catch (AuraHandledException e) {
        Assert.areEqual('That source no longer exists.', e.getMessage());
      }
    }
  }

  @IsTest
  static void readyMadeSourcesAreCopiedAsTheAdminsOwn() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      List<TimeDriveSetupController.TemplateOption> offered = TimeDriveSetupController.getTemplates('Contact');
      Assert.isFalse(offered.isEmpty(), 'The shipped templates are offered');
      TimeDriveSetupController.TemplateOption first = offered[0];
      Assert.isFalse(first.added);
      Assert.isNotNull(TimeDriveSetupController.useTemplate(first.key).developerName);
      Time_Drive_Record__c copy = [
        SELECT Template_Key__c, Active__c
        FROM Time_Drive_Record__c
        WHERE Template_Key__c = :first.key
      ];
      Assert.isTrue(copy.Active__c);
      Assert.isTrue(
        TimeDriveConfig.lensesOf(
            TimeDriveConfig.source([SELECT Key__c FROM Time_Drive_Record__c WHERE Template_Key__c = :first.key].Key__c)
          )
          .contains(TimeDriveConfig.ALL_VIEW),
        'A template\'s copy starts in All'
      );
      try {
        TimeDriveSetupController.useTemplate(first.key);
        Assert.fail('A template is added once');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('already added'));
      }
      // The rest in one go; a second go has nothing left to add.
      TimeDriveSetupController.QuickStartResult rest = TimeDriveSetupController.quickStart('Contact');
      Assert.areEqual(offered.size() - 1, rest.added.size());
      Assert.isTrue(rest.switched.isEmpty(), 'Nothing to switch: one variant of each');
      TimeDriveSetupController.QuickStartResult again = TimeDriveSetupController.quickStart('Contact');
      Assert.isTrue(again.added.isEmpty() && again.switched.isEmpty(), 'A second go changes nothing');
      Assert.isTrue(TimeDriveConfig.sources('Contact').size() > 0, 'They are on the timeline now');
    }
  }

  @IsTest
  static void leadPagesGetTheirActivitiesFilesAndCampaigns() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      TimeDriveSetupController.testFeatures = new Set<String>();
      TimeDriveSetupController.QuickStartResult first = TimeDriveSetupController.quickStart('Lead');
      Assert.areEqual(
        new Set<String>{
          'Lead_Tasks',
          // Its overdue ones too, in the Overdue lens.
          'Lead_Overdue_Tasks',
          'Lead_Calls',
          'Lead_Emails',
          'Lead_Events',
          'Lead_Files',
          'Lead_Campaign_Members'
        },
        templateKeys(first.added)
      );
      // With Shared Activities, every lead's variant of each takes over.
      TimeDriveSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
      TimeDriveSetupController.QuickStartResult shared = TimeDriveSetupController.quickStart('Lead');
      Assert.areEqual(
        new Set<String>{
          'Lead_Tasks_Shared',
          'Lead_Overdue_Tasks_Shared',
          'Lead_Calls_Shared',
          'Lead_Emails_Shared',
          'Lead_Events_Shared'
        },
        templateKeys(shared.added)
      );
      Assert.isFalse(copyActive('Lead_Tasks'));
      Assert.isTrue(copyActive('Lead_Tasks_Shared'));
      Assert.isFalse(copyActive('Lead_Overdue_Tasks'), 'the overdue ones switch variant too');
      Assert.isTrue(copyActive('Lead_Overdue_Tasks_Shared'));
      Assert.isTrue(copyActive('Lead_Files'), 'Files have no variant');

      // Back by name, and a lead's timeline plots its task, file and campaign.
      TimeDriveSetupController.testFeatures = new Set<String>();
      TimeDriveSetupController.quickStart('Lead');
      Lead prospect = new Lead(LastName = 'Okafor', Company = 'Okafor Ltd');
      Campaign launch = new Campaign(Name = 'Spring launch', IsActive = true);
      if (!TimeDriveTestData.tryInsert(new List<SObject>{ prospect, launch })) {
        return;
      }
      // Each is asserted when the org let it be made (automation can refuse one).
      Boolean taskMade = TimeDriveTestData.tryInsert(
        new Task(WhoId = prospect.Id, Subject = 'Call the lead', ActivityDate = Date.today())
      );
      Boolean fileMade = TimeDriveTestData.tryInsert(
        new ContentVersion(
          Title = 'Brochure',
          PathOnClient = 'brochure.txt',
          VersionData = Blob.valueOf('Spring range'),
          FirstPublishLocationId = prospect.Id
        )
      );
      Boolean memberMade = TimeDriveTestData.tryInsert(
        new CampaignMember(CampaignId = launch.Id, LeadId = prospect.Id, Status = 'Sent')
      );
      Integer expected = (taskMade ? 1 : 0) + (fileMade ? 1 : 0) + (memberMade ? 1 : 0);
      TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(prospect.Id, null, null, null, null);
      Assert.areEqual(expected, summary.total, String.join(summary.warnings, ' | '));
      Map<String, TimeDriveController.EngagementEvent> byType = new Map<String, TimeDriveController.EngagementEvent>();
      for (
        TimeDriveController.EngagementEvent e : TimeDriveController.getPageDays(
          prospect.Id,
          null,
          null,
          null,
          null,
          new List<String>{ Datetime.now().format('yyyy-MM-dd') },
          new List<String>(),
          null,
          null,
          null
        )
      ) {
        byType.put(e.type, e);
      }
      if (fileMade) {
        Assert.isTrue(byType.containsKey('file'), 'the lead\'s file is plotted');
        Assert.areEqual('Brochure', byType.get('file').title);
        Assert.areEqual(
          ContentDocument.SObjectType,
          byType.get('file').recordId.getSObjectType(),
          'a file opens its document'
        );
      }
      if (memberMade) {
        Assert.isTrue(byType.containsKey('campaign_member'), 'the lead\'s campaign is plotted');
        Assert.areEqual('Spring launch', byType.get('campaign_member').title);
        Assert.areEqual(launch.Id, byType.get('campaign_member').recordId, 'a membership opens its campaign');
      }
    }
  }

  @IsTest
  static void contactPagesGetTheirFilesAndCampaigns() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      TimeDriveSetupController.testFeatures = new Set<String>();
      Set<String> added = templateKeys(TimeDriveSetupController.quickStart('Contact').added);
      Assert.isTrue(
        added.containsAll(new Set<String>{ 'Contact_Files', 'Contact_Campaign_Members' }),
        String.valueOf(added)
      );

      Contact member = new Contact(LastName = 'Ngata');
      Campaign launch = new Campaign(Name = 'Spring launch', IsActive = true);
      if (
        !TimeDriveTestData.tryInsert(new List<SObject>{ member, launch }) ||
        !TimeDriveTestData.tryInsert(new CampaignMember(CampaignId = launch.Id, ContactId = member.Id, Status = 'Sent'))
      ) {
        return;
      }
      TimeDriveController.EngagementEvent joined;
      for (
        TimeDriveController.EngagementEvent e : TimeDriveController.getPageDays(
          member.Id,
          null,
          null,
          null,
          null,
          new List<String>{ Datetime.now().format('yyyy-MM-dd') },
          new List<String>(),
          null,
          null,
          null
        )
      ) {
        joined = e.type == 'campaign_member' ? e : joined;
      }
      Assert.isNotNull(joined, 'the contact\'s campaign is plotted');
      Assert.areEqual('Spring launch', joined.title);
      Assert.areEqual(launch.Id, joined.recordId, 'a membership opens its campaign');
    }
  }

  @IsTest
  static void checkingAgainSwitchesToTheVariantThatFitsNow() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      // First check: no Shared Activities, so Contact Tasks are read by Name.
      TimeDriveSetupController.testFeatures = new Set<String>();
      TimeDriveSetupController.QuickStartResult first = TimeDriveSetupController.quickStart('Contact');
      Assert.isTrue(templateKeys(first.added).contains('Contact_Tasks'));
      Assert.isTrue(first.switched.isEmpty());

      // Shared Activities is turned on: every contact's variant takes over, and the first is kept, switched off.
      TimeDriveSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
      TimeDriveSetupController.QuickStartResult second = TimeDriveSetupController.quickStart('Contact');
      Assert.isTrue(templateKeys(second.added).contains('Contact_Tasks_Shared'));
      TimeDriveSetupController.VariantSwitch tasks = switchTo(second, 'Tasks (every contact)');
      Assert.isNotNull(tasks, 'The switch is reported');
      Assert.areEqual('Tasks', tasks.offLabel);
      Assert.areEqual('Contact', tasks.parentObject);
      Assert.isFalse(copyActive('Contact_Tasks'), 'The variant by Name is switched off');
      Assert.isTrue(copyActive('Contact_Tasks_Shared'), 'Only the variant that fits plots the tasks');

      // Checking again changes nothing.
      TimeDriveSetupController.QuickStartResult third = TimeDriveSetupController.quickStart('Contact');
      Assert.isTrue(third.added.isEmpty() && third.switched.isEmpty());

      // Back without Shared Activities: the first copy is switched on again, not added a second time.
      TimeDriveSetupController.testFeatures = new Set<String>();
      TimeDriveSetupController.QuickStartResult fourth = TimeDriveSetupController.quickStart('Contact');
      Assert.isFalse(templateKeys(fourth.added).contains('Contact_Tasks'));
      Assert.isNotNull(switchTo(fourth, 'Tasks'));
      Assert.isTrue(copyActive('Contact_Tasks'));
      Assert.isFalse(copyActive('Contact_Tasks_Shared'));
      Assert.areEqual(1, [SELECT COUNT() FROM Time_Drive_Record__c WHERE Template_Key__c = 'Contact_Tasks']);
    }
  }

  @IsTest
  static void checkingLeavesAGroupTheAdminSwitchedOffAndMendsDoubles() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testSources = null;
      TimeDriveSetupController.testFeatures = new Set<String>();
      TimeDriveSetupController.quickStart('Contact');
      TimeDriveSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
      TimeDriveSetupController.quickStart('Contact');

      // Both variants on (as an older check could leave them): checking switches one off.
      switchOn('Contact_Tasks', true);
      switchOn('Contact_Tasks_Shared', true);
      TimeDriveSetupController.QuickStartResult mended = TimeDriveSetupController.quickStart('Contact');
      Assert.isNotNull(switchTo(mended, 'Tasks (every contact)'));
      Assert.isFalse(copyActive('Contact_Tasks'));
      Assert.isTrue(copyActive('Contact_Tasks_Shared'));

      // The admin switches Contact Tasks off altogether: checking leaves it off.
      switchOn('Contact_Tasks_Shared', false);
      TimeDriveSetupController.QuickStartResult after = TimeDriveSetupController.quickStart('Contact');
      Assert.isNull(switchTo(after, 'Tasks (every contact)'));
      Assert.isFalse(copyActive('Contact_Tasks'));
      Assert.isFalse(copyActive('Contact_Tasks_Shared'));
    }
  }

  private static Set<String> templateKeys(List<TimeDriveSetupController.TemplateOption> options) {
    Set<String> out = new Set<String>();
    for (TimeDriveSetupController.TemplateOption o : options) {
      out.add(o.key);
    }
    return out;
  }

  private static TimeDriveSetupController.VariantSwitch switchTo(
    TimeDriveSetupController.QuickStartResult result,
    String onLabel
  ) {
    for (TimeDriveSetupController.VariantSwitch s : result.switched) {
      if (s.onLabel == onLabel && s.parentObject == 'Contact') {
        return s;
      }
    }
    return null;
  }

  private static Time_Drive_Record__c copyOfTemplate(String templateKey) {
    return [SELECT Key__c, Active__c FROM Time_Drive_Record__c WHERE Template_Key__c = :templateKey LIMIT 1];
  }

  private static Boolean copyActive(String templateKey) {
    return copyOfTemplate(templateKey).Active__c;
  }

  private static void switchOn(String templateKey, Boolean active) {
    TimeDriveSetupController.setActive(copyOfTemplate(templateKey).Key__c, active);
  }

  @IsTest
  static void findsApexProviders() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Set<String> names = new Set<String>();
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getApexProviders()) {
        names.add(o.value);
      }
      Assert.isFalse(names.contains('TimeDriveSoqlProvider'), 'Built-in providers need no class');
      // Listed by its name; once packaged, its value carries the namespace (ns.TimeDriveOpportunityProducts).
      Boolean products = false;
      for (TimeDriveSetupController.Option o : TimeDriveSetupController.getApexProviders()) {
        products = products || o.label == 'TimeDriveOpportunityProducts';
      }
      Assert.isTrue(products, 'Setup lists the opportunity products among the Apex sources');
    }
  }

  @IsTest
  static void conditionsRoundTripThroughTheFilterText() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = orderDraft();
      d.conditions = new List<TimeDriveSetupController.Condition>();
      d.conditions.add(condition('Status', 'notEquals', 'Can\'t be 100%', 'text'));
      d.conditions.add(condition('Subject', 'contains', 'order_1', 'text'));
      d.conditions.add(condition('IsClosed', 'equals', 'true', 'boolean'));
      d.conditions.add(condition('Priority', 'blank', '', 'text'));
      d.conditions.add(condition('ActivityDate', 'greater', '2026-01-31', 'date'));
      d.conditions.add(condition('CreatedDate', 'less', '2026-02-01', 'datetime'));
      d.conditions.add(condition('Amount', 'equals', '12.5', 'number'));
      String text = d.filterText();

      List<TimeDriveSetupController.Condition> back = TimeDriveSetupController.conditionsOf(text);
      Assert.areEqual(7, back.size());
      TimeDriveSetupController.SourceDraft again = orderDraft();
      again.conditions = back;
      Assert.areEqual(text, again.filterText(), 'The conditions write the same filter');
      Assert.areEqual('Can\'t be 100%', back[0].value);
      Assert.areEqual('order_1', back[1].value);
      Assert.areEqual('2026-02-01', back[5].value);
    }
  }

  @IsTest
  static void anyOfTheConditionsAndOneOfAListRoundTrip() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveSetupController.SourceDraft d = orderDraft();
      d.match = 'any';
      TimeDriveSetupController.Condition statuses = condition('Status', 'oneOf', '', 'text');
      statuses.values = new List<String>{ 'Closed', 'Can\'t fix' };
      TimeDriveSetupController.Condition priorities = condition('Priority', 'notOneOf', '', 'text');
      priorities.values = new List<String>{ 'Low' };
      d.conditions = new List<TimeDriveSetupController.Condition>{
        statuses,
        priorities,
        condition('Subject', 'contains', 'order', 'text')
      };
      String text = d.filterText();
      Assert.areEqual(
        'Status IN (\'Closed\', \'Can\\\'t fix\') OR Priority NOT IN (\'Low\') OR Subject LIKE \'%order%\'',
        text
      );

      TimeDriveSetupController.FilterParts back = TimeDriveSetupController.filterParts(text);
      Assert.areEqual('any', back.match);
      Assert.areEqual(3, back.conditions.size());
      Assert.areEqual('oneOf', back.conditions[0].operator);
      Assert.areEqual(new List<String>{ 'Closed', 'Can\'t fix' }, back.conditions[0].values);
      Assert.areEqual('notOneOf', back.conditions[1].operator);
      TimeDriveSetupController.SourceDraft again = orderDraft();
      again.match = back.match;
      again.conditions = back.conditions;
      Assert.areEqual(text, again.filterText(), 'The conditions write the same filter');

      // A list with nothing chosen writes nothing; all is the default.
      statuses.values = new List<String>();
      d.match = null;
      d.conditions = new List<TimeDriveSetupController.Condition>{
        statuses,
        condition('IsClosed', 'equals', 'true', 'boolean')
      };
      Assert.areEqual('IsClosed = true', d.filterText());
    }
  }

  @IsTest
  static void aFilterTheBuilderCannotShowIsKeptAsText() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      for (
        String text : new List<String>{
          'Status = \'Open\' AND Name = \'A\' OR Name = \'B\'',
          'NOT Status = \'Open\'',
          'Id IN (SELECT WhoId FROM Task)',
          'Name IN (\'A\', 3)',
          'Status = \'it\' AND OR'
        }
      ) {
        Assert.isNull(TimeDriveSetupController.conditionsOf(text), text);
      }
      Assert.isNull(TimeDriveSetupController.conditionsOf(null));
      Assert.areEqual(1, TimeDriveSetupController.conditionsOf('Status = \'A AND B\'').size(), 'AND inside a value');
      // What it can now show: OR, a list, and brackets around the whole filter.
      TimeDriveSetupController.FilterParts tasks = TimeDriveSetupController.filterParts(
        '(TaskSubtype = null OR TaskSubtype NOT IN (\'Call\', \'Email\', \'ListEmail\'))'
      );
      Assert.areEqual('any', tasks.match);
      Assert.areEqual('blank', tasks.conditions[0].operator);
      Assert.areEqual(new List<String>{ 'Call', 'Email', 'ListEmail' }, tasks.conditions[1].values);
      Assert.areEqual('all', TimeDriveSetupController.filterParts('(Status = \'Open\')').match);
      Assert.areEqual(
        2,
        TimeDriveSetupController.conditionsOf('(A__c = 1) AND (B__c = 2)')?.size() ?? 0,
        'brackets around each part are not the whole'
      );
    }
  }

  @IsTest
  static void recordsTheUserMayNotMakeAreSkippedNotFailed() {
    User admin = TimeDriveTestData.setupAdmin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = admin.Id, UserPermissionsMarketingUser = false);
    }
    System.runAs(admin) {
      // Campaigns need Marketing User: the test that wants one goes without, it doesn't fail.
      Assert.isFalse(TimeDriveTestData.tryInsert(new List<SObject>{ new Campaign(Name = 'Not theirs') }));
      Assert.areEqual(0, [SELECT COUNT() FROM Campaign WHERE Name = 'Not theirs'], 'nothing is kept');
    }
  }

  // Commerce and Digital start switched off: before Setup is first saved they
  // aren't offered, Get started's record keeps them off, and an admin can
  // switch them on.
  @IsTest
  static void commerceAndDigitalStartSwitchedOff() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      TimeDriveConfig.testViews = new List<Time_Drive_View__mdt>{
        new Time_Drive_View__mdt(DeveloperName = 'All', Label = 'All'),
        new Time_Drive_View__mdt(DeveloperName = 'Sales', Label = 'Sales'),
        new Time_Drive_View__mdt(DeveloperName = 'Marketing', Label = 'Marketing'),
        new Time_Drive_View__mdt(DeveloperName = 'Overdue', Label = 'Overdue'),
        new Time_Drive_View__mdt(DeveloperName = 'Commerce', Label = 'Commerce'),
        new Time_Drive_View__mdt(DeveloperName = 'Digital', Label = 'Digital')
      };
      Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Setup__c]);
      Assert.areEqual(new List<String>{ 'All', 'Overdue', 'Marketing', 'Sales' }, offered());

      TimeDriveSetupController.saveProgress(new List<String>{ 'welcome' }, null);
      TimeDriveConfig.forgetHiddenViews();
      Assert.areEqual('Commerce,Digital', [SELECT Hidden_Views__c FROM Time_Drive_Setup__c].Hidden_Views__c);
      Assert.areEqual(new List<String>{ 'All', 'Overdue', 'Marketing', 'Sales' }, offered());

      TimeDriveSetupController.saveViews('[{"developerName":"Commerce","active":true}]');
      Assert.areEqual(
        new List<String>{ 'All', 'Overdue', 'Commerce', 'Marketing', 'Sales' },
        offered(),
        'All, then Overdue, then the rest alphabetically'
      );
    }
  }

  private static List<String> offered() {
    List<String> out = new List<String>();
    for (TimeDriveController.ViewOption v : TimeDriveController.getViews()) {
      out.add(v.value);
    }
    return out;
  }
}
