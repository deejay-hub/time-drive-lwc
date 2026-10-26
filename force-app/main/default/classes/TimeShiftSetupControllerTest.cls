@IsTest
private class TimeShiftSetupControllerTest {
  // The sources the timeline once shipped with, in place of the org's.
  static {
    TimeShiftTestData.useShipped();
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

  static TimeShiftSetupController.SourceDraft orderDraft() {
    TimeShiftSetupController.SourceDraft d = new TimeShiftSetupController.SourceDraft();
    d.label = 'Orders from setup';
    d.kind = 'Salesforce';
    d.parentObject = 'Contact';
    d.objectName = 'Task';
    d.parentField = 'WhoId';
    d.dateField = 'ActivityDate';
    d.title = 'Order {Status}';
    return d;
  }

  static TimeShiftSetupController.Condition condition(String field, String op, String value, String type) {
    TimeShiftSetupController.Condition c = new TimeShiftSetupController.Condition();
    c.field = field;
    c.operator = op;
    c.value = value;
    c.valueType = type;
    return c;
  }

  @IsTest
  static void listsEverySourceInPlainWords() {
    List<TimeShiftSetupController.SourceSummary> sources = TimeShiftSetupController.getSources();
    Assert.areEqual(TimeShiftTestData.sources().size(), sources.size());
    for (TimeShiftSetupController.SourceSummary s : sources) {
      Assert.isTrue(String.isNotBlank(s.summary), s.developerName + ' has no summary');
      Assert.isNotNull(s.kind);
    }
  }

  @IsTest
  static void editsASourceWithItsDetailFields() {
    TimeShiftSetupController.SourceDraft d = TimeShiftSetupController.getSource('Order_Placed');
    Assert.areEqual('Task', d.objectName);
    Assert.areEqual('WhoId', d.parentField);
    Assert.areEqual('Salesforce', d.kind);
    try {
      TimeShiftSetupController.getSource('No_Such_Source');
      Assert.fail('A missing source should say so');
    } catch (AuraHandledException e) {
      Assert.areEqual('That source no longer exists.', e.getMessage());
    }
  }

  @IsTest
  static void offersObjectsByKindWithoutPlumbing() {
    Set<String> standard = new Set<String>();
    for (TimeShiftSetupController.Option o : TimeShiftSetupController.getObjects('standard', 'Contact', null)) {
      standard.add(o.value);
    }
    Assert.isTrue(standard.contains('Case'));
    Assert.isTrue(standard.contains('Opportunity'), 'Opportunities link through OpportunityContactRole');
    Assert.isFalse(standard.contains('Pricebook2'), 'Nothing links a price book to a Contact');
    Assert.isTrue(standard.contains('Event'), 'The calendar Event is a record, not a platform event');
    Assert.isFalse(standard.contains('CaseHistory'));
    Assert.isTrue(standard.contains('Task'), 'tasks link by WhoId');
    // Custom objects are custom (whatever this org has), and never metadata.
    for (TimeShiftSetupController.Option o : TimeShiftSetupController.getObjects('custom', 'Contact', null)) {
      Assert.isTrue(o.value.endsWith('__c'), o.value);
      Assert.isFalse(standard.contains(o.value));
    }
  }

  @IsTest
  static void findsLookupsAndJunctionsToTheContact() {
    Boolean who = false;
    for (TimeShiftSetupController.Link l : TimeShiftSetupController.getLinks('Contact', 'Task')) {
      who |= l.parentField == 'WhoId';
    }
    Assert.isTrue(who, 'Task.WhoId links to the Contact');

    Boolean contactRole = false;
    for (TimeShiftSetupController.Link l : TimeShiftSetupController.getLinks('Contact', 'Opportunity')) {
      contactRole |= l.junctionObject == 'OpportunityContactRole' && l.junctionRecordField == 'OpportunityId';
      Assert.areNotEqual('Attachment', l.junctionObject, 'Polymorphic lookups are not junctions');
    }
    Assert.isTrue(contactRole, 'Opportunities link through OpportunityContactRole');

    // What the diagram draws: the objects and the lookups between them.
    for (TimeShiftSetupController.Link l : TimeShiftSetupController.getLinks('Contact', 'Opportunity')) {
      if (l.junctionObject == 'OpportunityContactRole') {
        Assert.areEqual('Contact', l.parentLabel);
        Assert.areEqual('Opportunity', l.objectLabel);
        Assert.areEqual('Contact ID', l.fieldLabel);
        Assert.areEqual('Opportunity ID', l.recordFieldLabel);
        Assert.isNotNull(l.junctionLabel);
      }
    }
    TimeShiftSetupController.Link task = TimeShiftSetupController.getLinks('Contact', 'Task')[0];
    Assert.areEqual('Task', task.objectLabel);
    Assert.areEqual('Subject', task.objectNameLabel);
    Assert.isFalse(task.masterDetail, 'a Task points at its Contact by a lookup');
  }

  static Time_Shift_Source__mdt fitted(
    String name,
    String page,
    String requires,
    String variantGroup,
    Boolean active
  ) {
    return new Time_Shift_Source__mdt(
      DeveloperName = name,
      Label = name,
      Active__c = active,
      Org_Fit__c = true,
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
    TimeShiftConfig.testViews = new List<Time_Shift_View__mdt>{
      new Time_Shift_View__mdt(
        DeveloperName = 'Service',
        Label = 'Service',
        Menu_Label__c = '$Label.Time_Shift_View_Service',
        Active__c = true,
        Sequence__c = 40
      ),
      new Time_Shift_View__mdt(
        DeveloperName = 'All',
        Label = 'All',
        Menu_Label__c = '$Label.Time_Shift_View_All',
        Sequence__c = 99
      ),
      new Time_Shift_View__mdt(DeveloperName = 'Sales', Label = 'Sales', Active__c = true, Sequence__c = 10),
      new Time_Shift_View__mdt(DeveloperName = 'Digital', Label = 'Digital', Active__c = false, Sequence__c = 30)
    };
    // All first, then by sequence; names come from custom labels (a blank
    // one reads as the view's label); an inactive view isn't offered.
    List<TimeShiftController.ViewOption> views = TimeShiftController.getViews();
    Assert.areEqual(3, views.size());
    Assert.areEqual('All', views[0].value);
    Assert.areEqual(System.Label.Time_Shift_View_All, views[0].label);
    Assert.areEqual('Sales', views[1].value);
    Assert.areEqual('Sales', views[1].label);
    Assert.areEqual(System.Label.Time_Shift_View_Service, views[2].label);

    // Setup sees every view, with the label behind its name.
    List<TimeShiftSetupController.ViewDraft> drafts = TimeShiftSetupController.getViewDrafts();
    Assert.areEqual(4, drafts.size());
    Assert.areEqual('Time_Shift_View_All', drafts[0].labelName);
    Assert.isTrue(drafts[0].active, 'All is always offered');
    Assert.isFalse(drafts[2].active, drafts[2].developerName);

    // Making a view inactive saves just its record, as it was but for Active.
    Assert.areEqual(
      'test-job',
      TimeShiftSetupController.saveViews(
          '[{"developerName":"Service","active":false},{"developerName":"Sales","active":true}]'
        )
        .jobId
    );
    Metadata.CustomMetadata m = TimeShiftSetupController.viewMetadata(TimeShiftConfig.testViews[0], false);
    Assert.areEqual('Time_Shift_View.Service', m.fullName);
    Assert.areEqual('Service', m.label);
    Assert.areEqual(3, m.values.size());
    Assert.isNull(
      TimeShiftSetupController.saveViews('[{"developerName":"Sales","active":true}]').jobId,
      'nothing changed, nothing deployed'
    );
    for (String bad : new List<String>{ '[{"developerName":"Nope"}]', '[{"developerName":"All","active":false}]' }) {
      try {
        TimeShiftSetupController.saveViews(bad);
        Assert.fail('not saved: ' + bad);
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
  }

  @IsTest
  static void reportsEinsteinActivityCaptureForTheEmailSyncCheck() {
    // Whatever this org has, the answer says whether it's in use.
    TimeShiftSetupController.ActivityCapture found = TimeShiftSetupController.getOrgFit().activityCapture;
    Assert.isNotNull(found);
    Assert.areEqual(found.users > 0, found.inUse);
    // With licences assigned, setup can say who has it.
    TimeShiftSetupController.ActivityCapture assigned = new TimeShiftSetupController.ActivityCapture();
    assigned.inUse = true;
    assigned.users = 12;
    assigned.licences.add('Standard Einstein Activity Capture');
    TimeShiftSetupController.testActivityCapture = assigned;
    TimeShiftSetupController.ActivityCapture reported = TimeShiftSetupController.getOrgFit().activityCapture;
    Assert.isTrue(reported.inUse);
    Assert.areEqual(12, reported.users);
    Assert.areEqual('Standard Einstein Activity Capture', reported.licences[0]);
  }

  @IsTest
  static void listsDataModelObjectsDataCloudNamesAndSkipsUnknownOnes() {
    // A name Data 360 offers that this org can't describe is left out; no
    // DMOs here, so the list is empty rather than an error.
    TimeShiftSetupController.testDmoNames = new List<String>{ 'NotHere__dlm' };
    Assert.isTrue(TimeShiftSetupController.getObjects('dmo', 'Contact', null).isEmpty());
    // Objects the global describe lists are still found by name.
    Assert.areEqual(Contact.SObjectType, TimeShiftConfig.sObjectType('Contact'));
    Assert.isNull(TimeShiftConfig.sObjectType('NotHere__dlm'));
    Assert.isNull(TimeShiftConfig.sObjectType(''));
  }

  @IsTest
  static void data360StatusSaysWhetherTheAddOnIsThere() {
    // Ready where the add-on is deployed; where it isn't, a reason says
    // whether the org lacks Data 360 or only the add-on. Either way it holds
    // in any org.
    TimeShiftSetupController.Data360Status status = TimeShiftSetupController.getData360Status();
    Assert.areEqual(TimeShiftData360Provider.addOnInstalled(), status.ready);
    Assert.areEqual(status.ready, status.reason == null);
    if (!status.ready) {
      Assert.isTrue(status.reason.contains('Data 360'), status.reason);
    }

    TimeShiftSetupController.testData360Status = new TimeShiftSetupController.Data360Status(false, 'Not here.');
    Assert.isFalse(TimeShiftSetupController.getData360Status().ready);
    Assert.areEqual('Not here.', TimeShiftSetupController.getData360Status().reason);
  }

  @IsTest
  static void data360SourcesKeepTheirDataSpace() {
    // Without Data 360 there are none to choose from, and that's no error.
    Assert.isNotNull(TimeShiftSetupController.getDataSpaces());
    TimeShiftSetupController.testDataSpaces = new List<TimeShiftSetupController.Option>{
      new TimeShiftSetupController.Option('default', 'default', null),
      new TimeShiftSetupController.Option('Europe', 'Europe', null)
    };
    Assert.areEqual(2, TimeShiftSetupController.getDataSpaces().size());

    // Saved on the record, and read back for editing.
    TimeShiftSetupController.SourceDraft d = (TimeShiftSetupController.SourceDraft) JSON.deserialize(
      '{"kind": "Data 360", "objectName": "Reservation__dlm", "dataSpace": "Europe"}',
      TimeShiftSetupController.SourceDraft.class
    );
    Time_Shift_Source__mdt record = d.toRecord();
    Assert.areEqual('Europe', record.Data_Space__c);
    Assert.areEqual('Europe', new TimeShiftSetupController.SourceDraft(record).dataSpace);
  }

  @IsTest
  static void enhancedEmailReadsEmailMessagesInsteadOfEmailTasks() {
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      fitted('Emails', 'Contact', null, 'Contact Emails', true),
      fitted('Emails_Every', 'Contact', 'SharedActivities', 'Contact Emails', false),
      fitted('Email_Messages', 'Contact', 'EnhancedEmail', 'Contact Emails', false)
    };
    // Enhanced Email alone: Email Messages, not the email tasks.
    Map<String, Boolean> target = TimeShiftSetupController.targets(new Set<String>{ 'EnhancedEmail' });
    Assert.isTrue(target.get('Email_Messages'));
    Assert.isFalse(target.get('Emails'));
    // With Shared Activities too, each needing one setting: Enhanced Email wins,
    // so emails are never read twice.
    target = TimeShiftSetupController.targets(new Set<String>{ 'EnhancedEmail', 'SharedActivities' });
    Assert.isTrue(target.get('Email_Messages'));
    Assert.isFalse(target.get('Emails_Every'));
    Assert.isFalse(target.get('Emails'));
    // Neither: the email tasks.
    target = TimeShiftSetupController.targets(new Set<String>());
    Assert.isTrue(target.get('Emails'));
    Assert.isFalse(target.get('Email_Messages'));
  }

  @IsTest
  static void fitsTheTimelineToTheOrg() {
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      fitted('Tasks', 'Contact', null, 'Contact Tasks', true),
      fitted('Tasks_Every', 'Contact', 'SharedActivities', 'Contact Tasks', false),
      fitted('Person_Tasks', 'PersonAccount', 'PersonAccounts', null, false),
      fitted('Cases', 'Contact', null, null, false)
    };
    // An org with Shared Activities but no person accounts; the install uses neither.
    TimeShiftSetupController.testFeatures = new Set<String>{ 'SharedActivities' };
    Map<String, TimeShiftSetupController.FitFeature> features = new Map<String, TimeShiftSetupController.FitFeature>();
    for (TimeShiftSetupController.FitFeature f : TimeShiftSetupController.getOrgFit().features) {
      features.put(f.key, f);
    }
    TimeShiftSetupController.FitFeature shared = features.get('SharedActivities');
    Assert.isTrue(shared.enabled, 'the org has it');
    Assert.isFalse(shared.used, 'the timeline does not use it yet');
    Assert.areEqual(new List<String>{ 'Contact Tasks (every contact)' }.size(), shared.turnsOn.size());
    Assert.isTrue(shared.turnsOn[0].contains('Tasks_Every'), String.valueOf(shared.turnsOn));
    Assert.isTrue(shared.turnsOff[0].contains('Tasks'), String.valueOf(shared.turnsOff));
    Assert.isFalse(features.get('PersonAccounts').enabled);
    Assert.isTrue(features.get('PersonAccounts').turnsOn[0].contains('Person_Tasks'));
    // Sources for a setting the timeline doesn't use are out of sight.
    Set<String> shown = new Set<String>();
    for (TimeShiftSetupController.SourceSummary s : TimeShiftSetupController.getSources()) {
      shown.add(s.developerName);
    }
    Assert.areEqual(new Set<String>{ 'Tasks', 'Cases' }, shown);

    // Using Shared Activities: the every-contact variant on, the WhoId one off,
    // the source tied to no setting (Cases) left alone.
    Map<String, Boolean> target = TimeShiftSetupController.targets(new Set<String>{ 'SharedActivities' });
    Assert.isTrue(target.get('Tasks_Every'));
    Assert.isFalse(target.get('Tasks'));
    Assert.isFalse(target.containsKey('Cases'));
    Assert.isFalse(target.get('Person_Tasks'));
    Assert.areEqual(
      'test-job',
      TimeShiftSetupController.applyOrgFit(new List<String>{ 'SharedActivities' }).jobId
    );
    // Back to the install's assumption: nothing to change, nothing deployed.
    Assert.isNull(TimeShiftSetupController.applyOrgFit(new List<String>()).jobId);
    // Not a setting the org doesn't have.
    try {
      TimeShiftSetupController.applyOrgFit(new List<String>{ 'PersonAccounts' });
      Assert.fail('Person Accounts is off here');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Person Accounts'));
    }

    // A switch keeps the org-fit fields on the record.
    TimeShiftSetupController.SourceDraft d = new TimeShiftSetupController.SourceDraft(
      TimeShiftConfig.testSources[1]
    );
    Map<String, Object> values = new Map<String, Object>();
    for (Metadata.CustomMetadataValue v : TimeShiftSetupController.sourceMetadata(d).values) {
      values.put(v.field, v.value);
    }
    Assert.areEqual(true, values.get('Org_Fit__c'));
    Assert.areEqual('SharedActivities', values.get('Requires__c'));
    Assert.areEqual('Contact Tasks', values.get('Variant_Group__c'));
  }

  @IsTest
  static void eventsLinkThroughEveryContactOnThem() {
    // Every contact on an event comes with Shared Activities: out of sight
    // until the timeline uses it.
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>();
    for (TimeShiftSetupController.Link l : TimeShiftSetupController.getLinks('Contact', 'Event')) {
      Assert.isFalse(l.everyContact, 'hidden without Shared Activities');
    }
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      fitted('Every', 'Contact', 'SharedActivities', null, true)
    };
    List<TimeShiftSetupController.Link> links = TimeShiftSetupController.getLinks('Contact', 'Event');
    TimeShiftSetupController.Link every = links[0];
    Assert.areEqual('EventRelation', every.junctionObject, 'every contact on it comes first');
    Assert.areEqual('RelationId', every.junctionParentField);
    Assert.areEqual('EventId', every.junctionRecordField);
    Assert.areEqual('Contact', every.parentLabel, 'the diagram shows the page, not Calendar');
    Assert.isTrue(every.note.contains('invitees'));
    Boolean who = false;
    for (TimeShiftSetupController.Link l : links) {
      who = who || l.parentField == 'WhoId';
    }
    Assert.isTrue(who, 'the primary contact (WhoId) is still a choice');
  }

  @IsTest
  static void accountAndPersonAccountPagesLinkTheirOwnWays() {
    Set<String> forAccounts = new Set<String>();
    for (TimeShiftSetupController.Option o : TimeShiftSetupController.getObjects('standard', 'Account', null)) {
      forAccounts.add(o.value);
    }
    Assert.isTrue(forAccounts.contains('Case'), 'cases link to an Account');
    Assert.isTrue(forAccounts.contains('Opportunity'));

    // A person account links by its Account lookups and its Contact ones.
    Set<String> fields = new Set<String>();
    for (TimeShiftSetupController.Link l : TimeShiftSetupController.getLinks('PersonAccount', 'Case')) {
      fields.add(l.parentField);
    }
    Assert.isTrue(fields.contains('AccountId'), String.valueOf(fields));
    Assert.isTrue(fields.contains('ContactId'), String.valueOf(fields));
    // Tasks: Related To (the Account side), Name (the Contact side), and
    // Account, which Salesforce fills from either; never "Name is this Account".
    Map<String, TimeShiftSetupController.Link> taskLinks = new Map<String, TimeShiftSetupController.Link>();
    for (TimeShiftSetupController.Link l : TimeShiftSetupController.getLinks('PersonAccount', 'Task')) {
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
    for (
      TimeShiftSetupController.Option o : TimeShiftSetupController.getObjects('standard', 'PersonAccount', null)
    ) {
      tasks = tasks || o.value == 'Task';
    }
    Assert.isTrue(tasks, 'tasks link to the person through WhoId');
  }

  @IsTest
  static void describesFieldsWithPicklistValues() {
    TimeShiftSetupController.FieldInfo status;
    for (TimeShiftSetupController.FieldInfo f : TimeShiftSetupController.getFields('Task')) {
      if (f.name == 'Status') {
        status = f;
      }
    }
    Assert.isNotNull(status);
    Assert.areEqual('picklist', status.type);
    Assert.isFalse(status.values.isEmpty());
    // Lookups say where they lead, so the wizard can follow them.
    TimeShiftSetupController.FieldInfo account;
    for (TimeShiftSetupController.FieldInfo f : TimeShiftSetupController.getFields('Contact')) {
      if (f.name == 'AccountId') {
        account = f;
      }
    }
    Assert.areEqual('Account', account.referenceTo);
    Assert.areEqual('Account', account.relationshipName);
    try {
      TimeShiftSetupController.getFields('No_Such_Object__c');
      Assert.fail('A missing object should say so');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('No_Such_Object__c'));
    }
  }

  @IsTest
  static void previewPlotsADraftForARecord() {
    Id customer = [SELECT Id FROM Contact LIMIT 1].Id;
    TimeShiftSetupController.SourceDraft d = orderDraft();
    TimeShiftSetupController.Preview all = TimeShiftSetupController.preview(JSON.serialize(d), customer);
    Assert.areEqual(2, all.total);
    Assert.isTrue(all.events[0].title.startsWith('Order '));

    d.conditions.add(condition('Status', 'equals', 'Completed', 'text'));
    TimeShiftSetupController.Preview delivered = TimeShiftSetupController.preview(
      JSON.serialize(d),
      customer
    );
    Assert.areEqual(1, delivered.total);
    Assert.areEqual(0, TimeShiftSetupController.preview(JSON.serialize(d), null).total);
  }

  @IsTest
  static void previewSaysWhenADraftCantBeRead() {
    Id customer = [SELECT Id FROM Contact LIMIT 1].Id;
    TimeShiftSetupController.SourceDraft d = orderDraft();
    d.filter = 'Not_A_Field__c = 1';
    TimeShiftSetupController.Preview p = TimeShiftSetupController.preview(JSON.serialize(d), customer);
    Assert.areEqual(0, p.total);
    Assert.isFalse(p.problems.isEmpty(), 'A broken filter is a problem, not an error');
  }

  @IsTest
  static void countsTheRecordsEachRangeWouldRead() {
    TimeShiftSetupController.Volume v = TimeShiftSetupController.getVolumes(JSON.serialize(orderDraft()));
    Assert.areEqual(2, v.total);
    Assert.areEqual(1, v.parents, 'Both orders are one Contact\'s');
    Assert.areEqual(5, v.ranges.size());
    Assert.areEqual(2, v.ranges[0].count, 'Both orders are in the last 3 months');

    TimeShiftSetupController.SourceDraft delivered = orderDraft();
    delivered.conditions.add(condition('Status', 'equals', 'Completed', 'text'));
    Assert.areEqual(1, TimeShiftSetupController.getVolumes(JSON.serialize(delivered)).total);

    TimeShiftSetupController.SourceDraft apex = new TimeShiftSetupController.SourceDraft();
    apex.kind = 'Apex';
    Assert.isNull(TimeShiftSetupController.getVolumes(JSON.serialize(apex)).total);
  }

  @IsTest
  static void aSourceCanLookBackLessFarThanTheTimeline() {
    Id customer = [SELECT Id FROM Contact LIMIT 1].Id;
    TimeShiftSetupController.SourceDraft d = orderDraft();
    d.historyMonths = 0;
    Assert.areEqual(0, TimeShiftSetupController.preview(JSON.serialize(d), customer).total);
    d.historyMonths = 1;
    Assert.areEqual(2, TimeShiftSetupController.preview(JSON.serialize(d), customer).total);
  }

  @IsTest
  static void conditionsBecomeSafeFilters() {
    TimeShiftSetupController.SourceDraft d = new TimeShiftSetupController.SourceDraft();
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

  @IsTest
  static void savesANewSourceUnderAFreshName() {
    TimeShiftSetupController.SourceDraft d = orderDraft();
    TimeShiftSetupController.DetailDraft detail = new TimeShiftSetupController.DetailDraft();
    detail.field = 'Description';
    detail.label = 'Notes';
    detail.format = 'Text';
    d.details.add(detail);
    TimeShiftSetupController.SaveTicket ticket = TimeShiftSetupController.save(JSON.serialize(d));
    Assert.areEqual('test-job', ticket.jobId);
    Assert.areEqual('Orders_from_setup', ticket.developerName);

    Assert.areEqual('Order_Placed_2', TimeShiftSetupController.uniqueName('Order Placed'));
    Assert.areEqual('Source_2026_orders', TimeShiftSetupController.uniqueName('2026 orders!'));
    d.developerName = 'Order_Placed';
    Metadata.CustomMetadata m = TimeShiftSetupController.sourceMetadata(d);
    Assert.areEqual('Time_Shift_Source.Order_Placed', m.fullName);
  }

  @IsTest
  static void aSourceKeepsAtMostFourDetailFields() {
    TimeShiftSetupController.SourceDraft d = orderDraft();
    for (String field : new List<String>{ 'Description', 'Status', 'Name', 'Type', 'Phone' }) {
      TimeShiftSetupController.DetailDraft detail = new TimeShiftSetupController.DetailDraft();
      detail.field = field;
      d.details.add(detail);
    }
    List<Time_Shift_Detail_Field__mdt> kept = d.detailRecords();
    Assert.areEqual(4, kept.size());
    Assert.areEqual('Type', kept[3].Field__c);
  }

  @IsTest
  static void aSourceKeepsOneHighlightAndItRoundTrips() {
    TimeShiftSetupController.SourceDraft d = orderDraft();
    for (String field : new List<String>{ 'IsHighPriority', 'IsClosed' }) {
      TimeShiftSetupController.HighlightDraft h = new TimeShiftSetupController.HighlightDraft();
      h.field = field;
      h.icon = 'utility:flag';
      h.colour = '#C23934';
      d.highlights.add(h);
    }
    // Without a field a highlight is no highlight.
    d.highlights.add(new TimeShiftSetupController.HighlightDraft());
    List<Time_Shift_Highlight__mdt> records = d.highlightRecords();
    Assert.areEqual(1, records.size());
    Assert.areEqual('IsHighPriority', records[0].Field__c);
    TimeShiftSetupController.HighlightDraft back = new TimeShiftSetupController.HighlightDraft(records[0]);
    Assert.areEqual('IsHighPriority', back.field);
    Assert.areEqual('utility:flag', back.icon);
    Assert.areEqual('#C23934', back.colour);
  }

  @IsTest
  static void savingPlacesTheSourceInItsLegendOrder() {
    TimeShiftSetupController.SourceDraft d = orderDraft();
    // New at the top, then the two order sources (sequence 10 and 11 now).
    d.legendOrder = new List<String>{ TimeShiftSetupController.THIS_SOURCE, 'Order_Placed', 'Order_Delivered' };
    List<Metadata.CustomMetadata> moved = TimeShiftSetupController.reordered(d);
    Assert.areEqual(10, d.sequence);
    Assert.areEqual(2, moved.size(), 'both move down a place');
    Assert.areEqual('Time_Shift_Source.Order_Placed', moved[0].fullName);
    Decimal placed;
    for (Metadata.CustomMetadataValue v : moved[0].values) {
      if (v.field == 'Sequence__c') {
        placed = (Decimal) v.value;
      }
    }
    Assert.areEqual(20, placed);

    // A source already in its place isn't redeployed; no order, no change.
    d.legendOrder = new List<String>{ 'Order_Placed', TimeShiftSetupController.THIS_SOURCE };
    Assert.areEqual(0, TimeShiftSetupController.reordered(d).size());
    Assert.areEqual(20, d.sequence);
    d.legendOrder = null;
    Assert.areEqual(0, TimeShiftSetupController.reordered(d).size());
  }

  @IsTest
  static void saveSaysWhatIsMissing() {
    TimeShiftSetupController.SourceDraft d = new TimeShiftSetupController.SourceDraft();
    d.kind = 'Salesforce';
    try {
      TimeShiftSetupController.save(JSON.serialize(d));
      Assert.fail('An empty draft should not save');
    } catch (AuraHandledException e) {
      Assert.areEqual('Before saving, choose a name, an object, a date, how it links to the record.', e.getMessage());
    }
    d.kind = 'Apex';
    d.label = 'Mine';
    try {
      TimeShiftSetupController.save(JSON.serialize(d));
      Assert.fail('An Apex source needs a class');
    } catch (AuraHandledException e) {
      Assert.areEqual('Before saving, choose an Apex class.', e.getMessage());
    }
  }

  @IsTest
  static void switchesASourceOnAndOff() {
    TimeShiftSetupController.SaveTicket ticket = TimeShiftSetupController.setActive('Order_Placed', false);
    Assert.areEqual('Order_Placed', ticket.developerName);
    try {
      TimeShiftSetupController.setActive('No_Such_Source', true);
      Assert.fail('A missing source should say so');
    } catch (AuraHandledException e) {
      Assert.areEqual('That source no longer exists.', e.getMessage());
    }
  }

  @IsTest
  static void removesASourceBySwitchingItOffAndHidingIt() {
    TimeShiftSetupController.SaveTicket ticket = TimeShiftSetupController.remove('Order_Placed');
    Assert.areEqual('Order_Placed', ticket.developerName);
    TimeShiftSetupController.SourceDraft d = new TimeShiftSetupController.SourceDraft(
      TimeShiftTestData.source('Order_Placed')
    );
    d.active = false;
    d.removed = true;
    Map<String, Object> values = new Map<String, Object>();
    for (Metadata.CustomMetadataValue v : TimeShiftSetupController.sourceMetadata(d).values) {
      values.put(v.field, v.value);
    }
    Assert.areEqual(true, values.get('Removed__c'));
    Assert.areEqual(false, values.get('Active__c'));
    try {
      TimeShiftSetupController.remove('No_Such_Source');
      Assert.fail('A missing source should say so');
    } catch (AuraHandledException e) {
      Assert.areEqual('That source no longer exists.', e.getMessage());
    }
    for (TimeShiftSetupController.SourceSummary s : TimeShiftSetupController.getSources()) {
      Assert.areEqual('Contact', s.parentObject);
      Assert.isTrue(new Set<String>{ 'standard', 'custom', 'dmo', 'apex' }.contains(s.type), s.type);
    }
  }

  @IsTest
  static void findsApexProviders() {
    Set<String> names = new Set<String>();
    for (TimeShiftSetupController.Option o : TimeShiftSetupController.getApexProviders()) {
      names.add(o.value);
    }
    Assert.isFalse(names.contains('TimeShiftSoqlProvider'), 'Built-in providers need no class');
  }

  @IsTest
  static void publishesTheDeploymentResult() {
    Metadata.DeployResult result = new Metadata.DeployResult();
    result.id = '0Af000000000001';
    result.status = Metadata.DeployStatus.Succeeded;
    Test.startTest();
    new TimeShiftSetupController.SaveResult('Order_Placed').handleResult(result, null);
    Assert.areEqual(1, Limits.getPublishImmediateDml(), 'The result is published');
    Test.stopTest();
  }

  @IsTest
  static void conditionsRoundTripThroughTheFilterText() {
    TimeShiftSetupController.SourceDraft d = orderDraft();
    d.conditions = new List<TimeShiftSetupController.Condition>();
    d.conditions.add(condition('Status', 'notEquals', 'Can\'t be 100%', 'text'));
    d.conditions.add(condition('Subject', 'contains', 'order_1', 'text'));
    d.conditions.add(condition('IsClosed', 'equals', 'true', 'boolean'));
    d.conditions.add(condition('Priority', 'blank', '', 'text'));
    d.conditions.add(condition('ActivityDate', 'greater', '2026-01-31', 'date'));
    d.conditions.add(condition('CreatedDate', 'less', '2026-02-01', 'datetime'));
    d.conditions.add(condition('Amount', 'equals', '12.5', 'number'));
    String text = d.filterText();

    List<TimeShiftSetupController.Condition> back = TimeShiftSetupController.conditionsOf(text);
    Assert.areEqual(7, back.size());
    TimeShiftSetupController.SourceDraft again = orderDraft();
    again.conditions = back;
    Assert.areEqual(text, again.filterText(), 'The conditions write the same filter');
    Assert.areEqual('Can\'t be 100%', back[0].value);
    Assert.areEqual('order_1', back[1].value);
    Assert.areEqual('2026-02-01', back[5].value);
  }

  @IsTest
  static void aFilterTheBuilderCannotShowIsKeptAsText() {
    for (String text : new List<String>{
      'TaskSubtype = null OR TaskSubtype NOT IN (\'Call\', \'Email\')',
      'Subject LIKE \'%a%\' OR Subject LIKE \'%b%\'',
      '(Status = \'Open\')',
      'Status = \'Open\' AND Name IN (\'A\')',
      'Status = \'it\' AND OR'
    }) {
      Assert.isNull(TimeShiftSetupController.conditionsOf(text), text);
    }
    Assert.isNull(TimeShiftSetupController.conditionsOf(null));
    Assert.areEqual(1, TimeShiftSetupController.conditionsOf('Status = \'A AND B\'').size(), 'AND inside a value');
  }
}
