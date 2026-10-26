# Config Guide

A short mock guide, to check that Time Trail Setup reads markdown from GitHub. Replace it with the real guide.

## Before you start

You need the **Customize Application** permission to add and change sources.

- Two permission sets come with the timeline.
- Data 360 is *optional*.

## Assign the permission sets

1. In Setup, open **Permission Sets**.
2. Assign `Time Trail` to people who see the timeline.
3. Assign `Time Trail Setup` to admins who manage it.

> [!NOTE]
> What each person sees still depends on the objects and fields they can read.

## Add a source

Open **Customize**, choose the record page, then **Add a source**. See the [FAQs](faqs.md#why-does-saving-take-a-few-seconds) for why saving takes a moment.

## Apex sources

```apex
public with sharing class LoyaltyProvider implements TimeShiftProvider {
  public List<TimeShiftController.EngagementEvent> getEvents(TimeShiftContext context) {
    return new List<TimeShiftController.EngagementEvent>();
  }
}
```

---

Questions? Read the [FAQs](faqs.md), or go back to [Before you start](#before-you-start).
