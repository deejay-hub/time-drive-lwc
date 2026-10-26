// Timeline load test (time-shift-person only): one chunk of a Contact's
// activity, spread over 2 years back and 1 ahead, with a few spike days.
// Every record's Subject starts [Load test]. Placeholders are filled in by
// the runner: __CONTACT__, __OFFSET__, __COUNT__, __SPIKE_SIZE__.
Id contactId = '__CONTACT__';
Integer offset = __OFFSET__;
Integer count = __COUNT__;
Integer spikeSize = __SPIKE_SIZE__;
List<Integer> spikeDays = new List<Integer>{ -3, -40, -200, -500, 30 };
Integer spikeRecords = spikeSize * spikeDays.size();

List<Task> tasks = new List<Task>();
List<Event> events = new List<Event>();
List<Opportunity> opps = new List<Opportunity>();
for (Integer i = offset; i < offset + count; i++) {
  Integer dayOffset = i < spikeRecords ? spikeDays[i / spikeSize] : Math.mod(i * 7919 + 13, 1095) - 730;
  Date day = Date.today().addDays(dayOffset);
  Integer hour = 8 + Math.mod(i * 31, 10);
  Integer kind = Math.mod(i, 20);
  String subject = '[Load test] ' + i;
  if (kind < 10) {
    tasks.add(new Task(WhoId = contactId, Subject = subject + ' follow-up', ActivityDate = day, Status = 'Completed', Priority = 'Normal', Description = 'Load test task ' + i));
  } else if (kind < 14) {
    tasks.add(new Task(WhoId = contactId, Subject = subject + ' call', ActivityDate = day, Status = 'Completed', TaskSubtype = 'Call', CallDurationInSeconds = 300, Description = 'Load test call ' + i));
  } else if (kind < 19) {
    Datetime at = Datetime.newInstance(day, Time.newInstance(hour, 0, 0, 0));
    events.add(new Event(WhoId = contactId, Subject = subject + ' meeting', StartDateTime = at, EndDateTime = at.addMinutes(30), Description = 'Load test event ' + i));
  } else {
    opps.add(new Opportunity(Name = subject + ' deal', CloseDate = day, StageName = 'Prospecting', Amount = 1000 + Math.mod(i, 50) * 100));
  }
}
insert tasks;
insert events;
insert opps;
List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
for (Opportunity o : opps) {
  roles.add(new OpportunityContactRole(OpportunityId = o.Id, ContactId = contactId, Role = 'Decision Maker'));
}
insert roles;
System.debug('SEEDED tasks=' + tasks.size() + ' events=' + events.size() + ' opps=' + opps.size() + ' cpu=' + Limits.getCpuTime());
