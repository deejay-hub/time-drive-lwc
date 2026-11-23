# Contributing to Time Drive

## General guidelines

The best thing about the trailblazer community is contributions. Time Drive needs lots of help and will need people to contribute who have a diversity of skills. However, please ask yourself "should Time Drive do X?" as the answer is sometimes "no". **So ask first!** It might save you some time and energy.

#### Design principles

1.  Time Drive can be used across industries, apps and objects. If a change is not generic don't add it.
2.  Time Drive is simple and intuitive to use. Less is more.
3.  Lightning base components and SLDS will be used in preference to custom components.
4.  Time Drive can be used in any language and locale. If you can't translate/localise it, don't add it. Every string is a custom label in `scripts/labels/catalogue.py`.
5.  Time Drive scales with the data. A source counts its items for the summary and reads rows only for the days on screen.

#### Flow

- Fork the Project
- Create your Feature Branch (git checkout -b feature/NewFeature)
- Commit your Changes (git commit -m 'Add some NewFeature')
- Push to the Branch (git push origin feature/NewFeature)
- Open a Pull Request

#### Before you open a Pull Request

- `npm run lint` and `npm run prettier:verify` pass
- `npm run test:unit` passes
- The Apex tests pass in a scratch org, with coverage of 85% or more
- New or changed strings are in the label catalogue, with `python3 -I scripts/labels/generate.py` run
- [changelog.md](/changelog.md) says what changed
